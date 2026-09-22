# 任务：T14 安装环境 PATH 调研与修复

2026-09-22，drover/main 交给新开的 drover/dev-install-path（Codex，重档 gpt-6-astra / xhigh；实际名字以 corral start 返回为准）。
路由：重 / 交叉审查要（路由：重 0.99、安全隐私 0.84；当前先调研，实施后安排独立审查）
你是被委派的 agent：照本文件做，不要再开别的 agent。

## 先读

1. HANDOFF.md、AGENTS.md、README.md。
2. docs/ROADMAP.md 安装脚本与 launchd 段，docs/QUICKSTART.md、docs/手册.md 的安装/循环说明。
3. install.sh、launchd/dev.drover.loop.plist、tests/install.sh、docs/任务/m5-install 安装脚本和 launchd.md。
4. 本文件。corral 如需参考只读其 docs/CONTRACT.md，不读源码或状态目录。

## 位置与范围

- worktree：/Users/firegnu/Developer/personal_projs/drover-worktrees/m23-install-path，分支 m23-install-path，从 main 建立。
- 只用 Python 标准库，无需安装依赖。主仓库 HANDOFF 由主控维护，不改。
- T14 已正式收到派发，队列末尾“仅加入待办”是之前排期文字，已被本次派发取代。原 T4 的放弃记录保留。
- 本轮只做第一阶段调研，在本文件追加报告并提交；不改生产代码、测试或 ROADMAP。探针与输出放临时目录，给出可复核命令与证据路径。后续实施仍在同一任务、同一 worktree，等主控发送明确范围。

## 第一阶段：先查清再定方案

现状：install.sh 将安装时 PATH（前置 ~/.local/bin、去重）写进 plist。换 PATH 重装会因内容不同拒绝覆盖；激活虚拟环境时可能让后台依赖临时 Python。不要直接把白名单当成既定方案。

1. 列出现有行为矩阵：干净系统/Homebrew 环境、激活 venv、conda/pyenv 等路径或 shim（可用合成目录模拟，不安装它们）、自定义位置的 corral、PATH 顺序/无关目录变化、空/相对 PATH 分量、旧 plist 已存在。明确实际坏在哪里、何时只是安全拒绝，避免“总能找到 corral”这类无依据绝对结论。
2. 至少复现换无关 PATH 后重装拒绝、临时解释器优先级被写进 plist，以及简单白名单漏掉自定义 corral 路径这三类。使用临时 HOME、合成命令，不调用真实 corral/agent、不启动引擎。可以执行沙箱内安装以观察生成物；“只写不跑”禁止真实安装，不禁止隔离验证。
3. 核对实际命令解析链：脚本 shebang、引擎对子命令的启动、corral 的外部运行时依赖。只看本仓库代码；不要读 corral 源码、真实 corral 可执行文件内容或内部状态。外部工具不可知的依赖明确标成边界。
4. 提出最小推荐方案，最多再给一个有意义的备选；说明 Python/git/corral 怎么找、如何避免临时环境、重复安装如何保持幂等、旧配置如何处理、未知目标拒绝覆盖如何保留。不要扩成通用运行时管理器，不新增不必要配置。
5. 对照现有 ROADMAP 与安装契约逐条标注：哪些只是实现修复，哪些改变已定设计、需用户决定。先完成可审阅的具体方案，不提前要求用户泛泛批准。
6. 给出后续 tests/install.sh 的最小用例与有效 RED→GREEN 计划；既有未知目标/预检/隔离/不启动服务断言保留。现有“原样保存 PATH”断言若需变更，精确解释。

## 安全边界

- 临时 HOME 和合成环境沿用 tests/install.sh 的 sandbox-exec 写入隔离，拒绝执行 /bin/launchctl；不得运行真实 install.sh 安装到用户 HOME。沙箱不可用就报告，不换成真实环境验证。
- 不运行任何 launchctl 操作，不修改真实 PATH/shell rc、~/.local/bin、LaunchAgents、~/.drover 或真实队列/tasks.state；不操作真实 done/go/next/loop、不改 TASK_GATE。保留手动 n → g → n。
- 不修改 corral 或 corral-dispatch，不读其源码/状态目录，不访问受保护真实项目与服务（AGENTS.md 表格）。不运行真实 corral 作为探针、不发消息、不新建或关闭 agent。
- 不恢复/删除 T8 stash，不按项目名批量杀进程；只处理自己记录 PID 的临时进程。
- 不安装第三方包、不改其它文件、不合并 main、不推送、不清 worktree/分支、不打收尾记号。

## 记录与回复

报告包含环境/行为矩阵、实际复现命令和结果、最小方案、兼容影响、需裁定点与后续定向测试计划。事实与推断分开；未执行的场景不能写成已验证。不跑全仓库套件；可以跑现有隔离安装套件了解基线。

