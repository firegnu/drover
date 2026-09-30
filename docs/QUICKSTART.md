# QUICKSTART

Drover 记录任务流转和通知；主控审查交付质量，用户验收。Git、测试、分支不再统一阻挡状态。完整字段、退出码和切换步骤见[任务流转接口 v2](任务流转JSON接口.md)。

## 安装与接入

需要 Python 3 标准库、Git；要发送给主控时需要 Corral。Drover 不开、不关、不接入 agent。

获授权后在长期保留的 Drover checkout 执行 `sh install.sh`。它只创建命令软链并生成通知观察模板，不运行 launchctl、不改 PATH；已有不同 plist 会拒绝覆盖。**从旧版升级必须先退出旧 KeepAlive 推进引擎，再与 Saddle 联合切换，不能单独安装本任务分支。**

在目标项目内执行：

```sh
drover init <短名>
```

编辑 `.drover.conf` 中的 `MAIN_AGENT=<项目>/main`；留空表示明确派发时只返回正文供人粘贴。HANDOFF_DIR 指向保存 queue.md 和 tasks.state 的目录。TASK_FILE_DIR 可选，仅供看板显示任务文件/路由。

不再要求为了 Drover 添加收尾记号、验收命令或分支基线；项目自己已有的开发、审查、合并与清理规矩照常执行。

## 明确派发、提交、接受

```sh
drover add '标题' '任务正文'
drover list --json
```

也可直接编辑交接目录中的 `queue.md`：`## T1 标题` 或 `## 标题` 开始一件待办。正文只作为任务内容，绝不执行其中的命令。

从所选 Pending 的 `actions["dispatch-pending"]` 取 pos 和 target_token：

```sh
drover dispatch-pending --pos N --target-token TOKEN --json
```

运行中主控完成交付并审查后，重新读取当前目标：

```sh
drover show T1 --json
drover done T1 --target-token TOKEN --json
```

done 仅提交到 Awaiting release，不运行测试，也不接受交付。用户验收并接受后，从新响应的 `task.actions.go` 取令牌：

```sh
drover go T1 --target-token TOKEN --json
```

go 只结束 T1，不派发下一项。下一项重新读取 list，再明确 dispatch-pending。令牌过期后重新读取、由用户重新确认，不能自动换令牌重试；发送未确认或写入失败也不能盲目重发。

## 退回与暂停

Running 或 Awaiting 都能退回。确认工作已停，读取该任务的 return-to-pending 动作令牌：

```sh
drover return-to-pending T1 --target-token TOKEN --reason '需要修改' --work-stopped --json
```

恢复原派发正文到 Pending，保留交付记录、分支与 worktree，不隐式暂停、不自动重开。`drover pause` 阻止明确派发；`drover resume` 解除暂停但不会派发。原有暂停保持。

旧 next、loop、hold、complete-manually 已退役；无参 go 和不带令牌的 done 不再执行旧行为。

## 看板与通知

`drover board` 打开现有 curses 看板：`d` 提交、`g` 接受、`n` 明确派发第一件 Pending，`p` 暂停/恢复，`a` 编辑队列，`u` 看待办，`?` 看帮助。按键使用屏幕上那次观察的目标；过期后显示失败，不自动刷新令牌再执行。退回用上述 CLI 或接入后的 Saddle。

```sh
drover notifications status --json
drover notifications on --json
drover notifications off --json
drover notifications watch
```

watch 默认 60 秒观察一次新 Awaiting；启动和偏好变化先建立基线，不补弹历史、不推进任务。launchd 模板现在也仅运行此观察器；启用后不要再同时运行第二份。是否启用、何时切换真实服务须由用户决定。
