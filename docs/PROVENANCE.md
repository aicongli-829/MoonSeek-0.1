# 来源、依赖与差异说明

FileNest 是本仓库新实现的本地文件整理工具，开发过程中使用了 AI 辅助。项目未复制其他文件整理应用的源代码。

## 依赖

- MoonBit 官方工具链与 core：用于编译，以及 JSON、字符串、集合和正则能力。MoonBit core 使用 Apache-2.0 许可证。
- Node.js 内建模块：文件系统、HTTP、SHA-256 和测试。项目没有 npm 第三方运行时包。
- GitHub Actions：使用 `actions/checkout`、`actions/setup-node` 和 MoonBit 官方安装脚本执行持续集成。

## 初步生态查重

检索日期：2026-09-15。

公开 Mooncakes 和 MoonBit 项目检索没有发现明确的“分类整理＋批量重命名＋重复内容检查＋可撤销操作”完整产品。这个结论不能覆盖未被索引、未发布或同期申报的项目。

已知邻近能力：

- [moonbitlang/async/fs](https://mooncakes.io/docs/moonbitlang/async/fs) 提供文件系统 API。FileNest 提供面向用户的规则规划、预览、重复检查和恢复流程，当前版本使用 Node 作为文件系统适配器。
- [MoonBit HTTP 文件服务器示例](https://www.moonbitlang.com/pearls/2025/10/22/moonbit-http-server) 提供目录分享和下载，不包含 FileNest 的整理规划与事务日志。

## 代码规模口径

`node scripts/count-lines.mjs` 统计 `.mbt`、`.mjs`、`.js`、`.html` 和 `.css` 中的非空、非独立注释物理行，排除文档、配置、第三方工具链、构建产物和演示数据。

统计结果会分别报告 MoonBit 核心、Node 适配层、网页界面和测试。规模数据用于解释实现范围，不能代替赛事官方验收标准；项目功能和测试优先于追求行数。

## 发布状态

- GitHub：<https://github.com/aicongli-829/FileNest>
- Mooncakes：尚未发布。

当前 `moon.mod.json` 中的模块名是开发阶段名称。发布 Mooncakes 前，需要确认账号命名空间和比赛对可发布包结构的要求。
