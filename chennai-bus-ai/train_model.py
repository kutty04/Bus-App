"""
Chennai Bus Crowding — ML Training Script
==========================================
Train a RandomForest classifier on seed_data.csv
Outputs:
  - model.pkl          (scikit-learn model)
  - label_encoder.pkl  (route label encoder)
  - model_rules.json   (exported rules for Dart/JS use)
  - evaluation.txt     (accuracy report)

Usage:
  pip install scikit-learn pandas numpy joblib
  python train_model.py
"""

import pandas as pd
import numpy as np
import json
import joblib
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import LabelEncoder
from sklearn.model_selection import cross_val_score, train_test_split
from sklearn.metrics import classification_report, confusion_matrix

# ── 1. Load Data ──────────────────────────────────────────────────────────────

df = pd.read_csv("seed_data.csv")
print(f"Loaded {len(df)} training rows")
print(f"Routes: {sorted(df['route'].unique())}")
print(f"Label distribution:\n{df['crowding_label'].value_counts()}\n")

# ── 2. Feature Engineering ───────────────────────────────────────────────────

# Encode route as integer
route_encoder = LabelEncoder()
df["route_enc"] = route_encoder.fit_transform(df["route"])

# Encode direction
df["direction_enc"] = (df["direction"] == "DOWN").astype(int)

# Encode stop_zone
zone_map = {"city": 0, "suburb": 1, "airport": 2}
df["zone_enc"] = df["stop_zone"].map(zone_map).fillna(0).astype(int)

# Target
label_map = {"low": 0, "medium": 1, "high": 2}
df["label_enc"] = df["crowding_label"].map(label_map)

# Feature columns used for training
FEATURES = [
    "route_enc",
    "direction_enc",
    "hour",
    "day_of_week",
    "is_weekend",
    "is_peak_am",
    "is_peak_pm",
    "zone_enc",
]

X = df[FEATURES]
y = df["label_enc"]

# ── 3. Train ──────────────────────────────────────────────────────────────────

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)

model = RandomForestClassifier(
    n_estimators=100,
    max_depth=8,
    min_samples_leaf=2,
    random_state=42,
    class_weight="balanced",
)
model.fit(X_train, y_train)

# ── 4. Evaluate ───────────────────────────────────────────────────────────────

y_pred = model.predict(X_test)
cv_scores = cross_val_score(model, X, y, cv=5, scoring="accuracy")

report = classification_report(
    y_test, y_pred, target_names=["low", "medium", "high"]
)

print("=== Evaluation ===")
print(report)
print(f"Cross-val accuracy: {cv_scores.mean():.2%} ± {cv_scores.std():.2%}")

with open("evaluation.txt", "w") as f:
    f.write("Chennai Bus Crowding — Model Evaluation\n")
    f.write("=" * 40 + "\n\n")
    f.write(report)
    f.write(f"\nCross-val accuracy: {cv_scores.mean():.2%} ± {cv_scores.std():.2%}\n")
    f.write(f"\nFeature importances:\n")
    for feat, imp in sorted(
        zip(FEATURES, model.feature_importances_), key=lambda x: -x[1]
    ):
        f.write(f"  {feat}: {imp:.3f}\n")

print("Saved evaluation.txt")

# ── 5. Save model ─────────────────────────────────────────────────────────────

joblib.dump(model, "model.pkl")
joblib.dump(route_encoder, "label_encoder.pkl")
print("Saved model.pkl and label_encoder.pkl")

# ── 6. Export rules as JSON (for Dart/Flutter use) ───────────────────────────
# We build a lookup table: route → direction → hour → day_type → prediction
# This avoids needing scikit-learn in Flutter

routes = df["route"].unique().tolist()
hours = list(range(4, 24))  # 4am to 11pm
days = list(range(7))
directions = ["DOWN", "UP"]

lookup = {}

for route in routes:
    lookup[route] = {}
    for direction in directions:
        lookup[route][direction] = {}
        for hour in hours:
            lookup[route][direction][str(hour)] = {}
            for day in days:
                is_weekend = 1 if day >= 5 else 0
                is_peak_am = 1 if 7 <= hour <= 9 else 0
                is_peak_pm = 1 if 17 <= hour <= 19 else 0

                # Get zone for this route (use most common zone)
                route_rows = df[df["route"] == route]
                if len(route_rows) > 0:
                    zone_enc = int(route_rows["zone_enc"].mode()[0])
                else:
                    zone_enc = 0

                try:
                    route_enc = int(route_encoder.transform([route])[0])
                except Exception:
                    route_enc = 0

                direction_enc = 1 if direction == "DOWN" else 0

                features = [[
                    route_enc,
                    direction_enc,
                    hour,
                    day,
                    is_weekend,
                    is_peak_am,
                    is_peak_pm,
                    zone_enc,
                ]]

                pred = model.predict(features)[0]
                proba = model.predict_proba(features)[0]
                label = ["low", "medium", "high"][pred]
                pct = [20, 50, 90][pred]
                confidence = round(float(max(proba)), 2)

                lookup[route][direction][str(hour)][str(day)] = {
                    "label": label,
                    "pct": pct,
                    "confidence": confidence,
                }

with open("model_rules.json", "w") as f:
    json.dump(lookup, f, separators=(",", ":"))

print(f"Saved model_rules.json ({len(json.dumps(lookup)) // 1024}KB)")
print("\nDone! Files created:")
print("  model.pkl          — sklearn model for retraining")
print("  label_encoder.pkl  — route encoder")
print("  model_rules.json   — embed this in your Flutter app")
print("  evaluation.txt     — accuracy report")
