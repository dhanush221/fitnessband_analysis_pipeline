"""etl/pipeline.py
Simple ETL for Fitabase CSVs (extract / transform / load)
- Loads raw CSVs from data/raw/
- Standardizes column names
- Parses date/time fields
- Handles simple missing value cases
- Aggregates daily activity, daily sleep, and user-level metrics
- Saves cleaned tables to data/processed/
Supports incremental mode via --since YYYY-MM-DD to process only newer dates.
"""

import re
import argparse
import json
from datetime import datetime, date, timedelta
import pandas as pd
from pathlib import Path

RAW = Path("data") / "raw" / "Fitabase Data 3.12.16-4.11.16"
PROCESSED = Path("data") / "processed"
PROCESSED.mkdir(parents=True, exist_ok=True)

STATE_FILE = Path('etl') / 'state.json'
STATE_FILE.parent.mkdir(parents=True, exist_ok=True)

# Helper utilities

def snake_case_cols(cols):
    def _sc(col):
        col = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", col)
        col = col.replace(" ", "_").replace("-", "_")
        col = re.sub(r"__+", "_", col)
        return col.lower()
    return [ _sc(c) for c in cols ]


def load_csv(file_path):
    if not file_path.exists():
        raise FileNotFoundError(f"Required file not found: {file_path}")
    return pd.read_csv(file_path)


def load_state():
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text())
        except Exception:
            return {}
    return {}


def save_state(state: dict):
    STATE_FILE.write_text(json.dumps(state, default=str))


# CLI
parser = argparse.ArgumentParser(description='Fitabase ETL')
parser.add_argument('--since', type=str, help='Process only dates >= YYYY-MM-DD')
parser.add_argument('--one-day', action='store_true', help='Process the next single unprocessed date (advance state by one day)')
args = parser.parse_args()

since = None
single_day = None
if args.one_day:
    # try to pick next date from state; if no state, will derive from data after load
    state = load_state()
    last = state.get('last_date_processed')
    if last:
        try:
            single_day = datetime.strptime(last, '%Y-%m-%d').date() + timedelta(days=1)
            print(f'Running one-day incremental ETL for {single_day}')
        except Exception:
            single_day = None
            print('Running one-day incremental ETL; will pick earliest available date after loading data')
    else:
        print('Running one-day incremental ETL; will pick earliest available date after loading data')
elif args.since:
    since = datetime.strptime(args.since, '%Y-%m-%d').date()
    print(f'Running incremental ETL since {since}')
else:
    print('Running full ETL')

# 1) Extract
print(f"Loading raw CSVs from {RAW}")
files = {
    "daily_activity": RAW / "dailyActivity_merged.csv",
    "hourly_steps": RAW / "hourlySteps_merged.csv",
    "minute_sleep": RAW / "minuteSleep_merged.csv",
    "minute_steps": RAW / "minuteStepsNarrow_merged.csv",
    "weight_log": RAW / "weightLogInfo_merged.csv",
}

loaded = {}
for name, path in files.items():
    try:
        loaded[name] = load_csv(path)
        print(f"Loaded {name}: {len(loaded[name])} rows")
    except FileNotFoundError:
        print(f"Warning: {path} not found; skipping {name}")
        loaded[name] = None


# 2) Transform: standardize column names & parse dates
for name, df in list(loaded.items()):
    if df is None:
        continue
    df.columns = snake_case_cols(df.columns)
    # drop exact duplicate rows
    before = len(df)
    df = df.drop_duplicates()
    after = len(df)
    if before != after:
        print(f"Dropped {before-after} duplicate rows from {name}")
    loaded[name] = df

# Parse dates where present
if loaded.get("daily_activity") is not None:
    df = loaded["daily_activity"]
    if "activity_date" in df.columns or "activitydate" in df.columns:
        # support both variants: activity_date (snake_case) or activitydate (older)
        if "activity_date" in df.columns:
            date_col = "activity_date"
        else:
            date_col = "activitydate"
        df[date_col] = pd.to_datetime(df[date_col], format="%m/%d/%Y", errors="coerce").dt.date
        na_dates = df[date_col].isna().sum()
        if na_dates:
            print(f"daily_activity: {na_dates} rows with unparsed activity date set to NA")
    loaded["daily_activity"] = df

