#!/usr/bin/env bash
# 审核记分表：每次 Astra 审核结束记一行，积累起来判断 Claude 和 Astra 谁的判断更可靠。
#
#   ledger.sh add key=value ...            追加一条记录
#   ledger.sh set <审核目录> key=value ...  修改已有记录（例如争议后来由用户裁决）
#   ledger.sh show                         打印全部记录和汇总
#
# 字段（add 时除 note 外都必填）：
#   date       日期 YYYY-MM-DD
#   project    项目名
#   dir        审核目录（每条记录的唯一标识）
#   model      例如 gpt-6-astra/xhigh
#   rounds     Astra 调用次数（首审 + 复审）
#   verdict    最后一轮的 verdict
#   issues     Astra 各轮提出的问题总数
#   real       其中经核实属实的（采纳 + 部分采纳）
#   new_major  属实、critical/major、且 BRIEF「已知弱点」里没提到的：Astra 抓到而 Claude 自己没发现的严重问题
#   disputes   争议数：Claude 驳回的条目 + 双方意见相左、交给用户裁决的条目
#   astra_won  争议中最终 Astra 对的（Claude 看到新证据后改判，或用户站在 Astra 一边）
#   tokens     Astra 各轮 tokens 之和
#   note       备注（可选，不能含制表符）
#
# 记分表位置：$ASTRA_LEDGER，默认 ~/.claude/astra-review/ledger.tsv
# 放在 skill 目录之外，更新或重装 skill 不会动到它。
set -euo pipefail

LEDGER="${ASTRA_LEDGER:-$HOME/.claude/astra-review/ledger.tsv}"
KEYS=(date project dir model rounds verdict issues real new_major disputes astra_won tokens note)
NUMERIC=" rounds issues real new_major disputes astra_won tokens "

die() { echo "ledger.sh: $*" >&2; exit 2; }

col_of() {  # 字段名 -> 列号（从 1 开始）
  local i
  for i in "${!KEYS[@]}"; do [ "${KEYS[$i]}" = "$1" ] && { echo $((i + 1)); return; }; done
  die "未知字段: $1（可用：${KEYS[*]}）"
}

ensure_file() {
  mkdir -p "$(dirname "$LEDGER")"
  [ -f "$LEDGER" ] || (IFS=$'\t'; echo "${KEYS[*]}") > "$LEDGER"
}

check_value() {  # 字段 值
  case "$2" in *$'\t'*|*$'\n'*) die "$1 的值不能含制表符或换行" ;; esac
  if [[ "$NUMERIC" == *" $1 "* ]]; then
    [[ "$2" =~ ^[0-9]+$ ]] || die "$1 必须是非负整数，收到: $2"
  fi
}

check_row() {  # 一行各字段之间的约束
  local -n r=$1
  [ "${r[real]}" -le "${r[issues]}" ] || die "real(${r[real]}) 不能大于 issues(${r[issues]})"
  [ "${r[new_major]}" -le "${r[real]}" ] || die "new_major(${r[new_major]}) 不能大于 real(${r[real]})"
  [ "${r[astra_won]}" -le "${r[disputes]}" ] || die "astra_won(${r[astra_won]}) 不能大于 disputes(${r[disputes]})"
}

cmd_add() {
  declare -A row=()
  local kv k v
  for kv in "$@"; do
    [[ "$kv" == *=* ]] || die "参数要写成 key=value：$kv"
    k=${kv%%=*}; v=${kv#*=}
    col_of "$k" >/dev/null
    check_value "$k" "$v"
    row[$k]=$v
  done
  for k in "${KEYS[@]}"; do
    [ "$k" = note ] && continue
    [ -n "${row[$k]:-}" ] || die "缺少字段: $k"
  done
  check_row row
  ensure_file
  if awk -F'\t' -v d="${row[dir]}" 'NR > 1 && $3 == d { found = 1 } END { exit !found }' "$LEDGER"; then
    die "这个审核目录已有记录，修改请用 set"
  fi
  local out=()
  for k in "${KEYS[@]}"; do out+=("${row[$k]:-}"); done
  (IFS=$'\t'; echo "${out[*]}") >> "$LEDGER"
  echo "已记录 -> $LEDGER"
}

cmd_set() {
  [ $# -ge 2 ] || die "用法: ledger.sh set <审核目录> key=value ..."
  [ -f "$LEDGER" ] || die "记分表还不存在: $LEDGER"
  local dir=$1; shift
  local assigns=() kv k v
  for kv in "$@"; do
    [[ "$kv" == *=* ]] || die "参数要写成 key=value：$kv"
    k=${kv%%=*}; v=${kv#*=}
    [ "$k" = dir ] && die "不能修改 dir"
    check_value "$k" "$v"
    assigns+=("$(col_of "$k")=$v")
  done
  local tmp="$LEDGER.tmp"
  awk -F'\t' -v OFS='\t' -v d="$dir" -v spec="$(printf '%s\n' "${assigns[@]}")" '
    BEGIN { n = split(spec, a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") { p = index(a[i], "="); c[substr(a[i], 1, p - 1)] = substr(a[i], p + 1) } }
    NR > 1 && $3 == d { for (j in c) $j = c[j]; hit = 1 }
    { print }
    END { if (!hit) exit 3 }
  ' "$LEDGER" > "$tmp" || { rm -f "$tmp"; die "没找到审核目录为 $dir 的记录"; }
  # 修改后重新检查这一行的约束
  declare -A row=()
  local line i
  line=$(awk -F'\t' -v d="$dir" 'NR > 1 && $3 == d' "$tmp")
  IFS=$'\t' read -r -a vals <<< "$line"
  for i in "${!KEYS[@]}"; do row[${KEYS[$i]}]=${vals[$i]:-}; done
  ( check_row row ) || { rm -f "$tmp"; exit 2; }
  mv "$tmp" "$LEDGER"
  echo "已更新 -> $LEDGER"
}

cmd_show() {
  [ -f "$LEDGER" ] && [ "$(wc -l < "$LEDGER")" -gt 1 ] || { echo "还没有记录（$LEDGER）"; return; }
  awk -F'\t' '
    NR == 1 { next }
    {
      n++
      printf "%s  %s  [%s, %s 轮]  %s\n", $1, $2, $4, $5, $6
      printf "    问题 %d，属实 %d，Claude 没发现的严重问题 %d | 争议 %d，Astra 对 %d | %s tokens%s\n",
             $7, $8, $9, $10, $11, $12, ($13 != "" ? " | " $13 : "")
      printf "    %s\n", $3
      I += $7; R += $8; M += $9; D += $10; W += $11; T += $12
    }
    END {
      print "----"
      printf "审核 %d 次，Astra tokens 合计 %d\n", n, T
      printf "Astra 意见属实率: %s\n", (I ? sprintf("%.0f%% (%d/%d)", 100 * R / I, R, I) : "无数据")
      printf "平均每次审核抓到 Claude 没发现的严重问题: %.1f 个 (共 %d)\n", M / n, M
      printf "争议中 Astra 对的比例: %s\n", (D ? sprintf("%.0f%% (%d/%d)", 100 * W / D, W, D) : "暂无争议")
      if (n < 5) print "（少于 5 次审核，样本太少，先别下结论）"
    }
  ' "$LEDGER"
}

case "${1:-}" in
  add)  shift; cmd_add "$@" ;;
  set)  shift; cmd_set "$@" ;;
  show) cmd_show ;;
  *)    die "用法: ledger.sh add|set|show（见脚本开头的说明）" ;;
esac
