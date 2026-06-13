# Chennai Bus Crowding — ML Prediction Pipeline

## Files in this folder

| File | What it does |
|------|-------------|
| `seed_data.csv` | 300+ handcrafted training rows based on Chennai commute knowledge |
| `train_model.py` | Trains RandomForest, exports model.pkl + model_rules.json |
| `retrain_with_real_data.py` | Pulls real Supabase reports, merges with seed, retrains |
| `model_rules.json` | Generated lookup table — embed this in Flutter |
| `prediction_service.dart` | Flutter service that reads model_rules.json |

---

## How to run for the first time

```bash
# 1. Install dependencies
pip install scikit-learn pandas numpy joblib

# 2. Train the model
python train_model.py

# 3. Copy output to Flutter
cp model_rules.json ../assets/data/model_rules.json
```

Add to pubspec.yaml:
```yaml
flutter:
  assets:
    - assets/data/model_rules.json
```

---

## How to use in Flutter

In `main.dart`, after Supabase init:
```dart
await PredictionService.instance.init();
```

In your feed screen, when no live reports exist:
```dart
final pred = PredictionService.instance.predict(
  route: '19',
  direction: 'DOWN',
);

if (pred != null) {
  // Show: "Usually packed during morning peak (85% confident)"
  print(pred.displayText);
  print(pred.pct);        // 90
  print(pred.confidence); // 0.85
}
```

---

## How to retrain with real data (do this weekly)

```bash
export SUPABASE_URL=https://xxxx.supabase.co
export SUPABASE_KEY=your_anon_key

pip install supabase
python retrain_with_real_data.py

# Then copy updated rules to Flutter
cp model_rules.json ../assets/data/model_rules.json
```

---

## Feature columns explained

| Column | What it means |
|--------|--------------|
| `route` | Bus route number e.g. 19, 102, MAA2 |
| `direction` | DOWN (city-bound) or UP (suburb-bound) |
| `hour` | Hour of day 0–23 |
| `day_of_week` | 0=Mon, 1=Tue ... 6=Sun |
| `is_weekend` | 1 if Sat/Sun |
| `is_peak_am` | 1 if 7–9am |
| `is_peak_pm` | 1 if 5–7pm |
| `stop_zone` | city / suburb / airport |
| `crowding_label` | **Target**: low / medium / high |
| `crowding_pct` | **Target**: 20 / 50 / 90 |

---

## Adding new routes to seed_data.csv

Just add rows following the same pattern. Example:
```
583B,DOWN,8,0,0,1,0,suburb,medium,50
583B,DOWN,17,0,0,0,1,suburb,medium,50
```

Then retrain. Model updates automatically.

---

## When to retrain

| Stage | Action |
|-------|--------|
| Now (0 reports) | Use seed_data.csv only — already done |
| 50+ reports | Run retrain_with_real_data.py once |
| 200+ reports | Set up weekly cron on your Render backend |
| 1000+ reports | Real data dominates, seed becomes irrelevant |