在本文件末尾追加“## 第一阶段完成记录”，只在自己分支提交这份文档。命令都在前台跑完，回复写主要发现、推荐方案、提交号和待决定事项，最后一行写 DONE。DONE 仅表示调研阶段结束，不表示 T14 已完成。

## 第一阶段完成记录

2026-09-22，`m23-install-path`，调查基线 `2d4b2f2`。**调研完成，尚未修复，也未授权第二阶段。** 本轮只追加本报告；生产代码、测试、ROADMAP、HANDOFF 均未修改。

结论：当前实现的 PATH 去重只解决“重复分量 / 补入安装目录”，不能解决无关目录增减、顺序变化引发的重装拒绝；临时解释器优先级会被保存。拒绝不一致的旧 plist 是已有的安全保护，不能用“看起来像自己生成的”放宽。单纯固定白名单、或者仅记录 corral 的绝对路径，都不足以保留自定义工具及其外部运行时。

推荐一个待裁定方案：**后台服务使用确定的默认 PATH，另提供一个安装时显式指定完整服务 PATH 的入口；继续逐字节保护已有 plist。** 不从安装 shell 自动搜集未知运行时，不新增持久化安装状态或改造 drover 引擎。下面明确其兼容代价和实施边界。

### 1. 环境、证据与验证范围

- macOS 27.0 / arm64；探针由 `/usr/bin/python3` 启动，本机实际 `sys.executable` 为 `/Applications/Xcode.app/Contents/Developer/usr/bin/python3`，版本 3.9.6。此事实只代表本机，不推出所有 macOS 都自带可用 Python。
- 证据根目录：`/private/tmp/drover-m23-ua0xpt1r/`。`environment.json` 记录基线；`repro.py` 是缺陷检查；`matrix.py` 是现状观察探针；`baseline.log`、`red.log`、`red-repeat.log`、`matrix.log` 保存输出。对应 `*-command.json` 记录命令及退出码。
- 最终矩阵：`/private/tmp/drover-m23-ua0xpt1r/matrix-yviatut0/results.json`，55 次观察子命令，探针断言全部通过；**不是 55 项产品回归通过**。每个场景目录另有 `sandbox.sb`、逐次调用 JSON 和实际生成的 plist。根目录 `evidence-manifest.json` 记录相关生产输入、探针及最终输出的 SHA-256；中途探针目录保留，不冒充最终结果。
- 所有安装均经 `sandbox-exec`：默认拒绝写入，只开放各自临时目录，拒绝执行 `/bin/launchctl`。`sandbox_guard/deny_write.json` 证实写另一个临时位置时报 `PermissionError`、目标未创建；没有对真实 HOME 做写入试探。
- venv、conda、Homebrew 布局和 pyenv shim 均为临时目录及合成脚本，不安装或运行这些环境管理器。Python 包装脚本标记被选中的入口，再转给上述现有 Python；**不声称测过真实 conda/pyenv 的完整激活行为**。
- 只运行合成 corral。真实 corral 的源码、可执行文件内容、内部状态均未读，命令也未运行。外部资料仅核对获准的 `corral/docs/CONTRACT.md`。未启动引擎、服务或 agent，未读取真实项目队列。
- `sh tests/install.sh` 在受控父环境下运行：9 项通过。未跑全仓库套件。两个缺陷检查两次运行均退出 1，失败点分别为“无关 PATH 重装应成功”和“临时 Python 目录不应写入 plist”，不是语法或 fixture 错误。
- 部分 `/usr/bin/python3` 调用输出 Xcode 缓存写入被沙箱拒绝的提示，但相同环境的首次安装成功；目标 RED 依据是 plist 冲突和已保存的临时目录。另一次扩展观察探针曾错误地把空 PATH 的 shell 退出码假定为 127；本机实际为 1，已改成检查非零、缺少 python3 的错误和零写入，**该次探针错误不计入 RED**。

复核入口（只写新建的临时子目录，不清理旧证据）：

```sh
cd /Users/firegnu/Developer/personal_projs/drover-worktrees/m23-install-path
/usr/bin/python3 -B /private/tmp/drover-m23-ua0xpt1r/repro.py -v
# 当前版本预期退出 1：2 个目标缺陷 FAIL。
/usr/bin/python3 -B /private/tmp/drover-m23-ua0xpt1r/matrix.py
# 当前版本预期退出 0：PASS observations: 55，并打印新证据目录。
```

探针内真正的安装调用为 `subprocess.run(["/usr/bin/sandbox-exec", "-p", profile, "/bin/sh", ROOT / "install.sh"], cwd=临时目录, env=仅含临时 HOME/受控 PATH 等, ...)`；具体参数、输入环境、stdout/stderr、退出码均在逐次 JSON 中。所有子进程使用同步等待和超时，未后台遗留进程。

### 2. 已验证的行为矩阵

下表证据路径均相对最终矩阵目录。标为“合成”的只证明 PATH/进程解析机制；对真实管理器的适用性属于推断。

