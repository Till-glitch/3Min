"""Windows-compatible, dependency-free training. No example data or model shipped.
Use only local real manually labelled sessions. Tests use artificial fixtures solely for QA.
"""
import argparse
import bisect
import hashlib
import json
import math
import random
from pathlib import Path

FEATURE_VERSION = "window-v1"
NAMES = ["acc_mean", "acc_std", "acc_change", "rot_mean", "rot_std", "rot_change",
         "hr_scaled", "hr_slope_scaled", "hr_missing", "hr_age_scaled", "coverage", "max_gap_scaled"]


def mean(values):
    return sum(values) / len(values) if values else 0.0


def std(values):
    m = mean(values)
    return math.sqrt(mean([(v - m) ** 2 for v in values]))


def features(motion, pulses, end):
    points = sorted((p for p in motion if end - 8 < p[0] <= end), key=lambda p: p[0])
    early = [p for p in points if p[0] <= end - 4]
    late = [p for p in points if p[0] > end - 4]
    a, r = [p[1] for p in points], [p[2] for p in points]
    recent = sorted((p for p in pulses if end - 30 <= p[0] <= end), key=lambda p: p[0])
    last = recent[-1] if recent else None
    age = max(0, end - last[0]) if last else 30
    fresh = last is not None and age <= 10
    hr = last[1] / 200 if fresh else 0
    slope = ((last[1] - recent[0][1]) / (last[0] - recent[0][0]) / 10
             if fresh and last[0] - recent[0][0] >= 1 else 0)
    gap = max(0, points[0][0] - (end - 8)) if points else 8
    for previous, current in zip(points, points[1:]):
        gap = max(gap, current[0] - previous[0])
    gap = max(gap, end - (points[-1][0] if points else end - 8))
    return [mean(a), std(a), mean([p[1] for p in late]) - mean([p[1] for p in early]),
            mean(r), std(r), mean([p[2] for p in late]) - mean([p[2] for p in early]),
            hr, slope, 0 if fresh else 1, min(age, 30) / 30,
            min(1, len(points) / 200), min(gap, 8) / 8]


