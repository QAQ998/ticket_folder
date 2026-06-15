# Ticket Recognition Test Fixtures

This folder contains a small synthetic regression set for validating ticket recognition changes.

## Files

- `fixtures/ticket_recognition_cases.json`: OCR text samples, expected extracted fields, and scenario tags.
- `evaluate_ticket_recognition.py`: compares prediction JSON against the fixture expectations.

## Coverage

The current set covers 21 intentionally difficult synthetic OCR cases:

- mobile ticket screenshots
- Traditional Chinese text
- English labels and bilingual titles
- noisy OCR that needs title/price correction
- duplicate two-column paper stubs
- movie format suffix removal
- cinema lines that appear before the title
- date without time
- missing optional fields
- sparse OCR that should trigger manual review
- order number, pickup code, and phone-tail noise
- selling time vs show time
- multiple amounts such as ticket price, service fee, and actual paid
- split label/value lines
- shuffled OCR line order from rotated photos
- table headers merged with values
- same-screen movie recommendations

## Prediction Format

Create a prediction file with this shape:

```json
[
  {
    "id": "maoyan_zongheng_verified_rules",
    "actual": {
      "movie_title": "哪吒之魔童闹海",
      "watched_at": "2025-02-01 19:35",
      "cinema": "广东省深圳市纵横西丽店",
      "hall": "10号激光厅",
      "seat": "9排6座",
      "ticket_price": "50.00",
      "should_request_manual_review": false
    }
  }
]
```

Then run:

```bash
python3 tests/evaluate_ticket_recognition.py tests/fixtures/ticket_recognition_cases.json path/to/predictions.json
```

The evaluator normalizes whitespace and common date separators, then prints per-field accuracy and mismatches.
If `should_request_manual_review` is present in predictions, it also checks manual-review decision accuracy.