| 场景 | 当前实际结果 | 结论 / 证据子目录 |
|---|---|---|
| 干净系统 PATH `/usr/bin:/bin:/usr/sbin:/sbin` | 安装退出 0；解析到系统 python3/git，corral 为 null | 安装成功没有验证 corral 就绪。`clean_system` |
| Homebrew 式绝对目录，含合成 python3/git/corral | 安装成功；三者均解析到合成目录，Python 入口标记为 brew | 能保留这类布局；未验证真实 Homebrew 包。`homebrew_shape` |
| 同一 PATH 重装、增加已经被前置的 `~/.local/bin`、增加重复分量 | 退出 0，HOME 快照内容、模式及 mtime 不变 | 现有去重有效，不能把所有重装都说成坏。`unrelated_and_order` 的 same/add_local/duplicates |
| 末尾添加无关空目录；交换两个无关空目录；交换系统目录顺序 | 首装 0、重装 1，明确“内容或安装时的 PATH 已变”，快照不变 | 重装可用性问题，但失败方向是安全拒绝，没有覆盖或半安装。extra/irrelevant_reorder/reorder |
| 合成激活 venv，PATH 首项为 `.venv/bin` | 安装成功；plist 保留该目录，服务环境下的合成 Python 探针仍选它 | `VIRTUAL_ENV` 本身未保存，仍会因 PATH 选中它。`venv` |
| 合成 conda 环境 `conda/envs/test/bin` | 同上；`CONDA_PREFIX` 未保存 | 环境目录被保留不等于激活过程被完整重现。`conda` |
| 上述 venv/conda Python 入口移走，后面仍有系统 Python | 合成服务探针仍退出 0，但改选 `/usr/bin/python3` | 是静默换解释器，不是必然起不来。只移动自己创建的探针文件。各自 after_removal |
| PATH 只有合成 venv，入口移走后无备用 Python | 安装原本成功；随后 `/usr/bin/env python3` 退出 127 | 只有无可用后备时才在查找环节失败。`venv_only_no_fallback` |
| 合成 pyenv shim 依赖 `PYENV_VERSION` | 安装时成功；plist 只有 HOME/PATH，服务探针退出 79，`MISSING_PYENV_VERSION` | 说明“保存 shim 路径”不保证环境完整；不是断言所有真实 pyenv shim 都依赖此变量。`pyenv_shim` |
| corral 在自定义目录，其 env 运行时在另一个自定义目录 | 完整 PATH 下合成 corral 退出 0；简单白名单中 corral 为 null | 必需复现三成立。`custom_corral_runtime` 的 full_path/whitelist_resolution |
| 固定上述 corral 的绝对路径，或把其软链放入临时 `~/.local/bin`，再用白名单 | corral 入口可定位，但退出 127：`env: m23-runtime: No such file or directory` | 入口路径 / 软链目标父目录并不代表全部运行时依赖。absolute_corral_missing_runtime/local_symlink_missing_runtime |
| 合成验收工具只在自定义目录 | 继承完整 PATH 的 `/bin/sh -c m23-check` 成功，白名单下退出 127 | PATH 还影响 CHECK_CMD；只保 python/git/corral 不足以保证验收命令兼容。check_full_path/check_whitelist |
| PATH 含空分量、`.`、`relative/bin` | 安装成功，去重后仍原样写入；相同服务 PATH 换 cwd，分别命中两个不同的合成 Python，再换无该目录的 cwd 则回落系统 Python | 相对搜索随项目目录变化；不应为后台服务悄悄保留。`empty_relative` |
| 整条 PATH 为空；只有不存在的绝对目录 | 安装启动 Python 失败，分别退出 1 / 127，临时 HOME 快照不变 | 失败在安装器启动层，还没到生成 plist。`empty_path` / `no_python` |
| 临时 `~/.local/bin/python3` 与 shell PATH 首选 Python 不同 | 安装器用 shell-first，生成的服务 PATH 因前置 local/bin 而选 local-first | 安装器解释器也不一定等于服务解释器。`local_bin_precedence` |
| 旧 plist 一致 / PATH 不同 / 字段被改 / 是软链或未知文件 | 一致时复用；其它均退出 1 且快照不变 | 当前保护应保留。`old_plist_*`；目录、断链及两个命令的冲突由原 9 项套件覆盖 |

### 3. 实际命令解析链与外部边界

以下是本仓库代码事实，未执行真实 loop/done/next：

