#!/usr/bin/env python3
"""Report Codex token usage and subscription quota movement from a baseline."""

from __future__ import annotations

import argparse
import json
import math
import sqlite3
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BASELINE = REPO_ROOT / "data" / "codex-usage-baseline.json"
DEFAULT_DB = Path.home() / ".codex" / "state_5.sqlite"


@dataclass(frozen=True)
class ThreadRow:
    thread_id: str
    created_at: int
    updated_at: int
    title: str
    model: str
    reasoning_effort: str
    tokens_used: int
    rollout_path: str


def parse_iso_z(value: str) -> datetime:
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    return datetime.fromisoformat(value).astimezone(timezone.utc)


def fmt_ts(seconds: int | None) -> str:
    if not seconds:
        return "-"
    return datetime.fromtimestamp(seconds).astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")


def fmt_dt(value: datetime | None) -> str:
    if value is None:
        return "-"
    return value.astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")


def pct(value: Any) -> str:
    if value is None:
        return "-"
    return f"{float(value):.1f}%"


def load_baseline(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def load_threads(db_path: Path, cwd: str) -> list[ThreadRow]:
    sql = """
        select id, created_at, updated_at, title, coalesce(model, ''),
               coalesce(reasoning_effort, ''), tokens_used, rollout_path
        from threads
        where cwd = ?
        order by updated_at desc, id desc
    """
    with sqlite3.connect(db_path) as conn:
        rows = conn.execute(sql, (cwd,)).fetchall()
    return [
        ThreadRow(
            thread_id=row[0],
            created_at=int(row[1] or 0),
            updated_at=int(row[2] or 0),
            title=row[3] or "",
            model=row[4] or "",
            reasoning_effort=row[5] or "",
            tokens_used=int(row[6] or 0),
            rollout_path=row[7] or "",
        )
        for row in rows
    ]


def iter_token_events(threads: list[ThreadRow]) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    thread_by_path = {thread.rollout_path: thread for thread in threads if thread.rollout_path}
    for rollout_path, thread in thread_by_path.items():
        path = Path(rollout_path)
        if not path.exists():
            continue
        with path.open("r", encoding="utf-8") as handle:
            for line in handle:
                try:
                    item = json.loads(line)
                except json.JSONDecodeError:
                    continue
                payload = item.get("payload") or {}
                if item.get("type") != "event_msg" or payload.get("type") != "token_count":
                    continue
                timestamp_raw = item.get("timestamp")
                if not timestamp_raw:
                    continue
                info = payload.get("info") or {}
                rate_limits = payload.get("rate_limits") or {}
                events.append(
                    {
                        "timestamp": parse_iso_z(timestamp_raw),
                        "thread_id": thread.thread_id,
                        "title": thread.title,
                        "model": thread.model,
                        "reasoning_effort": thread.reasoning_effort,
                        "total_usage": info.get("total_token_usage") or {},
                        "last_usage": info.get("last_token_usage") or {},
                        "rate_limits": rate_limits,
                    }
                )
    events.sort(key=lambda item: item["timestamp"])
    return events


def thread_deltas(threads: list[ThreadRow], baseline: dict[str, Any]) -> tuple[list[dict[str, Any]], int]:
    offsets = {
        item["thread_id"]: int(item.get("tokens_used_at_baseline") or 0)
        for item in baseline.get("thread_token_offsets", [])
    }
    baseline_at = parse_iso_z(baseline["baseline_captured_at_utc"]).timestamp()
    rows: list[dict[str, Any]] = []
    total_delta = 0
    for thread in threads:
        if thread.thread_id in offsets:
            offset = offsets[thread.thread_id]
        elif thread.created_at >= baseline_at:
            offset = 0
        else:
            offset = thread.tokens_used
        delta = max(0, thread.tokens_used - offset)
        total_delta += delta
        rows.append(
            {
                "thread": thread,
                "offset": offset,
                "delta": delta,
            }
        )
    return rows, total_delta


def latest_rate_sample(events: list[dict[str, Any]]) -> dict[str, Any] | None:
    for event in reversed(events):
        if event.get("rate_limits"):
            return event
    return None


def rate_window_summary(events: list[dict[str, Any]], baseline_at: datetime) -> list[dict[str, Any]]:
    groups: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for event in events:
        if event["timestamp"] < baseline_at:
            continue
        primary = (event.get("rate_limits") or {}).get("primary") or {}
        reset_at = primary.get("resets_at")
        if reset_at is not None:
            groups[int(reset_at)].append(event)

    windows: list[dict[str, Any]] = []
    for reset_at, items in sorted(groups.items()):
        primary_values = [
            float(((event.get("rate_limits") or {}).get("primary") or {}).get("used_percent"))
            for event in items
            if ((event.get("rate_limits") or {}).get("primary") or {}).get("used_percent") is not None
        ]
        secondary_values = [
            float(((event.get("rate_limits") or {}).get("secondary") or {}).get("used_percent"))
            for event in items
            if ((event.get("rate_limits") or {}).get("secondary") or {}).get("used_percent") is not None
        ]
        if not primary_values:
            continue
        reached = any((event.get("rate_limits") or {}).get("rate_limit_reached_type") for event in items)
        windows.append(
            {
                "reset_at": reset_at,
                "start": items[0]["timestamp"],
                "end": items[-1]["timestamp"],
                "primary_start": primary_values[0],
                "primary_max": max(primary_values),
                "primary_delta": max(primary_values) - primary_values[0],
                "secondary_start": secondary_values[0] if secondary_values else None,
                "secondary_max": max(secondary_values) if secondary_values else None,
                "secondary_delta": (
                    max(secondary_values) - secondary_values[0] if secondary_values else 0.0
                ),
                "full_hit": reached or max(primary_values) >= 99.5,
            }
        )
    return windows


def forecast(windows: list[dict[str, Any]]) -> dict[str, Any]:
    min_primary_delta_for_projection = 25.0
    useful = [window for window in windows if window["primary_delta"] > 0]
    primary_delta = sum(window["primary_delta"] for window in useful)
    secondary_delta = sum(window["secondary_delta"] for window in useful)
    full_hits = sum(1 for window in windows if window["full_hit"])

    if (
        primary_delta < min_primary_delta_for_projection
        or secondary_delta <= 0
    ):
        return {
            "status": "样本不足",
            "full_hits": full_hits,
            "primary_delta": primary_delta,
            "secondary_delta": secondary_delta,
            "min_primary_delta_for_projection": min_primary_delta_for_projection,
        }

    secondary_per_full_primary = secondary_delta / primary_delta * 100.0
    weekly_full_windows = math.floor(100.0 / secondary_per_full_primary)
    if primary_delta < 50 or len(useful) < 2:
        confidence = "低"
    elif full_hits >= 2 or primary_delta >= 200:
        confidence = "高"
    else:
        confidence = "中"
    return {
        "status": "可推算",
        "full_hits": full_hits,
        "primary_delta": primary_delta,
        "secondary_delta": secondary_delta,
        "secondary_per_full_primary": secondary_per_full_primary,
        "weekly_full_windows": weekly_full_windows,
        "confidence": confidence,
    }


def usage_records(events: list[dict[str, Any]], baseline_at: datetime) -> list[dict[str, Any]]:
    records = []
    for event in events:
        if event["timestamp"] <= baseline_at:
            continue
        last_usage = event.get("last_usage") or {}
        if not last_usage:
            continue
        records.append(event)
    return records


def render_markdown(
    baseline: dict[str, Any],
    threads: list[ThreadRow],
    events: list[dict[str, Any]],
) -> str:
    baseline_at = parse_iso_z(baseline["baseline_captured_at_utc"])
    deltas, total_delta = thread_deltas(threads, baseline)
    records = usage_records(events, baseline_at)
    windows = rate_window_summary(events, baseline_at)
    projection = forecast(windows)
    latest = latest_rate_sample(events)
    current_total = sum(thread.tokens_used for thread in threads)

    lines: list[str] = []
    lines.append("# Codex Usage Report")
    lines.append("")
    lines.append(f"- Project: `{baseline['project_cwd']}`")
    lines.append(f"- Baseline: {baseline['baseline_captured_at_local']}")
    lines.append(f"- Baseline project tokens: {baseline['project_total_tokens_at_baseline']:,}")
    lines.append(f"- Current project tokens: {current_total:,}")
    lines.append(f"- Project tokens since baseline: {total_delta:,}")
    lines.append("")

    if latest:
        rate = latest["rate_limits"]
        primary = rate.get("primary") or {}
        secondary = rate.get("secondary") or {}
        current_window = windows[-1] if windows else None
        primary_observed = (
            current_window["primary_max"] if current_window else primary.get("used_percent")
        )
        secondary_observed = (
            current_window["secondary_max"] if current_window else secondary.get("used_percent")
        )
        primary_reset_at = (
            current_window["reset_at"] if current_window else primary.get("resets_at")
        )
        lines.append("## Current Quota")
        lines.append("")
        lines.append(f"- Latest sample: {fmt_dt(latest['timestamp'])}")
        lines.append(f"- Plan type: `{rate.get('plan_type') or '-'}`")
        lines.append(
            f"- 5h window observed max: {pct(primary_observed)}, "
            f"resets at {fmt_ts(primary_reset_at)}"
        )
        lines.append(
            f"- Weekly window observed max: {pct(secondary_observed)}, "
            f"resets at {fmt_ts(secondary.get('resets_at'))}"
        )
        lines.append(
            f"- Latest raw sample: 5h {pct(primary.get('used_percent'))}, "
            f"weekly {pct(secondary.get('used_percent'))}"
        )
        lines.append("")

    lines.append("## Tokens By Thread")
    lines.append("")
    lines.append("| Thread | Model | Current | Baseline offset | Delta |")
    lines.append("|---|---:|---:|---:|---:|")
    for row in sorted(deltas, key=lambda item: item["delta"], reverse=True):
        thread = row["thread"]
        lines.append(
            f"| {thread.title or thread.thread_id} | "
            f"{thread.model}/{thread.reasoning_effort} | "
            f"{thread.tokens_used:,} | {row['offset']:,} | {row['delta']:,} |"
        )
    lines.append("")

    lines.append("## Recent Token Records")
    lines.append("")
    if not records:
        lines.append("No post-baseline token records yet.")
    else:
        lines.append("| Time | Thread | Last tokens | Input | Cached input | Output | Reasoning |")
        lines.append("|---|---|---:|---:|---:|---:|---:|")
        for event in records[-20:]:
            usage = event["last_usage"]
            lines.append(
                f"| {fmt_dt(event['timestamp'])} | {event['title']} | "
                f"{int(usage.get('total_tokens') or 0):,} | "
                f"{int(usage.get('input_tokens') or 0):,} | "
                f"{int(usage.get('cached_input_tokens') or 0):,} | "
                f"{int(usage.get('output_tokens') or 0):,} | "
                f"{int(usage.get('reasoning_output_tokens') or 0):,} |"
            )
    lines.append("")

    lines.append("## 5h Window Forecast")
    lines.append("")
    lines.append("| Reset time | Samples | Primary start | Primary max | Secondary start | Secondary max | Full hit |")
    lines.append("|---|---:|---:|---:|---:|---:|---:|")
    if not windows:
        lines.append("| - | 0 | - | - | - | - | - |")
    else:
        for window in windows:
            sample_count = len(
                [
                    event
                    for event in events
                    if ((event.get("rate_limits") or {}).get("primary") or {}).get("resets_at")
                    == window["reset_at"]
                    and event["timestamp"] >= baseline_at
                ]
            )
            lines.append(
                f"| {fmt_ts(window['reset_at'])} | {sample_count} | "
                f"{window['primary_start']:.1f}% | {window['primary_max']:.1f}% | "
                f"{pct(window['secondary_start'])} | {pct(window['secondary_max'])} | "
                f"{'yes' if window['full_hit'] else 'no'} |"
            )
    lines.append("")

    if projection["status"] == "可推算":
        lines.append(
            "- Projection: "
            f"weekly full 5h windows ~= {projection['weekly_full_windows']} "
            f"(confidence: {projection['confidence']}; "
            f"secondary cost per full 5h window ~= {projection['secondary_per_full_primary']:.2f}%)."
        )
    else:
        lines.append(
            "- Projection: 样本不足。需要看到至少一个明显变化的 5 小时窗口，"
            "更严谨的判断最好覆盖 2-3 个完整窗口。"
        )
    lines.append(
        f"- Observed full 5h hits since baseline: {projection['full_hits']}"
    )
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, default=DEFAULT_BASELINE)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    args = parser.parse_args()

    baseline = load_baseline(args.baseline)
    threads = load_threads(args.db, baseline["project_cwd"])
    events = iter_token_events(threads)
    print(render_markdown(baseline, threads, events))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
