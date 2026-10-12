"""Run locally on a Mac (or Linux for conversion only), not in the build workflow.
Windows training outputs weights; Apple's supported Core ML Tools platforms exclude Windows.
"""
import argparse
import json
import math
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("trained", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--reviewed", action="store_true", help="Confirm real data and independently reviewed validation/test metrics")
    args = parser.parse_args()
    data = json.loads(args.trained.read_text(encoding="utf-8"))
    if data.get("trained_on_real_data") is not True or data.get("feature_version") != "window-v1":
        parser.error("Requires validated training output, not a placeholder")
    if not args.reviewed:
        parser.error("Review metrics and real data provenance first; then pass --reviewed")
    report = json.loads(args.trained.with_name("metrics.json").read_text(encoding="utf-8"))
    if report.get("split") != data.get("split"):
        parser.error("Metrics do not match the training split")
    for partition in ("validation", "test"):
        metrics = report[partition]["ml"]
        if (metrics["total_ends"] < 5 or metrics["false_alarms_per_hour"] > .5 or
                metrics["miss_rate"] > .1 or metrics["p95_delay_seconds"] is None or metrics["p95_delay_seconds"] > 8):
            parser.error(f"{partition}: initial acceptance criteria failed; remain in learning mode")
    import numpy as np
    import coremltools as ct
    from coremltools.models import datatypes
    from coremltools.models.neural_network import NeuralNetworkBuilder
    weights, bias = np.asarray(data["weights"], dtype=np.float32), float(data["bias"])
    if len(weights) != 12 or not np.isfinite(weights).all() or not math.isfinite(bias):
        parser.error("Invalid learned coefficients")
    builder = NeuralNetworkBuilder([("features", datatypes.Array(12))], [("probability", datatypes.Array(1))])
    builder.add_inner_product("learned_linear", weights.reshape(1, 12), np.asarray([bias], dtype=np.float32),
                              12, 1, True, "features", "logit")
    builder.add_activation("learned_probability", "SIGMOID", "logit", "probability")
    model = ct.models.MLModel(builder.spec)
    model.user_defined_metadata["feature_version"] = "window-v1"
    model.user_defined_metadata["algorithm"] = data["algorithm"]
    model.user_defined_metadata["training_sessions"] = str(len(data["split"]["train"]))
    model.user_defined_metadata["evaluation_passed"] = "true"
    model.short_description = "Satzende aus echten manuell markierten Sitzungen. Experimentell; Hardwareprüfung erforderlich."
    # Core ML runtime parity can only run on macOS. Use fixed feature vectors, not invented training data.
    import sys
    if sys.platform == "darwin":
        for values in [np.zeros(12), np.ones(12), np.arange(12) / 12]:
            z = bias + sum(float(w)*float(v) for w, v in zip(weights, values))
            expected = 1 / (1 + math.exp(-max(-50, min(50, z))))
            actual = float(model.predict({"features": values})["probability"].reshape(-1)[0])
            if abs(actual - expected) > 1e-4:
                raise ValueError("Core ML parity failure")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    model.save(str(args.output))
    print(f"Converted trained model: {args.output}; automatic mode still requires device approval")


if __name__ == "__main__":
    main()
