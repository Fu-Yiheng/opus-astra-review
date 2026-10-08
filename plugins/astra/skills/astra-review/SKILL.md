---
name: astra-review
description: 把当前对话的工作成果（数据、文档、代码、Claude memory、对话中用户的原话）交给 Codex 里的 GPT-6-Astra 做独立的只读审核，然后逐条核实它的意见、据此改进，必要时请它复审，并记入审核记分表。当用户说「交给 Astra 审核」「让 Astra 看看」「Astra review」「找 Astra 挑毛病」，或问「Claude 和 Astra 谁该指挥谁」「Astra 审核记分表」，或要求「检查 Astra 审核环境」时使用。
---

# Astra 审核

本 skill 的目录是 `${CLAUDE_SKILL_DIR}`，下文的脚本和模板都在这里。

## 分工
- **Astra**（Codex 里的 `gpt-6-astra`）：独立审稿人。只读，只提意见，不改任何东西。
- **你**：写交接说明、核实 Astra 的每一条意见、决定采纳与否、动手改进、记分、向用户汇报。
- Astra 的意见**同样不是事实**。每条都要回到它给的证据位置亲自核对。

## 环境要点（Windows，已实测）
- 走 ChatGPT 订阅登录，不用 API key。第一次用、或者出错时，先跑环境检查：
  ```bash
  bash "${CLAUDE_SKILL_DIR}/scripts/astra.sh" doctor --live
  ```
- `codex.exe` 通常不在 PATH，所在的 `%LOCALAPPDATA%\OpenAI\Codex\bin\<哈希>\` 每次 Codex 更新都会变，脚本会自动查找。
- 脚本强制使用 `windows.sandbox="unelevated"`：elevated 沙箱从 Claude Code 里启动时，Astra 的每条命令都报 `setup refresh had errors`。
- `read-only` 已实测有效：Astra 能读文件，写文件被拒绝。但它**能读整个磁盘**，BRIEF 里的「禁止读取」只是提示词约束，不是强制隔离。
- 脚本带 `--ignore-user-config`：不加载用户 Codex 配置里的插件、MCP 和 memory。固定开销从约 7.8k 降到 2.2k tokens，审稿人也不受 Codex memory 影响。
- Astra 的命令跑在 PowerShell 5.1 的 **ConstrainedLanguage 模式**下：PowerShell 自己输出的中文全是乱码，设置 `[Console]::OutputEncoding` 也会报错。
  原生程序的输出不经转码，所以提示词要求它用 `findstr /n "^"` 读文件，用 Codex 自带的 `rg.exe` 搜索（路径由脚本自动填入）。
  Git 自带的 cat/sed/grep 在沙箱里**无法启动**（MSYS 运行时的 CreateFileMapping 被拒）。
- Astra 日志里并行命令的输出是交错排列的，某个 `exited 1` 不一定属于紧挨着它的那条命令，核对时以输出内容为准。
- 不要假设有 python 或 jq。JSON 用 PowerShell 处理，或者直接用 Read 读。
- 默认 `gpt-6-astra` + `xhigh`。**不要用 `ultra`**：它会自动派生子代理，额度消耗极大。
  额度紧张时，在命令前加 `ASTRA_EFFORT=high`，或者 `ASTRA_MODEL=gpt-6.1-sol`。
- 参考用量：`low` 强度审一个小项目约 2 万 tokens；`xhigh` 审真实项目可能几十万 tokens、10–30 分钟。

## 流程

### 0. 确定审核目录
`<项目根>/reviews/<YYYY-MM-DD_HHMM>_<短名>/`。项目根默认是当前工作目录。成果不在这里，或者当前目录不是一个项目（比如用户主目录），就问用户成果在哪。

### 1. 抽取用户原话
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_SKILL_DIR}/scripts/user_turns.ps1" -Transcript "<对话记录.jsonl>" -Out "<审核目录>/user_messages.md"
```
- 对话记录：`~/.claude/projects/<项目目录名>/<session_id>.jsonl`。session_id 就是系统提示里 scratchpad 路径中 `scratchpad` 上一级的文件夹名；找不到就取该目录下最近修改的 `.jsonl`。
- memory 目录：系统提示里 persistent memory 那个路径，和对话记录在同一个 `<项目目录名>` 下。
- 对话发生过 compaction 时，早期的原话已经不在你的上下文里了，这一步能从 jsonl 找回来。抽完读一遍 `user_messages.md`，确认用户的要求你没记错。

### 2. 写 BRIEF.md
把 `${CLAUDE_SKILL_DIR}/templates/BRIEF.md` 复制到审核目录再填写：
- **如实**，包括没把握的地方。Astra 会拿原始文件核对，粉饰只会让它多花额度去发现。
- 结论逐条写，每条附证据路径。材料清单写到具体文件，数据文件注明格式和规模。
- **禁止读取**：扫一遍材料，有 API key、`.env`、凭据、个人隐私或不得外传的数据，就列进去。
- memory：写出 memory 目录路径。为空就写「空」，不要省略这一行。