if loaded.get("hourly_steps") is not None:
    df = loaded["hourly_steps"]
    if "activity_hour" in df.columns or "activityhour" in df.columns:
        if "activity_hour" in df.columns:
            dt_col = "activity_hour"
        else:
            dt_col = "activityhour"
        df[dt_col] = pd.to_datetime(df[dt_col], format="%m/%d/%Y %I:%M:%S %p", errors="coerce")
        na_dt = df[dt_col].isna().sum()
        if na_dt:
            print(f"hourly_steps: {na_dt} rows with unparsed activity hour set to NA")
    loaded["hourly_steps"] = df

if loaded.get("minute_sleep") is not None:
    df = loaded["minute_sleep"]
    if "date" in df.columns or "datetime" in df.columns:
        dt_col = "date" if "date" in df.columns else "datetime"
        df[dt_col] = pd.to_datetime(df[dt_col], format="%m/%d/%Y %I:%M:%S %p", errors="coerce")
        na_dt = df[dt_col].isna().sum()
        if na_dt:
            print(f"minute_sleep: {na_dt} rows with unparsed date set to NA")
    loaded["minute_sleep"] = df

# if running one-day mode and we didn't find a next date in state, derive it from the data
if args.one_day and single_day is None:
    cand_dates = []
    if loaded.get('daily_activity') is not None:
        df = loaded['daily_activity']
        if 'activitydate' in df.columns:
            m = df['activitydate'].min()
            if pd.notna(m):
                cand_dates.append(m)
        elif 'activity_date' in df.columns:
            m = df['activity_date'].min()
            if pd.notna(m):
                cand_dates.append(m)
    if loaded.get('minute_sleep') is not None and 'date' in loaded['minute_sleep'].columns:
        m = loaded['minute_sleep']['date'].dt.date.min()
        if pd.notna(m):
            cand_dates.append(m)
    cand_dates = [d for d in cand_dates if d is not None]
    if not cand_dates:
        print('No available dates found for one-day run; exiting')
        exit(0)
    single_day = min(cand_dates)
    print(f'One-day run will process earliest available date: {single_day}')
elif args.one_day and single_day is not None:
    # ensure the next date exists in available data
    max_date = None
    if loaded.get('daily_activity') is not None and 'activitydate' in loaded['daily_activity'].columns:
        max_date = loaded['daily_activity']['activitydate'].max()
    if max_date and single_day > max_date:
        print(f'Next date {single_day} is beyond available data ({max_date}); nothing to process')
        exit(0)

# 3) Handle missing values (basic rules)
for name, df in list(loaded.items()):
    if df is None:
        continue
    # require Id for all tables
    if "id" in df.columns:
        missing_id = df["id"].isna().sum()
        if missing_id:
            print(f"{name}: dropping {missing_id} rows with missing id")
            df = df[df["id"].notna()]
    # convert numeric-like columns
    for col in df.columns:
        if df[col].dtype == object and col not in ("activityhour", "date", "activitydate"):
            # attempt numeric coercion for columns that look numeric
            coerced = pd.to_numeric(df[col], errors="coerce")
            if coerced.notna().sum() > 0 and coerced.isna().sum() < len(df):
                df[col] = coerced
    loaded[name] = df


