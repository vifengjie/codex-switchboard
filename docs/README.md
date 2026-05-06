# Codex Switchboard 文档索引

本文档库用于沉淀 Codex 多账号配额管理产品的背景、需求、设计、技术方案、开发拆解和验证记录。后续所有产品与研发文档都应放在 `docs/` 下，并按文档编号引用。

## 文档地图

| 阶段 | 目录 | 当前文档 | 用途 |
|---|---|---|---|
| 文档治理 | `00-governance/` | [DOC-001-document-system-and-naming.md](00-governance/DOC-001-document-system-and-naming.md) | 目录、命名、编号、引用规则 |
| 产品背景 | `01-background/` | [BKG-001-product-background.md](01-background/BKG-001-product-background.md) | 业务背景、用户问题、合规边界 |
| 需求分析 | `02-requirements/` | [REQ-001-codex-multi-account-quota-management.md](02-requirements/REQ-001-codex-multi-account-quota-management.md) | 已确认需求、功能范围、验收标准 |
| 产品设计 | `03-product-design/` | [PRD-001-product-design-overview.md](03-product-design/PRD-001-product-design-overview.md) | 信息架构、交互、页面与状态设计 |
| 技术方案 | `04-technical-solution/` | [TECH-001-architecture-and-implementation-options.md](04-technical-solution/TECH-001-architecture-and-implementation-options.md) | 架构、数据、采集、切换、安全方案 |
| 开发计划 | `05-development-plan/` | [DEV-001-mvp-task-breakdown.md](05-development-plan/DEV-001-mvp-task-breakdown.md) | MVP 任务拆解、里程碑、验收闭环 |
| 验证研究 | `06-validation/` | [VAL-001-poc-validation-plan.md](06-validation/VAL-001-poc-validation-plan.md), [VAL-002-usage-tracking-baseline.md](06-validation/VAL-002-usage-tracking-baseline.md) | PoC、待验证问题、实测记录、用量基线 |
| 发布交付 | `07-release/` | [REL-001-local-build-and-beta-packaging.md](07-release/REL-001-local-build-and-beta-packaging.md) | 本地构建、Beta 打包、反馈入口 |
| 资料资产 | `90-assets/` | [README.md](90-assets/README.md) | Mermaid、图片、截图、原型素材 |

## 引用规则

- 引用需求时使用 `REQ-001`。
- 引用产品设计时使用 `PRD-001`。
- 引用技术方案时使用 `TECH-001`。
- 引用开发拆解时使用 `DEV-001`。
- 引用验证计划时使用 `VAL-001`。
- 引用发布说明时使用 `REL-001`。

示例：

```text
本功能来源：REQ-001 / P0-6
交互设计参考：PRD-001 / 3. 菜单栏状态设计
技术实现参考：TECH-001 / 4. 配额采集方案
开发任务参考：DEV-001 / T-003
```

## 当前主线

当前产品主线是：为 Codex 客户端用户提供多账号额度监控、低额度提醒、手动切换账号、切换后刷新额度和 token / credits 用量统计。
