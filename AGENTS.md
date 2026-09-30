# AI 工作合同

本文件适用于整个仓库。进入项目后先执行只读检查，再根据用户任务决定是否修改。

<!-- template:usage -->
## 模板模式

`project.manifest.json` 中 `template.isTemplate` 为 `true` 时，本仓库仍是模板 `0000-002-ModuleReady`：

- 示范模块 `HistoryExemplum` 与 `{{...}}` 占位符都是有意保留的；模板自身跑不带 `-Instantiation` 的合同检查。
- 改模板时保证示范模块仍能构建、离线测试全过；新的踩坑经验写进下面的「模块开发要点」，
  能机械检查的同时加进 `b-Code/Test-ProjectContract.ps1`。
- 派生仓第一件事是运行 `b-Code/New-ModuleFromTemplate.ps1`（步骤见 README），它会删掉本节。

<!-- /template:usage -->
## 启动读取顺序

1. 读取根目录 `project.manifest.json`，确认项目身份、状态、活动目录和可用命令。
2. 读取根目录 `README.md` 和 `b-Office/current/项目概览.md`。
3. 根据任务读取 `b-Office/current/技术合同.md`、`有效决策.md` 或 `验证合同.md`；涉及目录治理时
   读取 `b-Office/文档中心.md` 的“目录规范”，涉及跨项目复用时再读取 `b-Office/package/模块API.md`。
4. 只进入 manifest 声明的活动目录。发现未登记目录时，先确认其级别、所有者和用途。

## 真值与冲突处理

- 用户当前指令决定本次任务范围，但不能隐式授权提交、推送、发布或破坏性操作。
- 目标行为以现行需求和有效决策为准；当前实现以测试、运行结果和源码共同判断。
- `项目概览.md` 中的状态只描述进度，不得代替技术或验证合同。
- `b-Office/history/` 不属于常用读取范围。确需版本背景时只读取版本号最高的最新一份 `V*`
  文档；旧 V 文档仅在用户明确要求追溯指定版本时读取最小必要部分，且不得覆盖现行合同。
- 根目录可见文件夹只允许 `a-*` 子项目、`b-*` 项目组件和 `z-*` 跨项目复用元目录。
- 文档与实现冲突时必须指出冲突，不能静默选择一方并改写另一方。

## 工作边界

- 修改前后检查 Git 状态，保留用户已有改动，不回退无关文件。
- 默认不扫描 `b-Office/history/`、`z-Publish/`、生成目录或大型二进制文件。
- 不直接编辑生成物、正式发布快照、归档和第三方依赖；应修改其权威源并按既定流程生成。
- 不把密钥、令牌、个人路径或机器专用状态写入仓库。
- 不执行 Git commit、tag、push、正式发布或外部部署，除非用户明确要求。
- 新增活动目录、外部依赖或验证命令时，同步更新 `project.manifest.json` 和相关现行文档。

## 模块开发要点

以下每条都来自真实事故；标 ✔ 的已由合同检查或离线测试机械守住。

- **改动只进 dev 工作区。** 代码改动先 `vulcan.dev.start`，在 F 盘工作区里改，`submit` 送审热装，
  用户批准后 `finish`。直接改主树最后没法 finish。
- **发布描述在本仓，不改宿主。** 宿主 5.8.0 起没有模块登记表，打包与验证步骤写在本仓 `project.manifest.json`
  的 `publish` 节（实例化时随改名生成）；缺了 `submit` 拒收。加验证步骤就在工作区里改这一节。✔
- **版本三处一致**：`<模块>Version.props`、`module.manifest.json`、`project.manifest.json`。
  不一致时宿主静默跳过整个模块。✔
- **`ModuleInfo.ModuleName` 显式写死模块名**：缺省值是程序集名，同时也是指令域。✔
- **页面 owner = `History` + 首字母大写的指令域**，与模块名无关；对不上整页被 Aurora 静默拒收。✔
- **界面协议指令**（`<域>.ui.describe / actions / data`）只读并带 `HiddenReason`。✔
- **宿主程序集 `Private=false`**：部署时由宿主提供，包里不带副本；测试工程反过来要 `Private=true`。
- **`.gitattributes` 必须有 `z-Publish/** binary`**：否则快照入库被规范换行，finish 热装 SHA 不符。✔
- **`.ps1` 必须带 UTF-8 BOM**（PS 5.1 按代码页读无 BOM 脚本）；`SHA256SUMS` 与 manifest 不能带 BOM。✔
- **模块内不定义 `[ComImport]` 类型**：宿主用可卸载装载上下文，其中的类型不能做 COM 互操作；
  要用 COM 时把 Interop 装进 `AssemblyLoadContext.Default`，按接口名反射调用。✔
- **不读已移除的上下文成员**（`context.Settings` / `context.DataDirectory`）。✔ 宿主日志用
  `context.Log`（5.5.0 起），指令过程用 `CommandContext.Progress`，别在模块里另建日志。
- **不跨仓 ProjectReference**，文档里也不写指向别的仓的相对链接（工作区里必然失效）。✔
- **外部程序的 API 语义以真机标定为准**：文档与实测不符时，把标定证据写进有效决策，用单元测试钉住实测组合。
- **手写 JSON 用编辑工具整文件写**，不要经 shell heredoc（反斜杠会被吃掉）。

## 实施与验证

- 优先沿用仓库现有结构和工具；只在确有复用价值时增加抽象。
- 每项需求应有可识别的需求编号和对应验收方式。
- 先运行与改动直接相关的快速检查，再按风险运行完整验证。
- 无法执行的检查必须在交付时说明原因和剩余风险，不能把“未运行”写成“已通过”。
- 任务完成时，代码、现行文档、状态和 manifest 应相互一致。