1. **安装器**：`install.sh:1–4` 是 `/bin/sh` → 按调用者 PATH 找 `python3`。`19–27` 生成 plist，只保存 HOME、前置安装目录并去重后的 PATH。`34–37` 要求旧 plist 为非软链普通文件且字节完全相等；`39` 之后才开始写入。
2. **后台入口**：plist 的 ProgramArguments 是绝对 `~/.local/bin/drover` 加 `loop`；两条命令仍是仓库脚本的绝对软链。`bin/drover:1` 为 `#!/usr/bin/env python3`，所以后台 Python 来自服务 PATH，**不是安装器的 sys.executable**。本轮仅用合成脚本验证同种 shebang 解析，没有启用 launchd。
3. **引擎子命令**：`bin/drover-board:1391,1437` 直接执行 `[task_bin_path(), "done"/"next", ...]`，设置 `cwd=repo`，再次经过 shebang 和继承的 PATH。单独把 plist 改成某个绝对 Python 并不能固定这些子进程；相对 PATH 在这里尤其不稳定。若保持全为绝对分量的服务 PATH，则无需为这次修复改动这些函数。
4. **看板路径不同**：`bin/drover:726` 打开看板、`bin/drover-board:1230` 执行看板操作用的是 `sys.executable`，已经保留调用者解释器。T8 已定的 `/opt/anaconda3/bin/python3 ./bin/drover board` 不应借 T14 改写或自动切换。
5. **git、corral 和其它程序**：git 通过 `subprocess` 按 PATH 找（`bin/drover:85,102`，`bin/drover-board:59–61` 等）。corral 来自 `DROVER_CORRAL_BIN` 或默认名称 `corral`（`:71–80`）；当前安装器不会把 shell 的 `DROVER_CORRAL_BIN` 烤进 plist。绝对 override 也不能消除 corral 自身 shebang / 包装器的依赖。`run_check`（`:437–441`）的 shell 和通知的 `osascript`（`bin/drover:486,513`）也继承 PATH。
6. **corral 契约的已知与未知**：契约只承诺 CLI/JSON/退出码；第 47 行的 `/usr/bin/python3` 指 Claude Code/Codex 的启动钩子，不能据此推断 corral CLI 本身的完整运行时。契约没有给出 `send/status/ls` 所需的解释器、包装器、辅助程序清单。其 `start` 的登录 shell 规则也不代表 drover 调用 CLI 会加载登录 shell。**真实 corral 的外部依赖未验证，明确留作使用者提供服务环境的边界；不猜 Python/Node/Bun，也不读入口来猜。**

因此应修正文档的两个绝对说法：“整条 PATH 一定找得到 corral/git”不成立；“venv 删了就起不来”只在没有后备或后备不能运行时成立。PATH 配置固定也不保证目录中的程序永远存在、不被升级或更换。

### 4. 最小推荐方案（待裁定，未实现）

#### 4.1 服务 PATH 的明确来源

仅为安装器增加一个输入，建议名 `DROVER_LAUNCHD_PATH`，不加配置文件、项目配置、命令包装器或安装状态文件。

- **未设置时**，服务 PATH 固定为下面的顺序；只把 HOME 展开为绝对路径，不拼接安装 shell PATH，也不按某目录今天存不存在改变列表：

  ```text
  <HOME>/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
  ```

- **显式设置时**，它代表完整的服务 PATH，严格保持用户顺序并按字符串去重，**不隐式追加其它目录，也不再次前置 local/bin**。这能明确选择自定义 Python/corral/git 和其外部依赖，避免安装器重新覆盖人的优先级。用户需要 local/bin 或系统工具时必须在完整值中列出。
- 显式空字符串、空分量、`.`、其它相对分量一律在任何安装写入前拒绝；不展开用户输入的 `~` / `$VAR`、不按 cwd 转绝对路径、不解析软链后猜依赖，也不排序。目录含空格与 XML 特殊字符仍由环境传参和 plistlib 处理。
- 安装器的短生命周期仍由现有 `exec python3` 启动；它可以来自当前可用 venv，但**不把该解释器路径或当前 PATH 自动变成后台配置**。若安装器本身没有 Python，仍报启动失败，不自装依赖。
- 此默认值只覆盖常见固定目录，不宣称自动发现所有工具。默认不捕获当前 shell 的 venv、conda env、pyenv shim、NVM 等路径；需要自定义工具时显式给出长期保留的目录。长期保留的 Anaconda 路径不是一概禁用，也不能仅凭目录名判断“临时”。

**保障边界**：这个方案避免“临时 shell 环境被无意保存”，不承诺识别所有临时解释器。用户若主动在默认目录放了指向 venv 的软链，或者显式输入了临时目录，仍可能依赖它。安装器不运行环境管理器、不自动切到所谓 base 环境、不抓取当前 shell 的其它变量来补齐包装器。启用服务前需人工核对显示出的实际入口及持久性；需要额外变量的外部包装器必须自行具备独立运行条件，本任务不增加通用环境管理功能。

#### 4.2 Python / git / corral 如何找

