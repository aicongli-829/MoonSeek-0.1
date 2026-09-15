# FileNest 工程设计

## 数据流

1. MoonBit Native 解析并校验用户选择的根目录。
2. 扫描器记录普通文件的相对路径、大小、修改时间和 SHA-256；链接与保留目录不会进入计划。
3. 大小与摘要相同的候选文件再逐字节比较，形成确认过的重复组。
4. 确定性核心验证规则、父目录占用和重复选择，生成整理计划与统计摘要。
5. 浏览器或 CLI 展示同一份计划。只有带预览 ID 的已确认请求可以执行。
6. Native 事务层重新验证全部源文件，将它们移入本批次暂存区，再移至目标；每一步都同步更新日志。
7. 撤销先验证现有文件，再把目标重新暂存，最后恢复原路径。

## 包边界

根包 `filenest/core` 不访问文件系统、时钟或网络，负责分类、命名、自然排序、路径诊断、计划审计、报告、分析、快照、规则解析、配置校验和事务状态决策。

`filenest/core/native` 只支持 Native 目标，使用 `moonbitlang/async` 实现文件系统和 HTTP。它还包含独立 SHA-256、Windows FILETIME 换算、CLI、日志和两阶段文件移动。

`filenest/core/webui` 只支持 JS 目标。页面状态、规则数组、HTML 渲染、重复选择、预览、导出和历史操作都用 MoonBit 编写。`dom.mbt` 中的窄 FFI 只映射 DOM、Fetch、下载和确认框等浏览器原语。

## 不覆盖事务

```text
pending → staged → applying → done
done → undo-staging → undo-staged → restoring → restored
```

- 所有源先移到 `.filenest/stage/<batch>/<index>`，因此名称交换与循环移动不会互相覆盖。
- 每次移动使用 `@fs.rename(source, target, replace=false)`；目标存在时底层直接失败。
- 移动前后都核对大小、修改时间与 SHA-256。
- 日志写入唯一临时文件并同步，然后原子替换历史 JSON。
- 批次锁阻止同一根目录同时执行两个事务。

操作失败时不会继续后续步骤，已完成步骤及阶段保留在历史记录中，可执行撤销。日志提供进程崩溃后的人工审计依据；当前实现不宣称突然断电下的完整数据库级持久性。

## 本地 HTTP 边界

- 仅绑定 `127.0.0.1`。
- 固定白名单提供 HTML、CSS 和 MoonBit 编译产物。
- POST 请求校验精确 Host、同源 Origin、`Sec-Fetch-Site` 和启动时随机令牌。
- 请求体限制为 2 MiB，静态响应设置 CSP 和 `nosniff`。
- 浏览器只接收文件元数据、计划和日志；文件内容不会通过 HTTP 返回。

## 构建产物

仓库只跟踪 MoonBit、HTML、CSS、配置和文档。浏览器 JS 位于 `_build/js/release/build/webui/webui.js`，由 `moon build webui --target js --release` 生成并由 Native 服务读取。

## 验证层次

- 核心测试：排序性质、规则组合、命名边界、冲突、报告、精确大小、事务阶段、分析、快照和 `.fnrules`。
- Native 测试：SHA-256 标准向量、跨平台路径和 FILETIME 月份换算。
- 原生冒烟：真实临时文件扫描、重复确认、计划、三文件执行、日志和整批撤销。
- HTTP 冒烟：会话、首页和 MoonBit 编译脚本返回 200。
