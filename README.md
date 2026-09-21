# MoonMigrate

简体中文 | [English](README.en.md)

**MoonMigrate 是使用 MoonBit 编写的版本化文件系统迁移框架。** 它把应用升级时的目录重构、配置更新、资源搬迁和旧缓存隔离写成可审查的迁移清单，并提供预览、前置校验、事务日志和整批回滚。

数据库有成熟的 schema migration，应用数据目录却经常依赖一次性脚本。脚本执行到一半、目标已存在、旧文件被用户修改或版本链断裂时，很容易留下无法判断的混合状态。MoonMigrate 为这类升级任务提供统一的 MoonBit API 与 Native CLI。

## 适用场景

- 桌面应用升级用户数据目录或配置格式；
- 插件、编辑器扩展和本地服务迁移持久化状态；
- 安装器与更新器搬迁资源并清理旧布局；
- CLI 工具升级缓存、索引和生成产物目录；
- 项目模板、素材管线和开发工作区演进；
- 任何需要“先预览、可追溯、可回退”的批量文件变更。

## 已实现

- **版本化迁移链**：校验迁移 ID、版本范围、分支、断点和目标版本边界。
- **六种操作**：`mkdir`、`move`、`copy`、`write`、`replace`、`quarantine`。
- **执行前预检**：路径、文件类型、目标占用、文本条件和可选 SHA-256 前置条件。
- **安全执行**：所有路径限制在所选根目录；移动和复制不覆盖已有目标。
- **持久状态**：在 `.moonmigrate/state.json` 记录当前数据版本。
- **逐步日志**：在 `.moonmigrate/history` 记录每一步的 `pending/running/done` 状态。
- **整批回滚**：反向恢复移动、写入、替换和隔离操作，清理迁移创建的文件与空目录。
- **可选步骤**：允许兼容不同历史安装状态，同时保持计划可审计。
- **纯 MoonBit 实现**：核心模型、CLI、SHA-256、原生文件操作与测试均为 MoonBit。

## 快速开始

安装 [MoonBit 工具链](https://www.moonbitlang.com/download)，然后：

```sh
git clone https://github.com/aicongli-829/MoonMigrate-v1.0.git
cd MoonMigrate-v1.0
moon update
moon run --target native cmd/moonmigrate -- migrate-plan ./demo --manifest examples/moonmigrate.json
```

预览通过后显式执行：

```sh
moon run --target native cmd/moonmigrate -- migrate-apply ./demo --manifest examples/moonmigrate.json --yes
moon run --target native cmd/moonmigrate -- migrate-status ./demo
moon run --target native cmd/moonmigrate -- migrate-rollback ./demo BATCH-ID --yes
```

可用 `--to 2` 只迁移到指定版本。清单格式、完整示例和回滚语义见[迁移指南](docs/MIGRATIONS.md)。

## 清单示例

```json
{
  "formatVersion": 1,
  "project": "notes-app",
  "migrations": [{
    "id": "data-v1",
    "fromVersion": 0,
    "toVersion": 1,
    "steps": [
      { "id": "layout", "op": "mkdir", "path": "data/v1" },
      { "id": "settings", "op": "move", "from": "settings.json", "to": "config/settings.json" },
      { "id": "marker", "op": "write", "path": "data/version", "content": "1\n" },
      { "id": "old-cache", "op": "quarantine", "from": "cache/index.old", "optional": true }
    ]
  }]
}
```

`expectedSha256` 可用于 `move`、`copy`、`write`、`replace` 和 `quarantine`，确保迁移只处理开发者验证过的旧内容。

## 与一次性脚本的差别

| 能力 | 一次性脚本 | MoonMigrate |
|---|---|---|
| 执行前完整预览 | 通常没有 | 有 |
| 版本链与断点校验 | 手工处理 | 自动 |
| 目标防覆盖 | 取决于脚本 | 强制 |
| 内容前置条件 | 需重复实现 | SHA-256 / 文本条件 |
| 中间状态记录 | 需重复实现 | 逐步持久化日志 |
| 回滚 | 通常另写脚本 | 由执行记录生成 |
| 可复用 API | 很少 | MoonBit 核心与 Native 层 |

## 开发验证

```sh
moon fmt --check
moon check --target native
moon test --target native
moon build cmd/moonmigrate --target native --release
```

当前测试包含迁移链规划、无效路径与版本诊断，以及在真实临时目录中依次执行六类操作并完整回滚。

## 项目结构

```text
/migration.mbt          迁移清单模型、校验与确定性计划
/native/migrations.mbt  原生预检、执行、日志、版本状态与回滚
/cmd/moonmigrate        MoonBit Native CLI 入口
/examples               可运行的迁移清单
/docs/MIGRATIONS.md     清单与安全语义
/native                 路径、SHA-256 和原生事务基础设施
```

项目采用 [MIT License](LICENSE)。生态差异见[选题与生态对比](docs/ECOSYSTEM.md)，工程细节见[架构说明](docs/ARCHITECTURE.md)。