- 以最终服务 PATH 显式调用 `shutil.which(name, path=service_path)`，取得 python3/git/corral 的可执行入口；打印这三个入口和服务 PATH。不从当前 PATH 找到 corral 后偷偷把某个父目录补进去。
- **建议收紧前置条件**：三者任一查不到，非零拒绝，全部目标保持不变。只做路径及可执行性检查，不执行真实 corral，也不声称完成其运行时验证。默认找不到自定义 corral 时，错误应指明缺失项及 `DROVER_LAUNCHD_PATH` 的完整覆盖用法，不回退捕获当前 shell PATH。该条改变现有“缺 corral 也生成文件”的行为，单列待裁定。
- 不把三个解析结果固定为新的持久化字段；plist 继续是 `[绝对 drover 路径, "loop"]`。全部绝对目录的服务 PATH 同时约束入口、done/next 子命令、git、corral 的 env shebang 和 CHECK_CMD。程序升级或路径删除后的漂移属于外部安装生命周期，本次不做版本锁定。
- 自定义 corral 的示例服务 PATH 必须同时列其运行时目录，例如 `/长期/corral/bin:/长期/runtime/bin:/usr/bin:/bin:/usr/sbin:/sbin`；还应列出 CHECK_CMD 所需工具。只加 corral 目录并不保证可运行，探针已给出反例。

#### 4.3 幂等、旧文件和未知目标

- 仍先完成所有源文件、目标和依赖预检，再创建目录、软链或 plist；保留 `lexists`、拒绝断链/目录/未知命令目标、plist 必须为非软链普通文件且内容一致等现有规则。
- **同一 HOME、同一源仓库、同一显式服务配置**下，无关的调用 shell PATH 增减或换顺序不会改变生成内容；重复安装退出 0，内容、链接和 mtime 不变。依赖已被删除时预检拒绝，不能声称此时仍应安装成功。
- 使用自定义服务 PATH 的重装需要再次提供同一输入；省略即选择默认值，和任何主动变更服务配置一样，若生成内容不同就拒绝。不要自动从旧 plist 反读 PATH 当作可信输入，那会把手改文件伪装成“自己上次生成的”。
- 旧 plist 恰好与新配置生成字节相同就复用；否则继续安全拒绝。无论只差 PATH、字段顺序还是 KeepAlive，都不自动迁移，不依据 Label 或几个熟悉字段认领。
- 报错说明“候选服务配置与已有文件不同，尚未改写，请人工核对旧配置”，并说明旧服务不会因一次拒绝而更新。使用者确认迁移时，另行备份、移开旧文件、重新生成；已登记服务的更新/重载仍须人操作。本轮不提供自动删除、强制覆盖或自动 launchctl 路径。

此方案预期只需修改 `install.sh`、直接相关 `tests/install.sh` 和安装说明；经裁定后再同步 ROADMAP。现有 plist 模板键、bin/ 命令解析、看板及推进逻辑无需改动。不提供“自动过滤整条 PATH”备选：过滤规则无法从未知目录、软链或包装器推导长期运行依赖，反而扩大本任务。

### 5. 对照既定设计及需裁定项

| 现有来源 / 约定 | 推荐方案的关系 | 分类 |
|---|---|---|
| ROADMAP:406–407、m5 任务：两条绝对软链、独立 loop、dev.drover.loop、日志位置、先预检后写、仅打印启用命令 | 全部保持；真实安装及服务启用仍需另行授权 | 现行契约，无需重定 |
| m5 幂等目标；README“相同配置重装不改写” | 把无关 shell PATH 与服务配置分开，消除非意图变化；相同显式服务配置仍逐字节复用 | 修复目标；实现依赖下一行设计裁定 |
| ROADMAP:408、README:65、QUICKSTART:26：保存整条安装 PATH、用干净 shell | 改为确定默认值 + 单一显式完整 PATH 输入，不再自动继承当前 shell PATH | **设计变化，需用户决定**；不能把白名单当作已获批准 |
| 当前总是前置 local/bin | 默认保留；显式完整覆盖时按输入顺序，不隐式前置 | **新输入语义需一起决定**，使解释器选择可控 |
| README:63、m5 取舍：旧 plist 只认字节完全一致；未知目标拒绝 | 完整保留；不自动迁移旧 PATH；旧安装可能需要人工迁移一次 | 保持既定安全行为；接受一次人工迁移是方案的兼容代价 |
| 当前不检查 git/corral 存在 | 建议三项入口缺失就安装失败，不运行 corral 探测 | **收紧安装前提，需决定**；这是查得到入口，不是“服务可运行”的证明 |
| CHECK_CMD 原来可使用整条安装 PATH 中任意工具 | 默认 PATH 收缩可能让项目验收工具缺失；通过同一显式输入列出长期工具目录 | **兼容影响随 PATH 政策裁定**，不改变 CHECK_CMD 内容或执行判据 |
| T8 / ROADMAP:339–341：手动指定已有 Anaconda Python 打开看板 | 不改两条命令 shebang、不换 TUI 运行时、不改 shell PATH；只影响生成的后台 plist | 保持已批准设计 |
| corral 契约、AGENTS 的只能向下依赖 | 不读实现、不加 corral 字段、不管理 agent，不假设外部依赖完整 | 保持硬边界 |
| 手动 n → g → n、TASK_GATE、旧工具和服务 | 完全不涉及 | 保持硬边界 |

