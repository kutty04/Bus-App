# 🚌 Chennai Bus Crowding Tracker

> **⚠️ Work in Progress (WIP)**  
> This project is currently under active development. Some features are being integrated and refined.

---

A premium, real-time crowding tracker and route planner for the Chennai Metropolitan Transport Corporation (MTC) OMR bus corridor. Built with **Flutter** for the mobile app, powered by **Supabase** for real-time reporting, and equipped with a **Python-based offline Machine Learning** engine to predict crowding levels when offline.

---

## 🌟 Key Features

* **Real-time Crowding Feed:** Displays live crowd reports submitted by commuters on the OMR corridor in the last 30 minutes.
* **Smart Route Planner:** Calculates direct and 1-transfer routes between transit stops using a custom routing algorithm powered by a localized **6.1 MB GTFS dataset** (`mtc_data.dart`).
* **Crowd-sourced Reporting:** Enables commuters to report crowding levels (seated, standing, heavily crowded), bus details (AC/Non-AC, Ladies-only flag), and boarding stops.
* **Offline AI Crowding Predictor:** When network connectivity is lost, the app relies on a locally stored Decision Tree ruleset (`model_rules.json`) to predict expected crowding levels based on stop, route, time of day, and history.
* **Anonymous Safety Flags:** Commuters can log safety concerns on routes anonymously, showing warning notifications in the live feed.
* **Active Onboarding & Location Services:** Features a smooth onboarding flow, automatic geolocation of nearest stops (using the device GPS), and notification prompts.

---

## 🏗️ Architecture & Data Flow

Below is a diagram showing how the Flutter app, Supabase backend, local routing data, and the offline machine learning service interact:

```mermaid
graph TD
    subgraph Client Application (Flutter)
        UI[App Screens & Widgets]
        Router[MTC Routing Engine]
        ML[Offline ML Predictor]
    end

    subgraph Data Sources
        GTFS[MTC GTFS Dataset: mtc_data.dart]
        Rules[Ruleset: model_rules.json]
    end

    subgraph Backend Services
        Supa[(Supabase Postgres DB)]
        AI[Python ML Trainer: train_model.py]
    end

    %% Routing
    GTFS -->|Pre-compiled stops/routes| Router
    Router -->|Calculate paths| UI

    %% Live Data
    UI -->|Write reports & safety concerns| Supa
    Supa -->|Real-time postgres changes sync| UI

    %% ML Flow
    AI -->|Train on seed data| Rules
    Rules -->|Local evaluation| ML
    UI -->|Fallback when offline| ML
```

---

## 🛠️ Technology Stack

* **Frontend Framework:** Flutter (Dart)
* **Backend Database:** Supabase (Postgres with Realtime enabled)
* **AI/ML Engine:** Python (scikit-learn, Pandas)
* **Routing Dataset:** Pre-processed General Transit Feed Specification (GTFS) data

---

## 📂 Project Structure

```
chennai_bus_crowding/
├── android/                   # Android native code and manifests
├── assets/                    # Image assets, app icons, and graphics
├── chennai-bus-ai/            # AI/ML Python training module
│   ├── train_model.py         # Trains the Decision Tree model on historical CSVs
│   ├── retrain_with_real_data.py # Merges real reports with seeds to refine rules
│   ├── seed_data.csv          # Base training dataset
│   ├── model.pkl              # Saved scikit-learn model artifact
│   └── model_rules.json       # Compiled ruleset exported for Dart usage
├── lib/                       # Main Flutter source code
│   ├── data/
│   │   ├── Destinations.dart  # Predefined popular destinations
│   │   ├── mtc_data.dart      # 6.1 MB precompiled OMR stop coordinates and routes
│   │   └── model_rules.json   # Local copy of the ML ruleset for the app
│   ├── screens/               # Mobile UI screens (Feed, Search, Report, Journey, Onboarding)
│   ├── services/              # Logic services (Supabase, GPS, Notifications, Routing, ML Predict)
│   ├── widgets/               # Reusable UI elements (banners, cards, selector bars)
│   ├── theme.dart             # Dark-themed visual design system
│   └── main.dart              # App entry point and Supabase initialization
├── web/                       # Web configuration and splash layout
└── pubspec.yaml               # Flutter package configuration and dependencies
```

---

## ⚙️ Local Setup Instructions

<details>
<summary><b>1. Mobile App Setup (Flutter)</b></summary>

### Prerequisites
* installed [Flutter SDK](https://docs.flutter.dev/get-started/install) (v3.0.0+)
* Android Studio or Xcode (for emulator execution)

### Steps
1. Navigate to the root directory:
   ```bash
   cd chennai_bus_crowding
   ```
2. Fetch dependencies:
   ```bash
   flutter pub get
   ```
3. Run the app:
   * **Development Mode:**
     ```bash
     flutter run
     ```
   * **Production Web Build:**
     ```bash
     flutter build web
     ```
</details>

<details>
<summary><b>2. AI Model Training Setup (Python)</b></summary>

### Prerequisites
* Python 3.8+
* Required packages: `scikit-learn`, `pandas`, `numpy`

### Steps
1. Navigate to the AI directory:
   ```bash
   cd chennai-bus-ai
   ```
2. Install dependencies:
   ```bash
   pip install pandas scikit-learn
   ```
3. Train the model and generate a new ruleset:
   ```bash
   python train_model.py
   ```
   This will output a fresh `model.pkl` and compile a new `model_rules.json`.
4. Copy the compiled ruleset to the Flutter project:
   ```bash
   copy model_rules.json ..\lib\data\model_rules.json
   ```
</details>

---

## 🤖 How the Offline AI Predictor Works
1. Historical bus crowding reports are compiled into a training dataset (`seed_data.csv`).
2. A **Decision Tree** model is trained in Python (`train_model.py`) using features: **Stop ID, Route ID, Day of Week, and Hour of Day**.
3. To bypass Python execution constraints inside a Flutter app, the trained tree is parsed and exported into a declarative JSON ruleset (`model_rules.json`).
4. The Flutter application uses [Crowd_prediction_service.dart](file:///C:/Users/R.Murugesan/.gemini/antigravity/playground/chennai_bus_crowding/lib/services/Crowd_prediction_service.dart) to traverse this ruleset in memory. This delivers instantaneous, offline-ready crowding predictions without any API latency or network requirements.

---

## 📝 Roadmap & Current Tasks
- [x] Integrate MTC OMR routing algorithm (`bus_lookup_service.dart`)
- [x] Implement Supabase database integration
- [x] Configure offline Decision Tree parser
- [/] Refine the widget tests (fix `test/widget_test.dart` class initialization)
- [ ] Implement user settings profile
- [ ] Connect live push notifications for crowding spikes
