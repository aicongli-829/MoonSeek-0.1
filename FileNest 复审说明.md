# FileNest 报名复审补充说明

感谢组委会指出原申报材料对项目必要性和适用范围说明不足。原材料把 FileNest 主要描述为个人文件整理工具，没有准确表达已经实现的可复用基础能力。现补充定位如下：

**FileNest Core 是一个使用 MoonBit 实现的安全文件批处理与可恢复事务引擎，“文件归巢”Web/CLI 是其示范应用。**

MoonBit 官方异步文件系统提供遍历、读写和重命名等底层操作，但批量路径变换仍需要项目自行解决目标冲突、交换与循环改名、预览后文件变化、部分执行失败、日志审计和整批恢复。FileNest 将这些共性机制实现为确定性规划核心和 Native 事务层，可用于代码仓库路径重构、素材流水线、数据集预处理、工作区迁移与归档，也可供 CLI、Web 或后续 IDE 插件复用。

项目已完成 36 个 MoonBit 源码及测试文件、6825 行 MoonBit 代码，不包含手写 JavaScript；JavaScript 目标通过 64 项测试，Native 目标通过 68 项测试。原生集成测试会真实创建文件并验证扫描、重复确认、三文件移动及整批撤销。2026-09-21 的合成数据验证包含 12 个目录和 1200 个文件，Release 构建在本机 801 ms 完成扫描并正确识别 30 组重复内容，830 ms 生成 1200 行无冲突计划。

项目坚持不覆盖目标、执行前后复核文件指纹、两阶段暂存、逐步日志和可撤销，不提供永久删除。本期将固化公共 API，补充代码仓库、素材和数据集三类复用示例，完成 Windows/Linux 端到端验证，并准备发布 Mooncakes 模块。

最新材料：

- 项目仓库：<https://github.com/aicongli-829/FileNest>
- 必要性与价值证明：<https://github.com/aicongli-829/FileNest/blob/main/docs/VALUE_PROOF.md>
- 工程架构：<https://github.com/aicongli-829/FileNest/blob/main/docs/ARCHITECTURE.md>
- 测试说明：<https://github.com/aicongli-829/FileNest/blob/main/docs/TESTING.md>
