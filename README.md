# FileNest · 文件归巢

FileNest 是一个本地文件整理工具，提供分类整理、批量重命名、重复文件检查和可撤销操作。

MoonBit 实现分类、命名、自然排序、路径诊断、计划生成、重复分组、报告、分析、快照对比、规则解析和事务状态机；Node.js 提供本机文件访问、内容核验与原子日志写入；浏览器提供中文操作界面。文件内容只在本机处理，不上传云端。

> 当前版本为 0.1.0 黑客松首版。建议先用自带的合成样例体验，再处理真实文件。

## 主要功能

- **分类整理**：按类型、修改月份、类型＋月份归档；支持扩展名和文件名关键词组成的自定义规则。
- **批量重命名**：前后缀、删除和替换文字、正则字面替换、自然顺序编号、空格与大小写规范化，规则可调整顺序。
- **重复文件检查**：先按 SHA-256 筛选，再逐字节确认；手动选择副本并移入隔离目录。
- **预览和冲突检测**：显示完整原路径、目标路径和处理状态；冲突时跳过或自动追加编号，绝不覆盖已有目标。
- **历史和恢复**：逐步保存操作记录；支持批次撤销，以及中途停止后的恢复。
- **筛选和模板**：扩展名筛选、排除目录、递归开关、内置模板和自定义模板。
- **报告导出**：CSV、JSON 和 Markdown 格式的整理预览。
- **空间分析**：统计扩展名、分类、顶层目录、大小区间、最大文件和重复空间，并逐组建议保留的重复文件。
- **快照对比**：保存轻量文件清单，再次扫描时识别新增、删除、修改和移动的文件。
- **图形界面和 CLI**：普通用户可以使用浏览器界面，也可以在脚本中调用命令行。
- **可读规则文件**：`.fnrules` 支持注释、引号、扫描范围、分类和重命名流水线，并提供精确到行的错误信息。

## 快速开始

需要 [Node.js 22 或以上](https://nodejs.org/)和 [MoonBit 工具链](https://www.moonbitlang.com/download)。项目没有 npm 第三方运行时依赖。

```sh
git clone https://github.com/aicongli-829/FileNest.git
cd FileNest
npm run build
npm start
```

浏览器打开 `http://127.0.0.1:4173`。从文件资源管理器地址栏复制完整文件夹路径，粘贴到“工作文件夹”。

如果 Windows PowerShell 禁止执行 `npm.ps1`，可使用 `npm.cmd run build` 和 `npm.cmd start`，或直接运行：

```sh
node scripts/build.mjs
node host/server.mjs
```

端口被占用时可以指定其他端口：

```sh
node host/server.mjs --port 4174
```

### 用演示文件体验

```sh
npm run demo
```

脚本会在 `.scratch/demo-*` 中创建一组可丢弃的合成文档、图片和重复副本，不会读取个人资料。复制脚本输出的路径到 FileNest，然后：

1. 扫描演示文件夹。
2. 选择分类方式，添加需要的命名规则。
3. 在“重复文件”中勾选一份待隔离副本。
4. 更新预览，确认目标位置，再执行整理。
5. 在“操作历史”中选择“恢复原状”。

## 命令行

```sh
node host/cli.mjs --help
node host/cli.mjs scan "D:/Downloads"
node host/cli.mjs analyze "D:/Downloads"
node host/cli.mjs snapshot "D:/Downloads" --output before.json
node host/cli.mjs diff "D:/Downloads" --snapshot before.json
node host/cli.mjs preview "D:/Downloads" --config examples/downloads.json
node host/cli.mjs preview "D:/Downloads" --rules examples/downloads.fnrules
node host/cli.mjs apply "D:/Downloads" --config examples/downloads.json --yes
node host/cli.mjs history "D:/Downloads"
node host/cli.mjs undo "D:/Downloads" BATCH-ID --yes
```

CLI 的 `apply` 会重新扫描并生成计划。需要审核并执行同一份预览时，请使用网页界面。扫描本身不会移动文件；读取模板或历史时会在工作文件夹创建 `.filenest` 元数据目录。

## 开发和验证

```sh
npm run check
npm test
node scripts/count-lines.mjs --require-4000
```

- `npm run check` 执行 MoonBit 编译检查、核心测试和 JavaScript 目标构建。
- `npm test` 使用 Node 内置测试框架和独立临时文件夹验证扫描、重复比较、模板、HTTP 接口及恢复流程。
- 行数统计排除文档、配置、空行、独立注释、第三方工具链和编译产物，分别报告 MoonBit、适配层、界面与测试。总源码行数不等于 MoonBit 行数。

## 项目结构

```text
*.mbt
  MoonBit 核心库：计划、报告、分析、快照、规则、配置和事务决策，无文件系统副作用
host/
  文件系统与加密摘要适配、事务日志、本地 HTTP 服务和 CLI
web/
  无框架中文界面
tests/ + planner_test.mbt
  文件系统、HTTP、规则及恢复测试
scripts/
  构建、演示数据和代码统计
docs/
  架构、限制与来源说明
```

## 使用边界

- 本地单用户工具；服务只监听 `127.0.0.1`，不适合开放到公网。
- 一次最多扫描 10,000 个文件。首版会读取所有选中文件的内容，大文件扫描需要时间。
- 文件移动依赖同卷硬链接，适合支持硬链接的本地文件系统，例如 NTFS。跨卷、FAT/exFAT 和部分网络盘不支持；失败时会保留可恢复日志。
- 不跟随符号链接或目录联接。运行期间不要同时使用其他程序调整所选目录结构。
- 文件内容或修改时间变化、恢复位置被占用时，FileNest 会停止恢复并保留现状；新增的空目录不会删除。
- 崩溃后可以恢复常见的中断状态，但当前版本不承诺突然断电下的完整事务持久性。
- 重复副本只会隔离，不会永久删除，因此不会立即释放磁盘空间。
- 日期分类使用文件修改时间所在的本地月份，尚未读取照片 EXIF 拍摄日期。
- 正则替换值按字面处理，不支持 `$1` 一类捕获组替换。
- 当前没有 AI 内容分类、相似照片识别、后台监控、云同步或安装包。

## 开源与参赛

项目使用 [MIT License](LICENSE)。本项目使用 AI 辅助开发，维护者负责代码审阅和最终交付。生态查重、依赖和来源见 [docs/PROVENANCE.md](docs/PROVENANCE.md)，工程设计见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

Mooncakes 尚未发布。发布前需要确认 Mooncakes 用户命名空间和赛事验收要求。
