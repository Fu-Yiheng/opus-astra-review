#!/usr/bin/env bash
# 让 Codex 里的 Astra 对项目成果做只读审核（走 ChatGPT 订阅，不用 API key）。
#
#   astra.sh review  <项目目录> <审核目录>   第 1 轮：新开会话，读 <审核目录>/BRIEF.md
#   astra.sh recheck <项目目录> <审核目录>   复审：接上一轮的会话，读最新的 rN_response.md
#   astra.sh doctor [--live]                检查运行环境；--live 再真调一次模型（约 2k tokens）
#
# 产物都在 <审核目录>：rN_prompt.md  rN_review.json  rN_astra.log  session_id
# 环境变量：ASTRA_MODEL   默认 gpt-6-astra
#           ASTRA_EFFORT  默认 xhigh（不要用 ultra：会自动派生子代理，极耗额度）
#           ASTRA_TIMEOUT 秒，默认 3600
#           ASTRA_CODEX   codex.exe 路径，默认自动查找
set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL="${ASTRA_MODEL:-gpt-6-astra}"
EFFORT="${ASTRA_EFFORT:-xhigh}"
TIMEOUT="${ASTRA_TIMEOUT:-3600}"

die() { echo "astra.sh: $*" >&2; exit 2; }

# codex.exe 不在 PATH 上，而且所在的 bin/<哈希>/ 目录会随 Codex 应用更新而变
find_codex() {
  if [ -n "${ASTRA_CODEX:-}" ]; then echo "$ASTRA_CODEX"; return; fi
  if command -v codex >/dev/null 2>&1; then command -v codex; return; fi
  local p=""
  if [ -f "$HOME/.codex/config.toml" ]; then
    p=$(grep -o "CODEX_CLI_PATH = '[^']*'" "$HOME/.codex/config.toml" | head -1 | sed "s/^CODEX_CLI_PATH = '//; s/'\$//" || true)
    if [ -n "$p" ]; then
      p=$(cygpath -u "$p")
      [ -f "$p" ] && { echo "$p"; return; }
    fi
  fi
  p=$(ls -t "$(cygpath -u "$LOCALAPPDATA")"/OpenAI/Codex/bin/*/codex.exe 2>/dev/null | head -1 || true)
  [ -n "$p" ] && { echo "$p"; return; }
  die "找不到 codex.exe，请设置 ASTRA_CODEX"
}

# Astra 的 PowerShell 处于 ConstrainedLanguage 模式，自己输出的中文必乱码；原生程序的输出直通，中文正常。
# Codex 自带的 rg.exe 能在沙箱里运行（Git 的 MSYS 工具不行：CreateFileMapping 被拒）
find_rg() {
  local p
  p=$(ls -t "$(cygpath -u "$LOCALAPPDATA")"/OpenAI/Codex/bin/*/rg.exe 2>/dev/null | head -1 || true)
  [ -n "$p" ] && cygpath -w "$p"
}

doctor() {
  local bad=0 codex rg st
  echo "astra-review 环境检查"
  if command -v cygpath >/dev/null && command -v powershell >/dev/null; then
    echo "[OK] Git Bash + PowerShell"
  else
    echo "[X]  需要在 Windows 的 Git Bash 里运行（装 Git for Windows）"; bad=1
  fi
  if codex=$(find_codex 2>/dev/null); then
    echo "[OK] codex: $codex ($("$codex" --version 2>/dev/null || echo 版本未知))"
    st=$("$codex" login status 2>&1 || true)
    case "$st" in
      *"Logged in"*) echo "[OK] 登录状态: $st" ;;
      *) echo "[X]  Codex 未登录：打开 Codex 应用，用 ChatGPT 账号登录"; bad=1 ;;
    esac
  else
    echo "[X]  找不到 codex.exe：安装 Codex 桌面应用，或设置 ASTRA_CODEX"; bad=1
  fi
  if [ -f "$HOME/.codex/models_cache.json" ]; then
    if grep -q "\"slug\": \"$MODEL\"" "$HOME/.codex/models_cache.json"; then
      echo "[OK] 模型列表里有 $MODEL"
    else
      echo "[!]  模型列表里没有 $MODEL，可能当前套餐不支持；可改用 ASTRA_MODEL=gpt-6.1-sol"
    fi
  fi
  if rg=$(find_rg); then echo "[OK] rg: $rg"; else echo "[!]  没找到 Codex 自带的 rg.exe，Astra 只能用 findstr 读文件"; fi
  if [ "${1:-}" = "--live" ] && [ $bad -eq 0 ]; then
    local out
    out=$(echo "只回复：OK" | timeout 300 "$codex" exec --ignore-user-config -m "$MODEL" -c 'model_reasoning_effort="low"' \
      -c 'windows.sandbox="unelevated"' -s read-only --skip-git-repo-check --ephemeral 2>&1 | tail -3 || true)
    case "$out" in
      *OK*) echo "[OK] 实际调用 $MODEL 成功" ;;
      *) echo "[X]  实际调用 $MODEL 失败，输出末尾："; echo "$out"; bad=1 ;;
    esac
  fi
  [ $bad -eq 0 ] && echo "环境正常" || echo "有问题需要处理（见上面的 [X]）"
  return $bad
}

if [ "${1:-}" = doctor ]; then doctor "${2:-}"; exit $?; fi

