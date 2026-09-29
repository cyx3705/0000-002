# HistoryExemplum 模块 API

模块版本：**0.1.0**；宿主基线：**HistoryVulcan 5.1.2**。

本文件是**总线面**合同：模块消费方的权威合同，随发布候选进包（`docs/模块API.md`）。
模块内部类型见 `b-Office/current/技术合同.md`；AI 面（MCP 工具）由 MCP 服务封装，本文件不重复。

## 这个模块提供什么

{{模块一句话描述}}

指令域：`exemplum`。模块 `ui=true`，`mcpExposure=readonly`（只有标 `Readonly` 的指令投影到 MCP）。

## 指令

每条指令一节，表格五格都要填；`Data` 写确切的 .NET 类型，没有就写「无（`null`）」。

### exemplum.hello.ping

| 格 | 内容 |
| --- | --- |
| 能做什么 | 示范：记一次招呼并刷新页面表格 |
| 谁会用 | 页面「打招呼」按钮 |
| 怎么调 | `exemplum.hello.ping`（无参数） |
| `Data` 的确切类型 | 无（`null`）。`Message`：`你好，这是第 N 次招呼。` |
| 失败与边界 | 不失败；Aurora 不在时表格刷新静默跳过 |

### exemplum.hello.echo（只读）

| 格 | 内容 |
| --- | --- |
| 能做什么 | 示范：原样返回文本 |
| 谁会用 | 控制台 |
| 怎么调 | `exemplum.hello.echo text=<文本>`，`text` 必填 |
| `Data` 的确切类型 | 无（`null`）。`Message` 即输入文本 |
| 失败与边界 | 缺 `text` 时由总线参数校验失败 |

### exemplum.hello.list（只读）

| 格 | 内容 |
| --- | --- |
| 能做什么 | 示范：列出招呼记录 |
| 谁会用 | AI（MCP）、控制台 |
| 怎么调 | `exemplum.hello.list` |
| `Data` 的确切类型 | `IReadOnlyList<IReadOnlyDictionary<string,string>>`，每行键：`id`、`index`、`time`（`HH:mm:ss`），最近的在前 |
| 失败与边界 | 不失败 |

## 界面内部协议（不要跨模块调）

`exemplum.ui.describe` / `exemplum.ui.actions` / `exemplum.ui.data` 是 Aurora 页面协议，声明了 `HiddenReason`。
页面 owner 与场景 id 为 `HistoryExemplum`；页面 id `exemplum`。
