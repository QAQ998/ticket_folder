#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path


def normalize(value):
    text = str(value or "").strip()
    text = re.sub(r"\s+", " ", text)
    text = text.replace("：", ":")
    text = re.sub(r"(\d{4})[/.年](\d{1,2})[/.月](\d{1,2})日?", lambda m: f"{m.group(1)}-{int(m.group(2)):02d}-{int(m.group(3)):02d}", text)
    text = re.sub(r"\b(\d{4})-(\d{1,2})-(\d{1,2})\b", lambda m: f"{m.group(1)}-{int(m.group(2)):02d}-{int(m.group(3)):02d}", text)
    text = text.replace("￥ ", "￥")
    text = text.replace("¥ ", "¥")
    return text


def load_predictions(path):
    raw = json.loads(Path(path).read_text(encoding="utf-8"))
    if isinstance(raw, dict) and "predictions" in raw:
        raw = raw["predictions"]
    if not isinstance(raw, list):
        raise ValueError("Prediction file must be a list or an object with a predictions list.")

    predictions = {}
    for item in raw:
        case_id = item.get("id")
        if not case_id:
            raise ValueError("Every prediction must include an id.")
        actual = item.get("actual") or item.get("fields") or item
        predictions[case_id] = actual
    return predictions


def boolean_value(value):
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in {"true", "1", "yes", "y"}
    return bool(value)


def main():
    if len(sys.argv) != 3:
        print("Usage: python3 tests/evaluate_ticket_recognition.py FIXTURES_JSON PREDICTIONS_JSON", file=sys.stderr)
        return 2

    fixtures = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    predictions = load_predictions(sys.argv[2])
    fields = fixtures["fields"]

    total = 0
    correct = 0
    field_totals = {field: 0 for field in fields}
    field_correct = {field: 0 for field in fields}
    review_total = 0
    review_correct = 0
    mismatches = []
    missing_cases = []

    for case in fixtures["cases"]:
        case_id = case["id"]
        expected = case["expected"]
        actual = predictions.get(case_id)
        if actual is None:
            missing_cases.append(case_id)
            continue

        for field in fields:
            total += 1
            field_totals[field] += 1
            expected_value = normalize(expected.get(field, ""))
            actual_value = normalize(actual.get(field, ""))
            if expected_value == actual_value:
                correct += 1
                field_correct[field] += 1
            else:
                mismatches.append((case_id, field, expected_value, actual_value))

        expected_review = case.get("assertions", {}).get("should_request_manual_review")
        if expected_review is not None and "should_request_manual_review" in actual:
            review_total += 1
            actual_review = boolean_value(actual.get("should_request_manual_review"))
            if actual_review == expected_review:
                review_correct += 1
            else:
                mismatches.append((case_id, "should_request_manual_review", str(expected_review), str(actual_review)))

    print(f"Cases: {len(fixtures['cases'])}")
    print(f"Evaluated cases: {len(fixtures['cases']) - len(missing_cases)}")
    print(f"Overall field accuracy: {correct}/{total} ({correct / total:.1%})" if total else "Overall field accuracy: n/a")
    print()
    print("Per-field accuracy:")
    for field in fields:
        total_for_field = field_totals[field]
        correct_for_field = field_correct[field]
        rate = correct_for_field / total_for_field if total_for_field else 0
        print(f"- {field}: {correct_for_field}/{total_for_field} ({rate:.1%})")

    if review_total:
        print()
        print(f"manual review decision accuracy: {review_correct}/{review_total} ({review_correct / review_total:.1%})")

    if missing_cases:
        print()
        print("Missing predictions:")
        for case_id in missing_cases:
            print(f"- {case_id}")

    if mismatches:
        print()
        print("Mismatches:")
        for case_id, field, expected_value, actual_value in mismatches:
            print(f"- {case_id}.{field}: expected={expected_value!r}, actual={actual_value!r}")
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
