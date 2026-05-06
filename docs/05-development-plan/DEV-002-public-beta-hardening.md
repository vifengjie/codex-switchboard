# DEV-002 Public Beta Hardening

文档编号：DEV-002  
文档状态：草案  
最后更新：2026-05-06  
关联文档：DEV-001、TECH-001

## 1. 目标

为首个公开 Beta 发布补齐安装、文档、回归和问题定位能力。

## 2. 当前基线

截至 `main`：

- `M1` 到 `M5` 主体功能已落地
- 管理窗口支持账号管理、切换、明细筛选、CSV/JSON 导出、审计筛选、清理、诊断导出
- 自动化测试通过

## 3. Beta 发布前任务

- 验证本机首次启动、退出、二次启动、卸载路径
- 验证菜单栏刷新、通知、切换、导出、清理、诊断导出关键路径
- 已补 `.app` 本地打包说明与脚本，见 `REL-001`、`tools/build_beta_app.sh`
- 已补 Beta release notes，见 `docs/BETA-RELEASE-NOTES.md`
- 已补最小 bug issue 模板，见 `.github/ISSUE_TEMPLATE/bug_report.md`
- 待补 `.dmg` / notarization 流程

## 4. 已知限制

- 不支持后台静默自动轮换账号
- 不读取、替换或导出 Codex 内部 auth 文件
- 切换后校验仍依赖官方流程完成和本地观察到的新快照
- 诊断导出目前是脱敏 JSON 摘要，不包含完整错误堆栈

## 5. 出口标准

- GitHub 用户可按 README 本地构建并启动
- 文档明确边界、隐私和安全限制
- Beta 试用者可在出现问题时导出脱敏诊断信息
