"""Local hardware QA report. Never used by the cloud build."""
import argparse
import json
import math
from pathlib import Path


def summarize(path):
    rows = [json.loads(s) for s in path.read_text(encoding="utf-8").splitlines() if s.strip()]
    motion = sorted(r["t"] for r in rows if r["kind"] == "motion")
    intervals = [b-a for a, b in zip(motion, motion[1:])]
    statuses = [r for r in rows if r["kind"] == "status"]
    checks = []
    starts = {r["set_number"]: r for r in rows if r["kind"] == "rest_start"}
    for row in rows:
        if row["kind"] == "rest_finished" and row["set_number"] in starts:
            start = starts[row["set_number"]]
            checks.append({"set": row["set_number"], "deadline_duration": start["deadline_t"] - start["t"],
                           "callback_lateness_seconds": row["t"] - start["deadline_t"]})
    return {"session": rows[0]["session_id"], "duration_seconds": rows[-1]["t"],
            "motion_samples": len(motion), "max_motion_gap_seconds": max(intervals, default=None),
            "observed_motion_hz": (len(motion)-1)/(motion[-1]-motion[0]) if len(motion) > 1 and motion[-1] > motion[0] else None,
            "gaps_over_1_second": sum(g > 1 for g in intervals),
            "heart_samples": sum(r["kind"] == "heart" for r in rows),
            "invalid_heart_time_samples": sum(r["kind"] == "heart" and not r.get("valid_time") for r in rows),
            "status_heart_fresh_fraction": sum(bool(r.get("heart_fresh")) for r in statuses)/len(statuses) if statuses else None,
            "rest_checks": checks,
            "rest_haptic_requests": sum(r["kind"] == "haptic_requested" for r in rows),
            "scenes": [{"t": r["t"], "value": r["value"]} for r in rows if r["kind"] == "scene"],
            "end_reason": rows[-1].get("reason"), "hardware_haptic_felt": "must be recorded by user"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("session", type=Path)
    args = parser.parse_args()
    print(json.dumps(summarize(args.session), indent=2))