# 4) Aggregate
# Daily activity (cleaned copy)
processed_max_date = None
if loaded.get("daily_activity") is not None:
    daily = loaded["daily_activity"].copy()
    # filter incremental or single-day
    if "activitydate" in daily.columns:
        if single_day is not None:
            daily = daily[daily["activitydate"] == single_day]
        elif since is not None:
            daily = daily[daily["activitydate"] >= since]
    if "activitydate" in daily.columns and not daily["activitydate"].isna().all():
        if not daily.empty:
            processed_max_date = daily["activitydate"].max()
    # keep relevant columns and rename to explicit names
    # column names after snake_case normalization; map to canonical names
    col_map = {
        "total_steps": "total_steps",
        "calories": "calories",
        "total_distance": "total_distance",
        "very_active_minutes": "very_active_minutes",
        "fairly_active_minutes": "fairly_active_minutes",
        "sedentary_minutes": "sedentary_minutes",
        "activity_date": "activity_date",
        "id": "id",
    }
    keep = [c for c in col_map.keys() if c in daily.columns]
    daily = daily[keep].rename(columns={k: col_map[k] for k in keep})
    out_name = "daily_activity_clean.csv" if since is None and single_day is None else f"daily_activity_clean_{since if single_day is None else single_day}.csv"
    daily.to_csv(PROCESSED / out_name, index=False)
    print(f"Saved {out_name} ({len(daily)} rows)")

# Daily sleep (aggregate minutes per day per user)
if loaded.get("minute_sleep") is not None:
    ms = loaded["minute_sleep"].copy()
    if "date" in ms.columns:
        ms["sleep_date"] = ms["date"].dt.date
        if single_day is not None:
            ms = ms[ms["sleep_date"] == single_day]
        elif since is not None:
            ms = ms[ms["sleep_date"] >= since]
        daily_sleep = (ms
          .groupby(["id", "sleep_date"])
          .size()
          .reset_index(name="sleep_minutes"))
        daily_sleep["sleep_hours"] = daily_sleep["sleep_minutes"] / 60.0
        out_name = "daily_sleep.csv" if since is None and single_day is None else f"daily_sleep_{since if single_day is None else single_day}.csv"
        daily_sleep.to_csv(PROCESSED / out_name, index=False)
        print(f"Saved {out_name} ({len(daily_sleep)} rows)")

# User-level metrics (means)
# activity
if loaded.get("daily_activity") is not None:
    da = loaded["daily_activity"].copy()
    if "activitydate" in da.columns:
        if single_day is not None:
            da = da[da["activitydate"] == single_day]
        elif since is not None:
            da = da[da["activitydate"] >= since]
    # ensure activitydate exists
    if "activitydate" in da.columns:
        user_activity = (da
                         .groupby("id")
                         .agg(
                             avg_steps=("total_steps", lambda x: pd.to_numeric(x, errors="coerce").mean()),
                             avg_calories=("calories", lambda x: pd.to_numeric(x, errors="coerce").mean()),
                             avg_distance=("total_distance", lambda x: pd.to_numeric(x, errors="coerce").mean()),
                             avg_very_active=("very_active_minutes", lambda x: pd.to_numeric(x, errors="coerce").mean()),
                             avg_sedentary=("sedentary_minutes", lambda x: pd.to_numeric(x, errors="coerce").mean())
                         )
                         .reset_index())
        out_name = "user_activity_summary.csv" if since is None and single_day is None else f"user_activity_summary_{since if single_day is None else single_day}.csv"
        user_activity.to_csv(PROCESSED / out_name, index=False)
        print(f"Saved {out_name} ({len(user_activity)} rows)")

# user sleep
if 'daily_sleep' in locals():
    user_sleep = (daily_sleep
                  .groupby("id")
                  .agg(avg_sleep_hours=("sleep_hours", "mean"))
                  .reset_index())
    out_name = "user_sleep_summary.csv" if since is None and single_day is None else f"user_sleep_summary_{single_day if single_day is not None else since}.csv"
    user_sleep.to_csv(PROCESSED / out_name, index=False)
    print(f"Saved {out_name} ({len(user_sleep)} rows)")

# save state if incremental or one-day
processed_date_to_save = processed_max_date
if processed_date_to_save is None and single_day is not None:
    processed_date_to_save = single_day

if (since is not None or single_day is not None) and processed_date_to_save is not None:
    state = load_state()
    state['last_run'] = datetime.utcnow().isoformat()
    state['last_date_processed'] = str(processed_date_to_save)
    save_state(state)
    print(f"Updated local state: last_date_processed={processed_date_to_save}")

print("ETL finished — processed files are in data/processed/")