主控下一轮可裁定的具体内容只有：①是否采用上述默认值和 `DROVER_LAUNCHD_PATH` 完整覆盖语义，并接受自定义环境需显式配置、旧 plist 需人工迁移；②是否把三项入口缺失提升为安装前置失败。**本报告提出方案，不代表上述设计已获批准；ROADMAP 本轮未改。**

### 6. 后续最小定向测试与有效 RED → GREEN 计划

先获第二阶段明确范围，再把以下检查加进 `tests/install.sh`；本轮探针不是已交付的回归测试，不据此宣称 GREEN。

1. **无关 shell PATH 不影响结果**：同一临时 HOME 首装，再增加/交换两个空目录、换系统目录顺序，第二次必须退出 0，所有目标内容/模式/mtime 相同；保留旧的补 local/bin 和重复分量场景。当前代码在第二次明确退出 1，已有有效 RED。
2. **临时 Python 不进入默认服务 PATH**：合成激活 venv、conda 目录、shim 排在安装 PATH 前面，断言 plist 的默认 PATH 精确等于批准值；在该服务环境下用合成 shebang 哨兵证明不会选中临时入口。当前会保存这些目录，已有有效 RED。加一个无激活变量但 PATH 仍有临时目录的子场景，避免仅检查 VIRTUAL_ENV 名字。
3. **显式完整配置及外部依赖**：用临时自定义 corral + 独立合成 runtime + 合成验收工具，提供完整服务输入。断言生成 PATH 保持输入优先级、只去重、不混入 shell PATH；按生成环境运行这些合成命令成功。只给 corral 绝对入口但漏掉 runtime 的负例必须仍能失败，防止把“找到入口”误写成“保证可运行”。当前实现忽略新输入，应先在最终 PATH 或解析目标上失败；不能把 fixture 的假 runtime 语法错误当 RED。
4. **输入与预检**：显式空值、空/相对分量非零退出且 HOME 快照完全不变；重复绝对分量可去重。若批准严格依赖预检，增加缺 python3/git/corral 的隔离子场景，断言缺失名称及零写入。对“服务 PATH 缺 Python”的检查仍使用可用安装器 Python 启动，不能把 shell 自己找不到安装器的 127 当目标 RED。
5. **旧配置保护**：用旧算法生成的 plist（测试 fixture）及正确命令软链，确认不一致仍拒绝且零写入；新配置完全一致则幂等；仅差 PATH、被手改字段、额外未知字段和 plist 软链也不自动认领。已有未知普通文件/目录/断链、两个命令目标冲突及后项冲突不留前项的断言全部保留。
6. **原 9 项安全回归**：临时 HOME、特殊字符路径、写入沙箱、静态禁止实际 launchctl、仅打印提示、不写 LaunchAgents、旧工具/rc 保持不变继续保留。若加入依赖预检，在每个隔离 HOME 预先放合成依赖，snapshot 在 fixture 完成后拍摄；不以宿主机真 corral 是否安装来决定测试成败。不得放宽旧目标保护或减少断言。

现有断言精确调整范围：

- `tests/install.sh:90–91` 是“每一个输入 PATH 分量都在生成 PATH 中”，**并非字节原样保存**，也没有断言顺序。它必须随批准的政策替换为：默认 PATH 精确值、无关/临时分量不在其中；另测显式 PATH 的顺序和去重。替换是更改输入来源后的新契约，不能直接删掉不补。
- `:85–89` 的 ProgramArguments / HOME 断言，以及 Label、KeepAlive、RunAtLoad、日志、plutil 检查全部保留；推荐方案不改参数形状。
- `:101–109` 补 local/bin 后的幂等和提示检查继续保留，追加无关变动场景。依赖预检不要求 shell wrapper 改形状，`:162–180` 的静态审计原则及“launchctl 只在 print 中”保持。

执行顺序：新定向检查在当前生产上先得到目标 RED → 最小安装器实现 → 相同检查 GREEN → 整份隔离安装套件及 `sh -n install.sh tests/install.sh`、`plutil -lint launchd/dev.drover.loop.plist`、`git diff --check`。如做缺陷自证，只在临时生产副本恢复“捕获 shell PATH”或去掉显式输入校验，确认新用例准确转红；不改工作区生产做注入，不运行真实服务。bin/ 不变时不跑全仓库套件。

### 7. 本轮交付与剩余工作

已交付可复核矩阵、三类必需复现、解析链、一个具体推荐方案、兼容代价、设计裁定点和后续测试计划。提交范围仅本任务文件，探针及生成物留在上述临时目录。不改真实 PATH、shell rc、安装目录、LaunchAgents、真实任务状态或 TASK_GATE；未碰 T8 stash、受保护项目、corral 实现和其它 agent；不合并、不推送、不清理分支/worktree、不打收尾记号。

剩余：主控审阅并明确第二阶段设计/实施范围；实施后按原任务安排独立审查。真实 corral 的运行时完整性、真实 launchd 启用及设备使用均未验证，本轮没有把这些列为已通过。DONE 只表示第一阶段调研结束。