### 3. 告知用户，发起审核
先在聊天里列出：Astra 将读取的路径清单、禁止读取清单，以及「这些内容会发送给 OpenAI」。
用户已经说了「交给 Astra 审核」，不必再等确认；但清单里有明显敏感的内容（个人隐私、合作方未公开的数据）时先问。

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/astra.sh" review "<项目根>" "<审核目录>"
```
- 用 Bash 的 `run_in_background` 运行（经常超过 10 分钟），结束时你会收到通知，不要轮询。
- 告诉用户审核已经开始，大概需要多久。
- 等待期间**不要修改被审的材料**，否则 Astra 看到的内容和 BRIEF 对不上。

### 4. 核实与回应
脚本最后打印 verdict、各严重度的问题数，以及 Astra 执行了几条命令、成功几条。然后：
1. 读 `rN_review.json`。
2. 在 `rN_astra.log` 里看 Astra 实际执行了哪些命令，确认它真的打开了原始文件，而不是只看 BRIEF 就下结论。
   成功的命令为 0，或者脚本打印了沙箱/编码警告，说明它可能什么都没读，这一轮作废，排查后重跑。
3. 对每条 issue：打开它给的 location 和 evidence，亲自核对，然后判定：
   - **采纳 / 部分采纳**
   - **驳回**：必须拿出证据（文件+行号或命令输出），「我认为没问题」不算理由
   - **需用户决定**：涉及研究取舍、额外算力、改变目标的
4. 按 `${CLAUDE_SKILL_DIR}/templates/response.md` 写 `rN_response.md`。

最大的风险是偏向自己：BRIEF 是你写的，成果是你做的，判定也是你下的。所以 critical 和 major 默认倾向采纳，驳回要拿得出硬证据。

### 5. 改进
按采纳的条目修改：
- 原始数据和已有结果**不要覆盖**：新结果写进新文件或新版本，旧的保留。
- 每处改动都记进 response.md 的改动清单。
- memory 被指出过时或错误 → 更新或删除对应的 memory 文件，并同步 MEMORY.md。
- 改动很大（重跑实验、重写文档主体、需要大量算力）时，先和用户确认范围。
- 用户说「只审不改」时跳过这一步，只汇报。

### 6. 复审（视情况）
采纳了 critical 或 major 条目并改完之后，做一次复审：
```bash
bash "${CLAUDE_SKILL_DIR}/scripts/astra.sh" recheck "<项目根>" "<审核目录>"
```
它会接着第 1 轮的 Astra 会话（Astra 记得自己提过什么），读 response.md，核对修改。BRIEF 是第 1 轮前的快照，不需要随修改更新。
- 自动复审最多 1 次（即总共 2 次 Astra 调用）。还要继续，先问用户。
- 你驳回的条目 Astra 坚持并给出了新证据时，不要来回拉锯，把双方的证据摆给用户决定。

### 7. 记分
每次审核结束（复审完或决定不复审之后）记一行：
```bash
bash "${CLAUDE_SKILL_DIR}/scripts/ledger.sh" add date=YYYY-MM-DD project=<项目名> dir=<审核目录> model=gpt-6-astra/xhigh rounds=<Astra 调用次数> verdict=<最后一轮 verdict> issues=<各轮问题总数> real=<属实数> new_major=<Claude 没发现的严重问题数> disputes=<争议数> astra_won=<争议中 Astra 对的数> tokens=<各轮之和，去掉千分位逗号> note=<可选>
```
口径（如实记，这张表是用来评估你自己的）：
- `real`：采纳 + 部分采纳
- `new_major`：属实、critical 或 major、而且 BRIEF「已知弱点」里没提到的
- `disputes`：你驳回的条目，加上双方意见相左、交给用户裁决的条目
- `astra_won`：争议中最后证明 Astra 对的：你看到新证据后改判的，或者用户站在 Astra 一边的

争议当时没结论、用户后来才裁决的，用 `ledger.sh set <审核目录> astra_won=<新值>` 更新。
记分表在 `~/.claude/astra-review/ledger.tsv`，不在 skill 目录里，更新 skill 不会丢。

### 8. 向用户汇报
- 每一轮的 verdict
- 一张表：编号 | 严重度 | 问题 | 判定 | 改动
- **驳回的条目和理由**：这是用户最需要抽查的部分
- 需要用户决定的事项
- 审核目录路径，以及 tokens 用量

## 用户问「谁该指挥谁」时
运行 `bash "${CLAUDE_SKILL_DIR}/scripts/ledger.sh" show`，如实解读：
- 少于 5 次审核：样本太少，不下结论。
- Astra 意见属实率高、经常抓到你没发现的严重问题、争议中多数是 Astra 对：说明在用户的领域里 Astra 的判断更可靠，应该建议让 Astra 负责核心判断和规划，你负责执行和审稿。
- 反之则维持现状。你是利益相关方，解读时只讲数据，不替自己辩护。

## 审核目录结构
```
reviews/2026-10-07_2130_<短名>/
  user_messages.md   用户在对话中的原话（第 1 步）
  BRIEF.md           交接说明（你写）
  session_id         Astra 的会话 ID（复审用）
  r1_prompt.md       发给 Astra 的提示词（脚本生成）
  r1_review.json     Astra 的意见，格式见 schema/review.schema.json
  r1_astra.log       Astra 的完整执行记录
  r1_response.md     你的逐条回应和改动
  r2_...             复审
```

## 脚本参数
- `astra.sh review|recheck <项目根> <审核目录>`；`astra.sh doctor [--live]`
- 环境变量：`ASTRA_MODEL`（默认 `gpt-6-astra`）、`ASTRA_EFFORT`（默认 `xhigh`）、`ASTRA_TIMEOUT`（秒，默认 3600）、`ASTRA_CODEX`（手动指定 codex.exe）
- `ledger.sh add|set|show`；环境变量 `ASTRA_LEDGER` 可改记分表位置
