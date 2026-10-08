这是第 {{ROUND}} 轮复审。Claude 已经逐条回应了你第 {{PREV_ROUND}} 轮的意见，并做了修改。

## 材料
- 你第 {{PREV_ROUND}} 轮的审核：{{PREV_REVIEW}}
- Claude 的回应：{{RESPONSE}}
  每条标了「采纳 / 部分采纳 / 驳回 / 需用户决定」，附理由、证据和改动的文件。
- 交接说明：{{BRIEF}}
  这是第 1 轮之前写的快照，**不会随修改更新**，里面的旧结论不算本轮的问题。判断是否解决，以修改后的原始文件为准。
- 项目目录（当前工作目录）：{{PROJECT_DIR}}

## 任务
1. 对第 {{PREV_ROUND}} 轮的每个问题，**打开修改后的文件核对**，在 previous_issues 里给出判定：
   - resolved：确实解决了
   - partially_resolved：改了但不彻底，comment 里说清还差什么
   - unresolved：没解决
   - withdrawn：Claude 驳回且理由成立，你撤回这条
   对 Claude 驳回的条目，认真看它给的证据。理由成立就撤回；不成立就标 unresolved，并在 comment 里给出**新的**证据，不要只重复上一轮的话。
   标为「需用户决定」的条目，只评价双方论据，不必判定。
2. 检查这次修改有没有引入新问题。新问题放进 issues，编号接着上一轮往下排。
3. 规则与上一轮相同：只读、有证据才报、禁止读取的路径不打开。
   读文件用 `findstr /n "^" "<路径>"`，搜索用 `& '{{RG}}' -n '<模式>' '<路径>'`（匹配所有行写 `'^'`，不要写 `''`），
   不要把它们的输出再交给 PowerShell cmdlet；PowerShell 只用来做数值计算，PowerShell 自己输出的中文是乱码。
   Git 自带的 cat/sed/grep 在你的沙箱里无法启动，不要用。

## 输出
最后一条消息只输出符合给定 JSON schema 的 JSON，round 填 {{ROUND}}。