## 主控第一阶段审查（2026-09-22）

调研通过，T14 未完成；实施暂未启动。被审提交 `8c2e7b4`，agent idle、工作区干净，仅本任务文档变化。主控读取探针源码与解析入口后，在原开发 worktree 前台重跑两项缺陷检查（均因目标缺陷 FAIL）、55 次矩阵观察（退出 0）及现有隔离安装套件（9 项通过）。主控矩阵证据 `/private/tmp/drover-m23-ua0xpt1r/matrix-4y8j22pq/`；两项目标 RED 分别在 `test_temporary_python_not_saved-mtg7wqnz/`、`test_unrelated_path_reinstall-uy4e6tlp/`。未运行真实服务、真实 corral 或全仓库测试。

逐项意见：

- 认可固定默认服务 PATH + 单一显式完整覆盖的最小方案，拟采用报告中的默认目录顺序；显式输入只接受非空绝对分量，保持输入顺序并去重，不隐式补目录。这替代 ROADMAP 的继承安装 PATH 行为，尚需用户裁定，不因本审查自动获准。
- 认可不自动识别临时环境、不猜 corral 运行时、不改 bin/ 与看板 Python 选择。默认目录中人为放入的临时软链仍可能失效；查到入口不等于运行时完整，文档不能保证后台必然可用。
- 认可旧 plist 仍逐字节保护、不自动迁移或认领未知文件；已有安装配置不同仍需人工核对。认可既有安全回归保留及定向 RED→GREEN 计划。
- 不采纳“三项入口任一缺失就拒绝整个安装”的建议：安装两条手动命令与启用后台服务相互独立，缺少默认服务 PATH 中的 corral 不应新增全局安装失败条件。建议仅打印最终服务 PATH、三项入口及明确缺项警告，提示启用前补齐；不执行真实工具做验证。显式 PATH 语法无效和未知目标冲突仍在写入前拒绝。这一调整随整体方案交用户裁定。
- 兼容代价需说明：自定义 corral、其运行时和 CHECK_CMD 工具目录以后需在显式完整 PATH 中列全；重装需提供同一显式值。旧 plist 不一致时仍拒绝。手动 n → g → n、loop、TASK_GATE 不变。

待用户批准上述 PATH 政策及“缺项警告、不新增安装硬阻断”后，再更新 ROADMAP、续派同一 agent 实施，并按路由独立交叉审查。本轮不合并、不清 worktree/agent、不打收尾、不推送。主控将调研报告完整同步到主仓库任务文件供审阅；开发分支仍停在调研提交。


## 第二阶段授权：固定常用目录的最小修复（2026-09-22）

用户明确批准：后台配置只使用固定常用目录，不再复制终端整条 PATH；原 agent 实施、补两项回归，审查通过收尾。不新增环境配置项、不实际安装或启动服务。此前默认值加 DROVER_LAUNCHD_PATH、依赖预检/缺项警告、拆分安装命令的提议均未获采用，不实现。

本机主控已验证：默认终端 python3 为 /opt/homebrew/bin/python3（3.14.7），drover list 成功；下列固定 PATH 下 python3 --version、git --version、corral --version 均退出 0。只证明这些入口可运行，不扩大成真实后台引擎验证。

实施范围：
1. 先在 ROADMAP 安装段记下获批取舍，再最小修改 install.sh：生成的服务 PATH 固定为 `<HOME>/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`，HOME 仍按原逻辑展开；不依赖调用 shell 的 PATH。安装器自身的 exec python3、ProgramArguments 及其它安装保护照旧。
2. tests/install.sh 加两项聚焦回归：无关 PATH 增加/换顺序后重装成功且目标不变；合成临时 Python 目录在安装 PATH 最前时不会进入生成的服务 PATH。先在旧实现跑出有效 RED，再最小实现并确认 GREEN。原 PATH 分量包含断言改成固定值精确断言，其它保护断言不删。
3. 保留旧 plist 字节不一致拒绝覆盖、未知目标保护和全量预检。仅按需要修正已有报错中“安装时 PATH 已变”的过时措辞；不增加新依赖检查、选项、配置输入、环境探测或迁移机制。旧 plist 不一致仍人工处理，不自动更新。
4. 同步 README、QUICKSTART 和手册中直接受影响的安装 PATH 说明，简短说明固定目录；其它文字不重写。不改 bin/、模板参数形状、TUI、loop、TASK_GATE 或真实队列。固定目录以外的自定义环境不在本任务自动支持范围，不设计通用解决方案。
5. 只跑定向新测试及整个隔离安装套件、sh -n、模板 plutil -lint、git diff --check。全部使用既有临时 HOME + 写入沙箱；不扩大为全仓库或再次调研环境矩阵。可以用临时旧实现副本确认两项回归确实守住缺陷，无须额外大规模变异检查。
6. 沿用本 worktree、agent 与分支；本文件已由主控同步进开发 worktree，保留前面的报告和主控审查，在末尾追加实施完成记录并一起提交。主仓库 HANDOFF 不动。不合并、不推送、不清理工作目录，不操作真实安装、launchctl、推进命令或全局 PATH。此前安全边界继续有效。

