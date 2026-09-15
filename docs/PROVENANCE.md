# 来源、依赖与差异说明

FileNest 是本仓库新实现的本地文件整理工具，开发过程中使用了 AI 辅助。项目未复制其他文件整理应用的源代码。

## 依赖

- MoonBit 官方工具链与 `moonbitlang/core`：编译、JSON、字符串和集合。
- `moonbitlang/async` 0.21.3：Native 文件系统、IO、socket 和 HTTP 服务。
- HTML/CSS：浏览器结构与样式，不使用前端框架。

项目不依赖 Node.js、npm 包或云端服务。浏览器 JavaScript 是 MoonBit 构建产物，不进入 Git。

## 初步生态查重

检索日期：2026-09-15。

公开 Mooncakes 和 MoonBit 项目检索没有发现明确的“分类整理＋批量重命名＋重复内容检查＋可撤销操作”完整产品。这个结论不能覆盖未被索引、未发布或同期申报的项目。

邻近基础能力：

- [moonbitlang/async/fs](https://mooncakes.io/docs/moonbitlang/async/fs) 提供通用文件系统 API；FileNest 在其上实现规则规划、预览、重复确认和事务恢复。
- [MoonBit HTTP 文件服务器示例](https://www.moonbitlang.com/pearls/2025/10/22/moonbit-http-server) 演示目录服务；FileNest 的本地工作台只提供固定资产和受会话保护的整理接口。

## 代码规模口径

规模统计只计算 Git 跟踪的 `.mbt` 源文件，不包含依赖缓存、构建产物、HTML/CSS、文档或配置。仓库不跟踪 `.js/.mjs`。规模用于说明实现范围，不能代替赛事验收标准。

## 发布状态

- GitHub：<https://github.com/aicongli-829/FileNest>
- Mooncakes：尚未发布。

当前模块名为开发阶段名称。发布 Mooncakes 前需要确认账号命名空间和赛事对包结构的要求。
