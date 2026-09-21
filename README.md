# FileNest · 文件归巢

简体中文 | [English](README.en.md)

FileNest Core 是一个使用 MoonBit 开发的安全文件批处理与可恢复事务引擎。“文件归巢”本地工作台和 CLI 是它的完整示范应用，提供分类整理、批量重命名、重复文件检查和整批撤销。

核心算法、原生文件系统适配、SHA-256、事务日志、CLI、本地 HTTP 服务和浏览器交互都使用 MoonBit。HTML/CSS 负责页面结构和样式；浏览器脚本由 MoonBit 编译生成，只保存在被 Git 忽略的 `_build` 目录。文件内容始终留在本机。

项目的必要性、可复用场景与千文件验证结果见[价值证明](docs/VALUE_PROOF.md)。

## 功能

- **分类整理**：按类型、修改月份、类型与月份、自定义扩展名或关键词归档。
- **安全批处理引擎**：确定性规划、冲突诊断、两阶段暂存、文件指纹复核和批次日志。
- **批量重命名**：前后缀、删除、替换、大小写、空格规范化、自然顺序编号和正则规则。
- **重复文件检查**：先按大小与 SHA-256 筛选，再逐字节确认；副本移入可撤销的隔离目录。
- **安全预览**：展示原路径、目标路径、冲突和无效项；目标已存在时绝不覆盖。
- **事务与撤销**：所有文件先进入批次暂存区，每一步同步写入 JSON 日志；支持循环改名和整批恢复。
- **分析与快照**：空间占用分析、重复空间建议，以及新增、删除、修改和移动对比。
- **双界面**：本地浏览器工作台与原生 CLI 共用同一套 MoonBit 核心。
- **报告**：导出 CSV、JSON 和 Markdown 预览。
- **可读规则**：`.fnrules` 支持注释、扫描范围、分类和重命名流水线。

## 环境

安装 [MoonBit 工具链](https://www.moonbitlang.com/download)。项目不需要 Node.js，也没有 npm 依赖。

Windows 下首次使用 Native 目标时，MoonBit 可能调用已安装的 Visual Studio Build Tools。Linux/macOS 使用系统 C 工具链。

## 启动图形界面

```sh
git clone https://github.com/aicongli-829/FileNest.git
cd FileNest
moon update
moon build webui --target js --release
moon run --target native cmd/filenest -- serve
```

浏览器打开 `http://127.0.0.1:4173`。服务仅监听 `127.0.0.1`。指定初始目录或端口：

```sh
moon run --target native cmd/filenest -- serve --root "D:/Downloads" --port 4174
```

## 命令行

```sh
moon run --target native cmd/filenest -- --help
moon run --target native cmd/filenest -- scan "D:/Downloads"
moon run --target native cmd/filenest -- analyze "D:/Downloads"
moon run --target native cmd/filenest -- preview "D:/Downloads" --config examples/downloads.json
moon run --target native cmd/filenest -- preview "D:/Downloads" --rules examples/downloads.fnrules --csv
moon run --target native cmd/filenest -- apply "D:/Downloads" --config examples/downloads.json --yes
moon run --target native cmd/filenest -- snapshot "D:/Downloads" --output before.json
moon run --target native cmd/filenest -- diff "D:/Downloads" --snapshot before.json
moon run --target native cmd/filenest -- history "D:/Downloads"
moon run --target native cmd/filenest -- undo "D:/Downloads" BATCH-ID --yes
```

`scan` 和 `preview` 不会移动文件。`apply` 必须显式传入 `--yes`，并在执行前重新扫描和验证文件指纹。

## 开发与验证

```sh
moon update
moon fmt --check
moon check --target js
moon test --target js
moon build webui --target js --release
moon check --target native
moon test --target native
moon build cmd/filenest --target native --release
```

项目测试覆盖排序、分类、命名、路径校验、配置、报告、分析、快照、规则解析、事务状态机、SHA-256 和 Windows 时间换算。原生集成测试会在临时目录完成扫描、重复文件确认，以及一次完整的 `apply` 与 `undo`。

## 项目结构

```text
/*.mbt             确定性的 MoonBit 核心库
/native/*.mbt      文件扫描、SHA-256、事务、HTTP 服务和 CLI
/webui/*.mbt       浏览器状态、规则编辑、渲染与请求编排
/cmd/filenest      MoonBit Native 可执行程序入口
/web               静态 HTML 和 CSS
/examples          JSON 与 .fnrules 示例
/docs              架构和来源说明
```

`examples/` 包含下载目录、照片、课程资料、代码仓库迁移和数据集预处理规则。首次使用任何规则时都应先执行 `preview`。

仓库不跟踪手写 `.js` 或 `.mjs` 文件。`moon build webui --target js --release` 生成浏览器可执行脚本。

## 安全边界

- 根目录和每个相对路径都经过校验；拒绝绝对路径、`..`、符号链接和内部状态目录。
- 服务校验 loopback Host、同源 Origin、跨站请求标记和随机会话令牌。
- 执行与撤销都会重新核对大小、修改时间和 SHA-256。
- 文件移动使用原生 `rename(..., replace=false)`；操作系统保证目标存在时失败。
- 两阶段暂存支持名称交换与循环移动，日志使用同步临时文件和原子替换更新。
- 一次最多扫描 10,000 个文件。当前实现会读取文件内容计算摘要，大文件扫描需要时间。
- 重复副本只会隔离，不会永久删除。
- 遗留 `.filenest/lock` 需要在确认没有 FileNest 进程运行后手动删除。

## 开源与参赛

项目使用 [MIT License](LICENSE)。必要性与价值证明见 [docs/VALUE_PROOF.md](docs/VALUE_PROOF.md)，生态查重和来源见 [docs/PROVENANCE.md](docs/PROVENANCE.md)，工程设计见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。Mooncakes 发布前仍需确认参赛账号命名空间。