审查调整：仍由主控定向审查；不另开独立交叉审查。初始路由基于广泛环境调查及新配置/预检方案，现经用户明确收敛成固定常量与两项回归，原安全隐私扩展面已移除，按小修规模执行。原 agent 的模型不变，不另开实例。

完成后报告修改、RED/GREEN 与隔离安装结果和提交号，命令前台跑完，最后一行 DONE。

## 第二阶段实施完成记录（2026-09-22）

已按上方最终授权完成最小修复，交主控定向审查；保留此前完整报告、主控审查和授权文字。第一阶段的覆盖变量、依赖预检/警告等方案未实施。

- 先在 ROADMAP 安装段记录获批取舍，再将 `install.sh` 生成的服务 PATH 改为固定常用目录。安装器的 `exec python3`、HOME 展开、ProgramArguments、软链、全量目标预检及 plist 字节比较均保持原样；只更新过时的冲突报错和已有启用提示中的 PATH 指代。
- `tests/install.sh` 仅新增两项回归：无关目录增加/换顺序后重装成功，且目标内容、链接、模式和 mtime 不变；合成临时 Python 确实被安装器调用，但其目录不写入服务 PATH。旧的“包含安装 PATH 全部分量”断言按批准的新契约替换为固定值精确断言；其余保护断言保留。
- README、QUICKSTART、手册只更新直接相关安装/排查说明：服务 PATH 固定、旧 plist 不一致仍人工处理、固定目录外自定义环境不自动支持，安装成功不等于后台可用。未改 bin/、plist 模板、TUI、loop、TASK_GATE 或 HANDOFF。

验证证据：`/private/tmp/drover-m23-implementation-g1v5l6aa/`，每项命令均有 `*-command.json`（原命令及退出码）和同名 `.log`。`task-before.md` 保存收到的完整任务文件，最终核对为新增完成记录前缀完全不变。

1. **RED**：`sh tests/install.sh -v InstallTests.test_reinstall_after_unrelated_path_changes InstallTests.test_temporary_python_path_is_not_saved`，在修改生产前退出 1。前者三个 PATH 子场景均因旧 plist 内容变化拒绝重装，后者断言明确发现临时目录被保存；共 2 项测试、4 处目标失败。安装器调用标记和成功退出检查均先通过，不是探针语法或环境错误。证据 `red.log`。
2. **GREEN**：最小修改后原命令退出 0，2 项通过，证据 `green.log`。
3. **隔离安装回归**：`sh tests/install.sh -v`，11 项全部通过，证据 `install-suite.log`。沿用临时 HOME、写入沙箱及拒绝执行 `/bin/launchctl`；未知目标/预检、特殊字符路径、旧工具及 shell 配置不变、不写 LaunchAgents、不实际启动服务等原有断言均通过。
4. **静态检查**：`sh -n install.sh tests/install.sh`、`plutil -lint launchd/dev.drover.loop.plist`、`git diff --check` 均退出 0。另核对原 9 项测试仍在、只增加指定 2 项，bin/、模板、HANDOFF、AGENTS 与本轮起点一致。

全部命令前台等待结束。没有扩大为全仓库测试、再次环境矩阵或额外变异检查；未运行真实 corral、安装或服务，未改全局 PATH、真实队列和其它项目。不合并、不推送、不清理 worktree/分支、不打收尾记号。实现与隔离验证已完成；后续为主控审查，真实安装与服务启用仍需另行授权。


## 主控第二阶段审查及本地合并（2026-09-22）

结论：通过，必须改 0。被审 `a1b64fc`，开发 worktree 干净；已核对生产 diff 仅固定 PATH 和两条相关提示，原预检、未知目标保护、plist 字节比较及启动边界均不变，bin/ 和模板未动。认可固定值、保留旧配置拒绝覆盖、只更换过时 PATH 断言及简短同步文档的全部取舍；未引入原调研的复杂方案。

主控已读取开发 RED/GREEN 日志：旧实现两项测试因目标缺陷失败（重装三个子场景及临时目录断言），新实现同项通过。主控在被审 worktree 前台重跑完整隔离安装套件，11 项全部通过；sh -n、plutil -lint、git diff --check 均通过。未跑全仓库、未新增独立交叉审查，未执行真实安装、服务或推进。

已本地合并。主仓库原任务文字经字节前缀核对全部在开发提交中，且备份到 `/var/folders/vs/3tm61ygs569g764_td0zxtym0000gn/T/drover-m23-main-review-datepb9g/`，合并保留完整调研、审查和用户授权；原 HANDOFF 改动保留。下一步按安全条件清理本任务 worktree/分支、自开 agent，再补收尾与交接；不推送。
