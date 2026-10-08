# astra-review：让 GPT-6-Astra 审核 Claude 的工作

在 Claude Code 里说一句「交给 Astra 审核」，Claude 会把当前对话的工作成果（数据、文档、代码、Claude 的 memory、你在对话里的原话）交给 Codex 里的 GPT-6-Astra 做**独立、只读**的审核。之后 Claude 逐条核实 Astra 的意见，采纳的就动手改，必要时再请 Astra 复审一次，最后把结果记进一张记分表。

全程走你自己的 Claude 订阅和 ChatGPT 订阅，**不需要任何 API key**。

## 需要什么

- **Windows 10 / 11**（目前只支持 Windows）
- **Claude Code**（桌面版的 Code 标签页或命令行都可以），以及 **Git for Windows**（装 Claude Code 时一般已经装了）
- **Codex 桌面应用**，并且已经用 ChatGPT 账号登录
- 你的 ChatGPT 套餐能用 **GPT-6-Astra**。不能用的话也可以换成别的模型，见下文「常见问题」

## 安装

三种方式任选一种。

### 方式一：从 GitHub 安装（之后能收到更新）

这个仓库是**私有**的，只有被邀请的人能装：

1. **接受邀请**：把你的 GitHub 用户名告诉作者。作者邀请你之后，你会收到邮件或 GitHub 通知，点 **Accept invitation**。
2. **让电脑记住你的 GitHub 登录**（只需做一次）：打开 Git Bash，运行
   ```bash
   git clone https://github.com/Fu-Yiheng/astra-review "$TEMP/astra-review-test"
   ```
   会弹出 GitHub 登录窗口，选 **Sign in with your browser** 并授权。克隆成功就说明可以了，这个临时文件夹之后可以删掉。
   这一步是必须的：Claude Code 安装插件时不会弹登录窗口，只会用电脑里已经保存的登录信息。
3. 在 Claude Code 的对话框里依次输入：
   ```
   /plugin marketplace add Fu-Yiheng/astra-review
   /plugin install astra@astra-review
   ```
   第一条报错的话，改用完整地址：`/plugin marketplace add https://github.com/Fu-Yiheng/astra-review.git`

装完重启 Claude Code，或者输入 `/reload-plugins`。

以后更新：输入 `/plugin marketplace update astra-review`，然后在 `/plugin` 的 Installed 页里点更新。
也可以在 `/plugin` → Marketplaces → astra-review 里打开 auto-update。

### 方式二：从本地文件夹安装（不需要 GitHub 账号）

向作者要 `astra-review.zip`，解压后把整个 `astra-review` 文件夹放到一个**不会删掉**的位置（例如 `D:\tools\astra-review`），然后在 Claude Code 里输入：

```
/plugin marketplace add D:/tools/astra-review
/plugin install astra@astra-review
```

以后拿到新版：用新文件夹覆盖旧的，再输入 `/plugin marketplace update astra-review`。

### 方式三：直接复制 skill（最简单，但不能自动更新）

把 `plugins/astra/skills/astra-review` 这个文件夹整个复制到 `C:\Users\<你的用户名>\.claude\skills\` 下，然后重启 Claude Code。

## 第一次用：检查环境

装好后，在 Claude Code 里说：

> 检查 Astra 审核环境

Claude 会运行自检，确认这几项：Git Bash 是否可用、codex 能否找到、Codex 是否已登录、Astra 模型能否调用。它还会真的调用一次模型，大约花 2k tokens。有 `[X]` 的项照提示处理。

## 怎么用

在**做这项工作的那个对话里**说：

| 你想要 | 这样说 |
|---|---|
| 全面审核 | 「交给 Astra 审核」 |
| 指定重点 | 「交给 Astra 审核，重点看统计方法对不对」 |
| 限定范围 | 「让 Astra 只审 `results/` 和报告，不用看代码」 |
| 排除敏感内容 | 「交给 Astra 审核，`data/raw/` 不要给它看」 |
| 只审不改 | 「让 Astra 挑挑毛病，先别改，我看完再说」 |
| 省额度 | 「用 high 审」或者「用 Sol 审」（默认是 Astra + xhigh） |
| 再审一轮 | 「再让 Astra 复审一次」 |
| 看记分表 | 「看看 Astra 审核记分表」 |

如果是从插件装的（方式一、二），也可以直接输入 `/astra:astra-review`。

**说完之后：**

1. Claude 先列出要发给 Astra 的文件清单，然后在后台启动审核，通常要 10–30 分钟。等待期间可以聊别的，但**不要改被审的文件**。
2. 审完 Claude 会汇报 Astra 提了什么问题，以及每条问题核实后的结论：采纳、驳回，还是需要你决定。
3. 采纳的意见 Claude 会动手改。改动大的（重跑实验、重写文档主体）会先问你。
4. 有严重问题被改掉的话，Claude 会请 Astra 再核对一次。

**你需要做的：**

- **抽查 Claude 驳回的条目**。Claude 最可能在这里偏袒自己，汇报里会单独列出来。
- 拍板「需要你决定」的事项。

所有记录都在项目里的 `reviews/<时间>_<名称>/` 文件夹：Astra 的意见在 `r1_review.json`，它执行过的每条命令在 `r1_astra.log`，Claude 的逐条回应在 `r1_response.md`。

## 记分表：Claude 和 Astra 谁更靠谱

每次审核结束，Claude 会在 `C:\Users\<你>\.claude\astra-review\ledger.tsv` 记一行，统计这几个数：
- Astra 提的意见有多少属实
- 每次审核里，Astra 抓到了几个 Claude 自己没发现的严重问题
- 双方有争议的条目里，最后谁是对的

攒够 5 次以上再看。如果 Astra 经常抓到 Claude 漏掉的问题、争议中多数是它对，说明在你的领域里 Astra 的判断更可靠，可以考虑让它来主导。

## 隐私和成本

- **Astra 读到的所有内容都会发送给 OpenAI**，Claude 每次发送前会列出清单。
- Astra 运行在只读沙箱里，**改不了你的任何文件**，但**能读整个磁盘**。交接说明里的「禁止读取」只是对 Astra 的要求，不是强制隔离，真正不能外传的数据别放在会被审核的项目里。
- 用量参考：`low` 强度审一个小项目约 2 万 tokens。默认的 `xhigh` 审一个真实项目，可能要几十万 tokens、10–30 分钟，从你的 ChatGPT 套餐额度里扣。

## 常见问题

- **自检说找不到 codex**：先装 Codex 桌面应用并登录。Codex 每次更新后程序路径都会变，脚本会自动去找，不用管。
- **自检说模型列表里没有 gpt-6-astra**：你的套餐可能不支持 Astra。对 Claude 说「用 Sol 审」，会换成 `gpt-6.1-sol`。
- **Astra 好像什么都没读到**：Claude 会检查 Astra 的执行记录，发现这种情况会把这一轮作废并重跑。如果反复出现，把 `r1_astra.log` 发给维护者。
- **Mac / Linux**：暂不支持。脚本依赖 Windows 上的 Git Bash 和 PowerShell。
