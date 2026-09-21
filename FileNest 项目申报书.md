# FileNest 项目申报书（复审版）

## 基本信息

- **项目名称：** FileNest Core：MoonBit 安全文件批处理与可恢复事务引擎
- **参赛者及联系方式：** 艾聪丽（联系方式待填写）
- **GitHub 仓库：** https://github.com/aicongli-829/FileNest
- **项目方向：** MoonBit 基础软件生态 / 文件系统工具 / 可恢复批处理
- **项目性质：** 原创项目，非移植项目

## 项目简介

FileNest Core 使用 MoonBit 为批量移动、重命名和路径重构提供“计划—校验—执行—审计—撤销”能力。引擎先根据文件清单与规则生成确定性计划，诊断目标重名、父路径占用和已有文件冲突；执行时采用两阶段暂存，逐步写入日志，并在执行及撤销前复核文件大小、修改时间和 SHA-256。目标存在时绝不覆盖。

项目包含可跨界面复用的纯 MoonBit 核心、Native 文件事务层、CLI 和 `.fnrules` 规则语言。“文件归巢”本地 Web 工作台是示范应用，用于直观验收分类、批量命名、重复检测和撤销流程。

## 项目必要性及通用价值

MoonBit 官方 `async/fs` 提供文件读写、遍历、重命名和锁等底层能力，但上层项目仍需重复处理批量冲突、交换与循环改名、预览后源文件变化、部分执行失败和恢复审计。实现不完整会造成目标覆盖、只完成半批操作或无法恢复。

FileNest 填补底层 I/O 与最终应用之间的安全批处理层，可用于代码仓库路径重构、代码生成产物整理、素材流水线、数据集预处理、工作区迁移和个人文件归档。核心逻辑不依赖浏览器或固定目录，可被 CLI、Web、IDE 插件及其他 MoonBit 工具调用。

## 预期使用场景

1. **代码仓库路径重构：** 预览大批文件迁移，安全处理重名、交换和循环移动，失败后按日志恢复。
2. **素材与构建产物流水线：** 按类型、日期和命名规则标准化资产，向自动化流程输出 JSON、CSV 或 Markdown 计划。
3. **数据集预处理：** 统一文件命名与目录结构，通过 SHA-256 和逐字节比较识别重复样本。
4. **个人文件整理：** 通过 Web 工作台整理下载目录、照片和课程资料，并使用模板、历史与整批撤销。

## 拟实现的核心功能

- 确定性路径变换规划、组合规则和冲突诊断；
- 原生递归扫描、SHA-256 与逐字节重复确认；
- 两阶段无覆盖移动，支持交换和循环改名；
- 文件指纹复核、批次锁、同步日志、历史与撤销；
- 快照比较、空间分析和多格式报告；
- 可复用 MoonBit API、Native CLI、规则语言与本地 Web 示例。

## 当前基础与价值证明

项目已有 36 个 MoonBit 源码及测试文件、6825 行 MoonBit 代码，不跟踪手写 JavaScript；JavaScript 目标通过 64 项测试，Native 目标通过 68 项测试。原生集成测试使用真实临时文件验证扫描、重复确认、三文件移动和整批撤销。

2026-09-21 的合成数据验证包含 12 个目录和 1200 个文件，其中有 30 组重复内容。Release 构建在本机 801 ms 完成扫描并正确返回全部文件和重复组，830 ms 生成 1200 行无冲突计划。完整数据、环境和能力边界见 `docs/VALUE_PROOF.md`。

## 本期计划

本期将固化规划、事务和撤销的公共 API，补充代码仓库、素材与数据集三类复用示例，完成 Windows/Linux 真实文件验证，完善中英文文档，并准备发布可供其他 MoonBit 项目调用的 Mooncakes 模块。

## 参考资料及许可证

- MoonBit 异步文件系统：https://mooncakes.io/docs/moonbitlang/async/fs
- 价值证明：https://github.com/aicongli-829/FileNest/blob/main/docs/VALUE_PROOF.md
- 项目为原创实现，使用 `moonbitlang/async`，采用 MIT License。

## GitHub 仓库

- **项目主页：** https://github.com/aicongli-829/FileNest
- **提交记录：** https://github.com/aicongli-829/FileNest/commits/main
- **工程设计：** https://github.com/aicongli-829/FileNest/blob/main/docs/ARCHITECTURE.md
