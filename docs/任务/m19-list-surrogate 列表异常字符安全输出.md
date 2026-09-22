# T10：修复 drover list 遇到异常字符标题时崩溃

2026-09-22，drover/main 委派 drover/dev-list-surrogate（Codex，常规档 gpt-6-astra / high）。
路由：常规 / 交叉审查不要（路由：tier拿不准，常规概率0.75；cross_review不要，core_rules0.07；主控按小范围行为修复选常规档）
你是被委派的开发agent，照本任务做，不再委派。用户已正式发出TASK T10，本次是执行，不是只入队。

## 先读

AGENTS.md、HANDOFF.md、README.md；ROADMAP现行完成判据/命令边界；本文件；bin/drover的print_text/cmd_list和直接相关测试。
可参考 `docs/任务/m14-print-surrogate drover done 遇到孤立代理码不再崩.md` 与 tests/check-result.py 的严格输出测试方式，只复用现有经验，不扩大其旧任务范围。

## 工作区和文件范围

- worktree `/Users/firegnu/Developer/personal_projs/drover-worktrees/m19-list-surrogate`，分支 `m19-list-surrogate`，从main建立，无需依赖安装。
- 生产仅改 `bin/drover` 的 `cmd_list` 中承载标题/放弃原因等任务文字的输出，复用现有 `print_text`；静态标题无需机械替换。
- 测试只在直接相关现有文件或一个小型定向入口中补回归；需要时可最小接入现有测试入口。不得删除/削弱旧断言。
- 允许本任务文件追加完成记录。主仓库和其它worktree只读；不改HANDOFF/ROADMAP，均无设计变动，收尾由主控完成。

## 实现目标

孤立Unicode代理码不再让list抛UnicodeEncodeError或中断后续列表，只在打印时转义成可读的反斜杠形式。覆盖进行中、待办、已完成、已放弃标题及放弃原因的输出。正常中文、合法Unicode、列表格式保持不变；内存任务及原始文件不得被改写。不要重构print_text或顺带改变其它命令、判据、事件、推进、看板、期限或其它字符处理。

## 定向RED → GREEN

1. 用合成数据先复现目标失败，再做最小实现。明确固定严格UTF-8的stdout，不能因宿主宽松错误处理出现假绿；导入/fixture错误不算RED。
2. 用Python/JSON转义构造孤立代理码，不把实际代理码写入shell参数或普通UTF-8文件。待办场景可在隔离进程中构造内存队列数据抵达cmd_list，不能为测试改写生产解析规则。
3. 五类输出分别守住：正常退出、目标字符按现有print_text规则转义、后续正常条目仍可见；正常中文及合法Unicode（包括非ASCII空白）原样保留。原VM/合成状态文件前后相同，绝不碰真实队列。
4. 只跑新增/受影响定向回归及必要检查，不跑全仓库四套，也不为这几处输出重跑无关大套件。用旧生产副本或逐点恢复原输出方式做一次聚焦自证，确认回归能抓到漏用安全打印；不新建通用测试框架。
5. `git diff --check` 与代码范围核对；记录RED/GREEN关键错误和退出码、测试命令、变更范围。数据准备不执行真实done/go/next/loop，不执行付费或真实agent操作。

## 交付和禁止

只在本分支提交允许文件，不用git add -A。完成记录写在本文件末尾；只需短记录，不写长报告。主控轻量复核后本地合并收尾，不做独立交叉审查。

不合并、不推送、不打收尾记号、不清worktree/分支，不安装、不切换Python、不改PATH、不启动循环。不修改真实queue.md/tasks.state，不操作真实done/go/next/loop。不改corral/corral-dispatch，不读其源码/内部状态，不碰AGENTS列出的受保护项目和服务，不按项目名批量杀进程，不开关其它agent。T4暂缓；T8实验stash原样保留，不恢复/删除。

回复只写完成内容、RED/GREEN结果和提交号。命令都在前台跑完，全部做完后，回复最后一行写 DONE。
