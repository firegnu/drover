# 任务：看板滚动区域位置条

2026-09-24，用户要求所有可滚动列表显示滚动条，并明确要求主控自己实施、不委派；调查后获准开工。直接在 main 完成，没有开发 agent、分支或 worktree 需要清理。

## 范围与实现

- 正文、历史、整页详情和宽屏项目列表共四处增加显示型位置条。暗灰细轨道、浅灰粗滑块，长度表示可见比例，首尾贴边，至少一格；没有溢出时隐藏。
- 正文和历史预留两列（一列条、一列空隙），文字按剩余宽度换行；整页条使用最右侧空白列，项目条复用原分隔线位置。局部区域按实际裁切后的可见行数计算。
- 只改 draw 展示层，header、底栏、业务数据及输入分发保持。现有滚轮/按键继续使用，位置条不支持点击和拖动。设计见 ROADMAP「滚动区域的位置条」。
- 按用户要求更新 AGENTS.md：默认不做 PTY 录屏、批量画面录制或录屏截图/拼图，也不间接运行会录制 PTY 的测试；优先轻量合成屏幕和定向验证。

## 完成与主控自审

通过，无待修复项；尚未进行实际终端主题/字体下的用户目视验收。

- 新增 `tests/board-scrollbars.py`：9 项通过，覆盖四处首尾与中间位置、比例、隐藏、裁切、宽窄与极小尺寸、单多项目、Unicode/Tab/字面轨道字符、无色及无双向滚轮降级、文字不被覆盖和 VM 不变。
- RED → GREEN：四处分别先运行检查，旧实现因空白位置/普通分隔线没有滑块而失败，实现后通过。最终另用 main 原版源文件运行四项表面检查，得到 6 个预期失败（整页含三个宽度），确认检查能发现原缺陷；没有语法或夹具错误。
- 原正文滚动 10 项、历史 13 项通过。只调整文字区域断言，排除新预留的两列，仍完整检查原文和局部独立性。
- `board-header.py`、`board-layout.py` 的轻量部分通过；原分栏断言改为按坐标排除滚动条，保留分栏和所有末尾标记可达性检查。另对 12 种场景 × 单多项目 × 7 种尺寸共 168 组合成字符网格比较，新旧 header 与底栏完全一致。
- `git diff --check` 通过。未运行全套 shell 回归；本次只改展示层，且 `drover-board.sh` 及部分旧测试会间接进行 PTY 录制。没有进行 PTY 录屏、生成画面文件或拼图。

轻量布局复跑方式（只跳过现有的录屏入口，保留其余检查）：

```python
from pathlib import Path
import runpy
from unittest.mock import patch
original = runpy.run_path
def without_recording(path, *args, **kwargs):
    if Path(path).name == 'board-tab-pty.py':
        print('SKIP board-tab-pty.py: user requested no PTY recording')
        return {}
    return original(path, *args, **kwargs)
with patch.object(runpy, 'run_path', without_recording):
    original('tests/board-layout.py', run_name='__main__')
```

仅本地提交并打收尾记号，不推送；未操作真实队列、服务、安装或其他项目。既有 PTY 测试问题不在本轮处理范围。
