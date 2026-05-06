# REL-001 本地构建与 Beta 打包说明

文档编号：REL-001  
文档状态：草案  
最后更新：2026-05-06  
关联文档：DEV-002、TECH-001、README

## 1. 目标

为首个公开 Beta 提供最小可执行的本地构建、启动、验证和打包说明。

## 2. 当前交付形态

当前仓库交付形态为源码仓库，主要支持：

- 本地 `swift build`
- 本地 `swift test`
- 本地 `swift run CodexQuotaManager`
- 使用仓库脚本生成本地 `.app`
- 开发者自行在 Xcode 中归档 `.app`

当前不包含：

- notarized `.dmg`
- 自动更新
- 后台静默安装器

## 3. 构建前提

- macOS
- Swift 6.1 或更新版本
- 推荐使用完整 Xcode 以便归档菜单栏应用

## 4. 本地验证步骤

```bash
swift build
swift test
swift run CodexQuotaManager
./tools/build_beta_app.sh
```

建议至少验证以下路径：

1. 首次启动后菜单栏状态项可见
2. 管理窗口可打开
3. `账号` 页可新增、编辑、切换账号
4. `明细` 页可筛选并导出 CSV / JSON
5. `审计` 页可筛选事件
6. `策略` 页可执行清理和诊断导出

## 5. 仓库脚本打包

仓库内提供最小 Beta 打包脚本：

```bash
./tools/build_beta_app.sh
```

脚本会：

1. 生成 release 可执行文件
2. 在 `.build/beta-release/` 下组装 `.app`
3. 写入最小 `Info.plist`

当前输出路径：

```text
.build/beta-release/Codex Quota Manager.app
```

## 6. Xcode 打包建议

当前阶段建议使用 Xcode 本地归档：

1. 用 Xcode 打开 `Package.swift`
2. 选择 `CodexQuotaManager` 可执行目标
3. 选择 `Product > Archive`
4. 导出本地 `.app`

注意：

- 当前重点是 Beta 试用，不承诺完成 notarization
- 打包前应再次运行 `swift test`
- 发布给试用者前应确认 `README`、`PRIVACY`、`SECURITY`、`BETA-RELEASE-NOTES` 已同步

## 7. 反馈与回收

Beta 试用阶段建议要求使用者附带：

- 应用版本或 commit SHA
- macOS 版本
- 问题发生路径
- 导出的脱敏诊断信息

GitHub issue 模板见：

- `.github/ISSUE_TEMPLATE/bug_report.md`

## 8. 后续完善项

- 明确 `.app` 导出截图说明
- 增加 notarization 与 `.dmg` 产物流程
- 增加 Beta 回归清单