[ $# -eq 3 ] || die "用法: astra.sh review|recheck <项目目录> <审核目录>，或 astra.sh doctor [--live]"
MODE="$1"
[ -d "$2" ] || die "项目目录不存在: $2"
[ -d "$3" ] || die "审核目录不存在: $3"
PROJECT="$(cd "$2" && pwd)"
RDIR="$(cd "$3" && pwd)"
[ -f "$RDIR/BRIEF.md" ] || die "缺少 $RDIR/BRIEF.md"
[ -f "$RDIR/user_messages.md" ] || echo "astra.sh: 提醒：没有 user_messages.md，Astra 将无法核对用户原话" >&2

# 已完成的轮数 = 已有 rN_review.json 中最大的 N
last=0
for f in "$RDIR"/r*_review.json; do
  [ -e "$f" ] || continue
  n=$(basename "$f"); n=${n#r}; n=${n%%_*}
  [ "$n" -gt "$last" ] && last=$n
done
N=$((last + 1))

case "$MODE" in
  review)
    [ "$last" -eq 0 ] || die "$RDIR 已有第 $last 轮审核；复审用 recheck，重新审核请换一个审核目录"
    TEMPLATE="$SKILL_DIR/prompts/review.md" ;;
  recheck)
    [ "$last" -ge 1 ] || die "还没有第 1 轮审核"
    [ -s "$RDIR/session_id" ] || die "缺少 $RDIR/session_id"
    [ -f "$RDIR/r${last}_response.md" ] || die "缺少 r${last}_response.md，先写回应再复审"
    TEMPLATE="$SKILL_DIR/prompts/recheck.md" ;;
  *) die "未知模式: $MODE（应为 review 或 recheck）" ;;
esac

PROMPT="$RDIR/r${N}_prompt.md"
OUT="$RDIR/r${N}_review.json"
LOG="$RDIR/r${N}_astra.log"

# 给 Windows 程序用的路径（正斜杠形式，PowerShell 和 codex 都认）
w() { cygpath -m "$1"; }

t=$(cat "$TEMPLATE")
t=${t//'{{ROUND}}'/$N}
t=${t//'{{PREV_ROUND}}'/$last}
t=${t//'{{PROJECT_DIR}}'/$(w "$PROJECT")}
t=${t//'{{BRIEF}}'/$(w "$RDIR/BRIEF.md")}
t=${t//'{{USER_MESSAGES}}'/$(w "$RDIR/user_messages.md")}
t=${t//'{{PREV_REVIEW}}'/$(w "$RDIR/r${last}_review.json")}
t=${t//'{{RESPONSE}}'/$(w "$RDIR/r${last}_response.md")}
RG=$(find_rg) || { RG="rg.exe"; echo "astra.sh: 提醒：没找到 Codex 自带的 rg.exe，Astra 只能用 findstr" >&2; }
t=${t//'{{RG}}'/$RG}
printf '%s\n' "$t" > "$PROMPT"

CODEX=$(find_codex)
# windows.sandbox 必须是 unelevated：elevated 沙箱从 Claude Code 里启动时，
# Astra 的每条命令都会失败（setup refresh had errors）
# --ignore-user-config：不加载用户 Codex 配置里的插件、MCP、memory、notify 钩子。
# 实测每次调用的固定开销从约 7.8k 降到 2.2k tokens，审稿人也不会受 Codex memory 影响；
# 登录凭据（auth.json）不受影响。
common=(
  --ignore-user-config
  -m "$MODEL"
  -c "model_reasoning_effort=\"$EFFORT\""
  -c 'windows.sandbox="unelevated"'
  -c 'sandbox_mode="read-only"'
  --skip-git-repo-check
  --output-schema "$(cygpath -w "$SKILL_DIR/schema/review.schema.json")"
  -o "$(cygpath -w "$OUT")"
)

echo "第 $N 轮 ($MODE) | $MODEL / $EFFORT | 日志 $(w "$LOG")"
cd "$PROJECT"
set +e
if [ "$MODE" = review ]; then
  timeout "$TIMEOUT" "$CODEX" exec "${common[@]}" -s read-only -C "$(cygpath -w "$PROJECT")" - < "$PROMPT" > "$LOG" 2>&1
else
  timeout "$TIMEOUT" "$CODEX" exec resume "${common[@]}" "$(tr -d '[:space:]' < "$RDIR/session_id")" - < "$PROMPT" > "$LOG" 2>&1
fi
rc=$?
set -e

if [ "$MODE" = review ]; then
  sid=$(grep -m1 '^session id:' "$LOG" | awk '{print $3}' || true)
  [ -n "$sid" ] && echo "$sid" > "$RDIR/session_id"
fi

grep -m1 '^sandbox:' "$LOG" || true
ok=$(grep -cE '^ succeeded in ' "$LOG" || true)
bad=$(grep -cE '^ exited -?[0-9]+ in ' "$LOG" || true)
echo "Astra 执行的命令: $(grep -c '^exec$' "$LOG" || true) 条（成功 $ok，非零退出 $bad；rg 没搜到也算非零退出）"
echo "tokens used: $(grep -A1 '^tokens used' "$LOG" | tail -1 || true)"
if grep -qE 'setup refresh had errors|CreateFileMapping|PropertySetterNotSupported' "$LOG"; then
  echo "警告：日志里有沙箱/编码相关的报错，检查 Astra 是否真的读到了文件，必要时这一轮作废" >&2
fi
if [ "$ok" -eq 0 ]; then
  echo "警告：Astra 没有一条命令成功，它什么都没读到，这一轮结论不可信" >&2
fi

if [ $rc -ne 0 ]; then
  echo "codex 退出码 $rc（124 = 超时），日志末尾：" >&2
  tail -20 "$LOG" >&2
  exit 1
fi
if [ ! -s "$OUT" ]; then
  echo "没有生成 $(w "$OUT")，日志末尾：" >&2
  tail -20 "$LOG" >&2
  exit 1
fi

powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$SKILL_DIR/scripts/summarize.ps1")" -Path "$(cygpath -w "$OUT")"
