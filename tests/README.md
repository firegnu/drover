# 本次流转重构的验证入口

- `bash tests/drover.sh`：公开 schema 2 CLI 流转、旧记录、目标令牌、锁、假发送结果/失败、正文恢复与只读列表、通知观察。
- `bash tests/drover-board.sh`：现有看板的合成历史、正文滚动、布局/窄头栏、滚动条、帮助和待办详情。与 CLI 一致的动作目标另在 task-flow.py 验证。
- `sh tests/install.sh`：macOS 临时 HOME 与 sandbox-exec 中核对安装幂等、拒绝覆盖、通知模板；禁止真实 launchctl。

旧 criteria/check-result/manual-complete/return-to-pending/dispatch-pending/show-json 测试中的 v1 门槛与行为已退役，其保留责任集中到 task-flow.py、list-json.py、list-output.py、notifications.py。没有保留两套产品语义。drover.sh/drover-board.sh 是上述测试的可执行入口。

PTY/录屏工具仍仅供用户明确要求时单独运行。默认看板套件已去掉间接调用 PTY 的路径；本轮不做录屏或真实 agent/队列验证。
