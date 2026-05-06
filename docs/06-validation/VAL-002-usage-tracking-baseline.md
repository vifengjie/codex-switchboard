# VAL-002 tokens 与订阅额度长期统计基线

文档编号：VAL-002  
文档状态：已确认  
负责人：fengjie  
最后更新：2026-05-03  
关联文档：REQ-001 / TECH-001 / VAL-001

## 1. 统计起点

长期统计从以下基线开始：

| 项目 | 值 |
|---|---|
| 本地时间 | 2026-05-03 11:30:07 CST |
| UTC 时间 | 2026-05-03T03:30:07.200Z |
| 项目路径 | `/Users/fengjie/Documents/CodeX/codex-switchboard` |
| 项目累计 tokens 基线 | 4,037,048 |
| 订阅计划记录值 | `team` |
| 5 小时窗口基线 | 34.0% |
| 周窗口基线 | 30.0% |
| 5 小时窗口重置时间 | 2026-05-03 15:28:46 CST |
| 周窗口重置时间 | 2026-05-05 14:15:35 CST |

基线文件为 `data/codex-usage-baseline.json`。后续所有增量统计都以该文件为准。

## 2. tokens 统计口径

项目 tokens 消耗使用本机 Codex 数据源统计：

| 数据 | 来源 |
|---|---|
| 项目线程列表 | `~/.codex/state_5.sqlite` 的 `threads` 表 |
| 项目过滤条件 | `cwd = /Users/fengjie/Documents/CodeX/codex-switchboard` |
| 当前线程累计 tokens | `threads.tokens_used` |
| 每轮 token 明细 | rollout JSONL 中的 `event_msg/token_count` |
| 每轮字段 | `last_token_usage` |
| 线程累计字段 | `total_token_usage` |

项目增量公式：

```text
项目增量 tokens = Σ max(0, 当前线程 tokens_used - 该线程基线 offset)
```

基线前已存在的线程写入 offset，避免把历史项目用量计入新周期。

## 3. 额度统计口径

订阅额度消耗不按纯 tokens 反推，而按 Codex 返回的额度遥测字段统计：

| 字段 | 含义 |
|---|---|
| `rate_limits.primary.used_percent` | 5 小时窗口已用百分比 |
| `rate_limits.primary.window_minutes` | 5 小时窗口长度，通常为 300 |
| `rate_limits.primary.resets_at` | 5 小时窗口重置时间 |
| `rate_limits.secondary.used_percent` | 周窗口已用百分比 |
| `rate_limits.secondary.window_minutes` | 周窗口长度，通常为 10080 |
| `rate_limits.secondary.resets_at` | 周窗口重置时间 |
| `rate_limits.rate_limit_reached_type` | 是否命中限额 |

同一个窗口内，不同线程的额度样本可能有延迟。展示当前状态时采用窗口内观测最高值，避免被较晚写入的旧百分比低估；同时保留最新原始样本用于排查。

满额 5 小时窗口只按严格条件认定：

```text
rate_limit_reached_type 非空
或 primary.used_percent >= 99.5%
```

低于该标准只记录为接近满额，不算一次满额。

## 4. 周可满额次数推算

核心推算公式：

```text
每满一次 5 小时额度的周额度成本 =
  Δsecondary_percent / Δprimary_percent * 100

预计一周可满额 5 小时次数 =
  floor(100 / 每满一次 5 小时额度的周额度成本)
```

严谨性要求：

| 样本状态 | 结论处理 |
|---|---|
| `primary` 变化低于 25 个百分点 | 只记录，不推算 |
| 覆盖不足 1 个明显窗口 | 可给低置信度区间 |
| 覆盖 2-3 个完整窗口 | 可给中置信度结论 |
| 出现多次满额触顶 | 可给高置信度结论 |

## 5. 运行方式

在项目根目录运行：

```bash
python3 tools/codex_usage_report.py
```

脚本会输出：

- 从基线开始的项目 tokens 增量。
- 当前 5 小时额度和周额度状态。
- 最近 token_count 记录。
- 5 小时窗口观察表。
- 一周可满额消耗几次 5 小时额度的推算状态。
