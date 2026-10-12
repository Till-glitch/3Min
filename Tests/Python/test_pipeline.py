"""Artificial fixtures verify software only. They never become a shipped/trained model."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("pipeline", ROOT / "ml/pipeline.py")
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
spec2 = importlib.util.spec_from_file_location("package_ipa", ROOT / "scripts/package_ipa.py")
pack = importlib.util.module_from_spec(spec2)
spec2.loader.exec_module(pack)


def temporary():
    folder = (ROOT / "build" / "test-temp").resolve()
    if not folder.is_relative_to(ROOT.resolve()):
        raise ValueError("Test scratch folder must remain in the workspace")
    folder.mkdir(parents=True, exist_ok=True)
    return tempfile.TemporaryDirectory(dir=folder)


class PipelineTests(unittest.TestCase):
    def test_shared_feature_contract(self):
        motion = [(i/25, .1, .2) for i in range(1, 201)]
        f = p.features(motion, [], 8)
        self.assertEqual(len(f), 12)
        self.assertAlmostEqual(f[0], .1)
        self.assertAlmostEqual(f[1], 0)
        self.assertEqual(f[6], 0)
        self.assertEqual(f[8], 1)
        self.assertEqual(f[10], 1)
        self.assertAlmostEqual(f[11], .005)
        stale = p.features([], [(0, 100)], 11)
        self.assertEqual(stale[6], 0)
        self.assertEqual(stale[8], 1)
        self.assertEqual(stale[11], 1)

    def test_heart_delivery_cannot_leak(self):
        session = {"motion": [], "pulses": [(5, 100, 10)], "sets": [], "duration": 11}
        w = p.windows(session)
        self.assertEqual(w[0][1][8], 1)  # time 8: sample not delivered yet
        self.assertEqual(w[2][1][8], 0)  # time 10: actually available

    def test_motion_delivery_cannot_leak(self):
        session = {"motion": [(7, .1, .2, 10)], "pulses": [], "sets": [], "duration": 11}
        w = p.windows(session)
        self.assertEqual(w[0][1][10], 0)
        self.assertEqual(w[2][1][10], 1/200)

    def test_logistic_optimizer_learns_in_memory_only(self):
        rows = []
        for value, label in [(-2, 0), (-1, 0), (1, 1), (2, 1)]:
            f = [0.0] * 12; f[0] = value
            rows.append((f, label))
        model = p.fit(rows)  # numerical QA only, no model artifact written or shipped
        self.assertLess(p.probability(model, rows[0][0]), .1)
        self.assertGreater(p.probability(model, rows[-1][0]), .9)

    def test_session_split_disjoint_and_deterministic(self):
        sessions = [{"id": str(i)} for i in range(10)]
        split = p.split_sessions(sessions)
        self.assertEqual(split, p.split_sessions(list(reversed(sessions))))
        self.assertEqual(len(set(sum(split.values(), []))), 10)
        for a, b in [("train", "test"), ("train", "validation"), ("validation", "test")]:
            self.assertFalse(set(split[a]) & set(split[b]))
        with self.assertRaises(ValueError):
            p.split_sessions(sessions[:2])
        with self.assertRaises(ValueError):
            p.split_sessions(sessions + [sessions[0]])

    def test_event_false_alarm_causes_missed_end(self):
        session = {"sets": [(0, 30)], "duration": 60}
        f = [0.0] * 12; f[10] = 1
        rows = [(t, f, 0) for t in range(8, 50)]
        metrics = p.event_metrics(session, rows, lambda _: 1)
        self.assertEqual(metrics["false_alarms"], 1)
        self.assertEqual(metrics["missed_ends"], 1)
        metrics = p.event_metrics(session, rows, lambda _: 0)
        self.assertEqual(metrics["missed_ends"], 1)
        self.assertIsNone(p.aggregate([metrics])["mean_delay_seconds"])

    def test_event_confirmation_and_delay(self):
        session = {"sets": [(0, 30)], "duration": 60}
        rows = []
        for t in range(8, 50):
            f = [0.0] * 12; f[10] = 1; f[0] = int(t >= 30)
            rows.append((t, f, int(t >= 30)))
        metrics = p.event_metrics(session, rows, lambda f: f[0])
        self.assertEqual(metrics["delays_seconds"], [2])
        self.assertEqual(metrics["false_alarms"], 0)
        self.assertEqual(metrics["missed_ends"], 0)

    def test_no_data_does_not_produce_model(self):
        with temporary() as d:
            root = Path(d)
            with self.assertRaises(ValueError):
                p.train(root, root / "model")
            self.assertFalse((root / "model").exists())

    def test_incomplete_and_automatic_labels_rejected(self):
        rows = [{"kind": "session_start", "schema": 1, "session_id": "abc", "seq": 0, "t": 0, "mode": "learning"},
                {"kind": "set_start", "source": "manual", "set_number": 1, "session_id": "abc", "seq": 1, "t": 1},
                {"kind": "set_end", "source": "model", "set_number": 1, "session_id": "abc", "seq": 2, "t": 30},
                {"kind": "session_end", "reason": "user", "session_id": "abc", "seq": 3, "t": 60}]
        with temporary() as d:
            file = Path(d) / "session.jsonl"
            file.write_text("\n".join(json.dumps(r) for r in rows), encoding="utf-8")
            with self.assertRaises(ValueError):
                p.load_session(file)
            rows[2]["source"] = "manual"
            file.write_text("\n".join(json.dumps(r) for r in rows), encoding="utf-8")
            self.assertEqual(p.load_session(file)["sets"], [(1, 30)])
            rows[-1]["reason"] = "interrupted"
            file.write_text("\n".join(json.dumps(r) for r in rows), encoding="utf-8")
            with self.assertRaises(ValueError):
                p.load_session(file)

    def test_package_requires_watch_and_matching_companion(self):
        import plistlib
        with temporary() as d:
            app = Path(d) / "Phone.app"; app.mkdir()
            pi = {"CFBundleIdentifier": "de.test", "CFBundleExecutable": "Phone", "MinimumOSVersion": "17.0"}
            (app / "Info.plist").write_bytes(plistlib.dumps(pi)); (app / "Phone").write_bytes(b"fixture")
            with self.assertRaises(ValueError):
                pack.inspect(app)
            watch = app / "Watch" / "Watch.app"; watch.mkdir(parents=True)
            wi = {"CFBundleIdentifier": "de.test.watchkitapp", "CFBundleExecutable": "Watch", "WKApplication": True,
                  "WKCompanionAppBundleIdentifier": "de.test", "CFBundleSupportedPlatforms": ["WatchOS"]}
            (watch / "Info.plist").write_bytes(plistlib.dumps(wi)); (watch / "Watch").write_bytes(b"fixture")
            self.assertFalse(pack.inspect(app)["watch_installation_verified"])
            wi["WKCompanionAppBundleIdentifier"] = "wrong"
            (watch / "Info.plist").write_bytes(plistlib.dumps(wi))
            with self.assertRaises(ValueError):
                pack.inspect(app)


if __name__ == "__main__":
    unittest.main()