def load_session(path):
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if not rows or rows[0].get("kind") != "session_start" or rows[0].get("schema") != 1:
        raise ValueError(f"{path.name}: expected schema-1 session_start")
    sid = rows[0]["session_id"]
    if any(r.get("session_id") != sid or r.get("seq") != i for i, r in enumerate(rows)):
        raise ValueError(f"{path.name}: inconsistent session ID or sequence")
    if any(not isinstance(r.get("t"), (int, float)) or not math.isfinite(r["t"]) or r["t"] < 0 for r in rows):
        raise ValueError(f"{path.name}: invalid time")
    if rows[-1].get("kind") != "session_end" or rows[-1].get("reason") != "user":
        raise ValueError(f"{path.name}: incomplete/interrupted/failed session; exclude from training")
    if rows[0].get("mode") != "learning":
        raise ValueError(f"{path.name}: installation probe is not labelled learning data")
    markers = [r for r in rows if r["kind"] in ("set_start", "set_end")]
    sets, opened = [], None
    for row in markers:
        if row.get("source") != "manual":
            raise ValueError(f"{path.name}: model predictions are not ground truth")
        if row["kind"] == "set_start":
            if opened is not None:
                raise ValueError(f"{path.name}: double start")
            opened = row
        else:
            if opened is None or row.get("set_number") != opened.get("set_number") or row["t"] <= opened["t"]:
                raise ValueError(f"{path.name}: unpaired set end")
            sets.append((opened["t"], row["t"]))
            opened = None
    if opened is not None:
        raise ValueError(f"{path.name}: unfinished set; do not invent its label")
    motion, pulses = [], []
    for row in rows:
        if row["kind"] == "motion":
            v = [row[k] for k in ("ax", "ay", "az", "rx", "ry", "rz")]
            if any(not isinstance(x, (int, float)) or not math.isfinite(x) for x in v):
                raise ValueError(f"{path.name}: invalid motion")
            received = row["received_t"]
            if not isinstance(received, (int, float)) or not math.isfinite(received) or received < row["t"] - 1:
                raise ValueError(f"{path.name}: invalid motion delivery time")
            motion.append((row["t"], math.sqrt(sum(x*x for x in v[:3])), math.sqrt(sum(x*x for x in v[3:])), received))
        if row["kind"] == "heart" and row.get("valid_time"):
            if not all(math.isfinite(row[k]) for k in ("sample_t", "bpm")) or row["bpm"] <= 0:
                raise ValueError(f"{path.name}: invalid heart sample")
            # Keep delivery time to avoid future information leaking into an earlier window.
            pulses.append((row["sample_t"], row["bpm"], row["t"]))
    return {"id": sid, "sets": sets, "motion": sorted(motion), "pulses": pulses,
            "duration": rows[-1]["t"], "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def windows(session):
    motion, result = session["motion"], []
    times = [p[0] for p in motion]
    for time in range(8, int(session["duration"]) + 1):
        lo, hi = bisect.bisect_right(times, time - 8), bisect.bisect_right(times, time)
        p = [(p[0], p[1]) for p in session["pulses"] if p[2] <= time]
        available_motion = [sample for sample in motion[lo:hi] if (sample[3] if len(sample) > 3 else sample[0]) <= time]
        f = features(available_motion, p, time)
        # Label the transition + its allowed delay, regardless of manual rest state.
        label = int(any(end <= time <= end + 12 for _, end in session["sets"]))
        result.append((float(time), f, label))
    return result


def split_sessions(sessions, seed=42):
    ids = [s["id"] for s in sorted(sessions, key=lambda s: s["id"])]
    if len(ids) != len(set(ids)):
        raise ValueError("Duplicate session IDs; copy files cannot create new independent sessions")
    if len(ids) < 6:
        raise ValueError("Lernmodus: mindestens 6 vollständige echte Trainingssitzungen erforderlich")
    random.Random(seed).shuffle(ids)
    n = max(1, len(ids) // 5)
    return {"test": ids[:n], "validation": ids[n:2*n], "train": ids[2*n:]}


def sigmoid(x):
    return 1 / (1 + math.exp(-max(-50, min(50, x))))


def fit(rows):
    if set(y for _, y in rows) != {0, 1}:
        raise ValueError("Both labelled classes are required in training")
    n = len(rows)
    means = [mean([f[j] for f, _ in rows]) for j in range(len(NAMES))]
    scales = [max(std([f[j] for f, _ in rows]), 1e-6) for j in range(len(NAMES))]
    x = [([(f[j] - means[j]) / scales[j] for j in range(len(NAMES))], y) for f, y in rows]
    counts = [sum(y == c for _, y in rows) for c in (0, 1)]
    weights, bias = [0.0] * len(NAMES), 0.0
    for _ in range(400):
        gradient, gb = [0.0] * len(NAMES), 0.0
        for f, y in x:
            residual = (sigmoid(bias + sum(a*b for a, b in zip(f, weights))) - y) * n / (2 * counts[y])
            gb += residual
            for j, value in enumerate(f):
                gradient[j] += residual * value
        for j in range(len(NAMES)):
            weights[j] -= 0.08 * (gradient[j] / n + 0.001 * weights[j])
        bias -= 0.08 * gb / n
    # Fold standardization into the trained coefficients, exactly matching watch inference.
    folded = [w / s for w, s in zip(weights, scales)]
    return {"weights": folded, "bias": bias - sum(w*m for w, m in zip(folded, means)),
            "means": means, "scales": scales}


def probability(model, f):
    return sigmoid(model["bias"] + sum(w*x for w, x in zip(model["weights"], f)))


def event_metrics(session, rows, score):
    detections, first_positive, last_time, armed, start_time = [], None, None, False, None
    starts = iter(start for start, _ in session["sets"])
    next_start = next(starts, None)
    for time, f, _ in rows:
        while next_start is not None and next_start <= time:
            armed, start_time, first_positive = True, next_start, None
            next_start = next(starts, None)
        p = score(f)
        eligible = armed and time - start_time >= 8 and f[10] >= 0.7 and p >= 0.8
        if not eligible:
            first_positive = None
        else:
            if last_time is not None and time - last_time > 1.5:
                first_positive = None
            if first_positive is None:
                first_positive = time
            if time - first_positive >= 2:
                detections.append(time)
                armed = False  # same one-timer-per-set policy as Watch; next start manually rearms
        last_time = time
    ends = [end for _, end in session["sets"]]
    used, delays, false = set(), [], 0
    for d in detections:
        candidates = [i for i, end in enumerate(ends) if i not in used and end <= d <= end + 12]
        if candidates:
            i = candidates[0]; used.add(i); delays.append(d - ends[i])
        else:
            false += 1
    return {"false_alarms": false, "missed_ends": len(ends) - len(used), "ends": len(ends),
            "delays_seconds": delays, "hours": session["duration"] / 3600}


def aggregate(metrics):
    delays = sorted(d for m in metrics for d in m["delays_seconds"])
    false = sum(m["false_alarms"] for m in metrics)
    hours = sum(m["hours"] for m in metrics)
    missed, ends = sum(m["missed_ends"] for m in metrics), sum(m["ends"] for m in metrics)
    return {"false_alarms": false, "false_alarms_per_hour": false / hours if hours else None,
            "missed_ends": missed, "total_ends": ends, "miss_rate": missed / ends if ends else None,
            "detected_ends": len(delays), "mean_delay_seconds": mean(delays) if delays else None,
            "p95_delay_seconds": delays[min(len(delays)-1, math.ceil(.95*len(delays))-1)] if delays else None}


def train(directory, output):
    paths = sorted(directory.glob("*.jsonl"))
    if not paths:
        raise ValueError("Lernmodus: keine echten Sitzungsdateien gefunden")
    sessions = [load_session(p) for p in paths]
    split = split_sessions(sessions)
    if sum(len(s["sets"]) for s in sessions) < 60:
        raise ValueError("Lernmodus: mindestens 60 manuell markierte Satzenden erforderlich")
    cache = {s["id"]: windows(s) for s in sessions}
    for partition, ids in split.items():
        selected = [s for s in sessions if s["id"] in ids]
        if sum(len(s["sets"]) for s in selected) < (30 if partition == "train" else 5):
            raise ValueError(f"{partition}: zu wenige Satzenden; weitere echte Sitzungen sammeln")
        if not {0, 1}.issubset({y for s in selected for _, _, y in cache[s['id']]}):
            raise ValueError(f"{partition}: beide Klassen erforderlich")
    train_rows = [(f, y) for sid in split["train"] for _, f, y in cache[sid] if f[10] >= .7]
    model = fit(train_rows)
    model.update({"feature_version": FEATURE_VERSION, "feature_names": NAMES, "threshold": .8,
                  "minimum_set_seconds": 8, "confirmation_seconds": 2, "minimum_coverage": .7,
                  "trained_on_real_data": True, "split": split,
                  "session_hashes": {s["id"]: s["sha256"] for s in sessions}, "algorithm": "balanced logistic regression L2"})
    report = {"split": split, "feature_version": FEATURE_VERSION, "sets": sum(len(s["sets"]) for s in sessions)}
    for partition in ("validation", "test"):
        selected = [s for s in sessions if s["id"] in split[partition]]
        report[partition] = {}
        for name, score in [("ml", lambda f: probability(model, f)),
                            ("baseline", lambda f: 1.0 if f[0] < .015 and f[3] < .15 else 0.0)]:
            report[partition][name] = aggregate([event_metrics(s, cache[s["id"]], score) for s in selected])
    report["automatic_approved"] = False  # always requires human review and hardware verification
    output.mkdir(parents=True, exist_ok=True)
    (output / "trained.json").write_text(json.dumps(model, indent=2), encoding="utf-8")
    (output / "metrics.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    parser.add_argument("--output", type=Path, default=Path("models/run"))
    args = parser.parse_args()
    try:
        train(args.data, args.output)
    except (ValueError, KeyError, OSError) as error:
        parser.exit(2, f"Kein Modell erzeugt: {error}\n")


if __name__ == "__main__":
    main()
