"""
Chennai Bus Crowding — Retrain with Real Supabase Data (REST Version)
=====================================================================
This version bypasses the 'supabase' library to avoid C++ compiler errors.
"""

import os
import pandas as pd
import numpy as np
import json
import joblib
import requests
from datetime import datetime

# ── 1. Pull real reports from Supabase via REST ──────────────────────────────

def fetch_real_data():
    # Credentials provided in your prompt
    URL = "https://olgrwxyqhfvolscdygln.supabase.co"
    # Using the Service Role Key for full access
    KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9sZ3J3eHlxaGZ2b2xzY2R5Z2xuIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NTIwNjQ5NiwiZXhwIjoyMDkwNzgyNDk2fQ.53_LcgqPllM6LnuG7eSUN8xCpb2RlSsR6J0vAxsNTL8"

    try:
        headers = {
            "apikey": KEY,
            "Authorization": f"Bearer {KEY}",
            "Content-Type": "application/json"
        }
        
        # We target the 'crowding_reports' table directly
        api_url = f"{URL}/rest/v1/crowding_reports?select=bus_route,crowding_level,boarding_stop,is_ac,timestamp"
        
        print("Connecting to Supabase via REST...")
        response = requests.get(api_url, headers=headers)
        response.raise_for_status()
        
        rows = response.json()
        print(f"Fetched {len(rows)} real reports from Supabase")
        return pd.DataFrame(rows)
        
    except Exception as e:
        print(f"⚠ Could not fetch from Supabase: {e}")
        return pd.DataFrame()


def process_real_data(df_raw):
    """Convert raw Supabase reports into training features."""
    if df_raw.empty:
        return pd.DataFrame()

    records = []
    for _, row in df_raw.iterrows():
        try:
            # Parse timestamp to extract time features
            ts = pd.to_datetime(row["timestamp"])
            hour = ts.hour
            day = ts.weekday()  # 0=Mon, 6=Sun
            is_weekend = 1 if day >= 5 else 0
            is_peak_am = 1 if 7 <= hour <= 9 else 0
            is_peak_pm = 1 if 17 <= hour <= 19 else 0

            # Map crowding_level (e.g., 'low', 'medium', 'high') to training labels
            lvl = str(row.get("crowding_level", "low")).lower()
            if "20" in lvl or "low" in lvl:
                label, pct = "low", 20
            elif "50" in lvl or "medium" in lvl:
                label, pct = "medium", 50
            else:
                label, pct = "high", 90

            # Categorize route zones
            route = str(row.get("bus_route", "")).strip().upper()
            zone = "airport" if "MAA" in route else (
                "suburb" if route in ["102", "102C", "519T", "99", "91"] else "city"
            )

            records.append({
                "route": route,
                "direction": "DOWN",  # Defaulting as it's often common for training
                "hour": hour,
                "day_of_week": day,
                "is_weekend": is_weekend,
                "is_peak_am": is_peak_am,
                "is_peak_pm": is_peak_pm,
                "stop_zone": zone,
                "crowding_label": label,
                "crowding_pct": pct,
            })
        except Exception:
            continue 

    return pd.DataFrame(records)


# ── 2. Merge seed + real data ─────────────────────────────────────────────────

print("--- Starting Retraining Pipeline ---")
seed_df = pd.read_csv("seed_data.csv")
real_raw = fetch_real_data()
real_df = process_real_data(real_raw)

if not real_df.empty:
    # We repeat the real data 3 times to give it higher priority (Weighting)
    real_df_weighted = pd.concat([real_df] * 3, ignore_index=True)
    combined_df = pd.concat([seed_df, real_df_weighted], ignore_index=True)
    print(f"Combined: {len(seed_df)} seed + {len(real_df)*3} weighted real = {len(combined_df)} rows")
else:
    combined_df = seed_df
    print("No real data fetched. Using seed data only.")

# Save for auditing purposes
combined_df.to_csv("combined_training_data.csv", index=False)

# ── 3. Execute Training Script ────────────────────────────────────────────────

print("\nExecuting train_model.py...")
import subprocess
import sys

# This runs your existing train_model.py which outputs model.pkl and model_rules.json
result = subprocess.run(
    [sys.executable, "train_model.py"],
    capture_output=True, text=True
)

print(result.stdout)
if result.returncode != 0:
    print("ERROR during training:", result.stderr)

print(f"\nPipeline complete at {datetime.now().strftime('%Y-%m-%d %H:%M')}")
print("Final Step: Copy 'model_rules.json' to your Flutter assets/data/ folder.")