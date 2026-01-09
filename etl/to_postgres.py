"""etl/to_postgres.py
Load processed CSVs into PostgreSQL using SQLAlchemy. Reads DB creds from .env.
"""
import os
from pathlib import Path
import pandas as pd
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

load_dotenv()

PG = {
    'host': os.getenv('PG_HOST', 'localhost'),
    'port': os.getenv('PG_PORT', '5432'),
    'db': os.getenv('PG_DB', 'fitdb'),
    'user': os.getenv('PG_USER', 'fituser'),
    'pw': os.getenv('PG_PASSWORD', 'fitpass')
}

WRITE_TO_DB = os.getenv('WRITE_TO_DB', 'false').lower() in ('1','true','yes')

PROCESSED = Path('data') / 'processed'

url = f"postgresql+psycopg2://{PG['user']}:{PG['pw']}@{PG['host']}:{PG['port']}/{PG['db']}"

import argparse
parser = argparse.ArgumentParser(description='Write processed CSVs to Postgres')
parser.add_argument('--incremental', action='store_true', help='Perform upsert for incremental files')
args = parser.parse_args()

if not WRITE_TO_DB:
    print('WRITE_TO_DB not enabled; set WRITE_TO_DB=true in your .env to enable DB writes')

if WRITE_TO_DB:
    engine = create_engine(url)

    # Create schema and tables (if provided SQL file exists, execute it)
    sql_file = Path('sql') / 'create_tables.sql'
    if sql_file.exists():
        with engine.connect() as conn:
            sql = sql_file.read_text()
            conn.execute(text(sql))
            conn.commit()
        print('Ensured DB schema/tables exist')

    # Apply Views (e.g. fit.vw_analysis_master)
    view_file = Path('sql') / 'create_views.sql'
    if view_file.exists():
        with engine.connect() as conn:
            sql = view_file.read_text()
            conn.execute(text(sql))
            conn.commit()
        print('Applied SQL Views')

    def upsert_dataframe(df, table_name, conflict_cols, update_cols, chunk_size=100):
        """Upsert dataframe into table in manageable chunks to avoid parameter limits."""
        if df.empty:
            print(f'No rows to upsert for {table_name}')
            return
        total = len(df)
        for start in range(0, total, chunk_size):
            chunk = df.iloc[start:start+chunk_size]
            temp_table = f"tmp_{table_name}"
            with engine.begin() as conn:
                conn.execute(text(f"CREATE TEMP TABLE {temp_table} (LIKE fit.{table_name} INCLUDING ALL) ON COMMIT DROP;"))
                chunk.to_sql(temp_table, con=conn, schema=None, if_exists='append', index=False, method='multi')
                cols = chunk.columns.tolist()
                insert_cols = ', '.join(cols)
                conflict_cols_sql = ', '.join(conflict_cols)
                set_sql = ', '.join([f"{c}=EXCLUDED.{c}" for c in update_cols])
                sql = f"INSERT INTO fit.{table_name} ({insert_cols}) SELECT {insert_cols} FROM {temp_table} ON CONFLICT ({conflict_cols_sql}) DO UPDATE SET {set_sql};"
                conn.execute(text(sql))
            print(f'Upserted {len(chunk)} rows into fit.{table_name} (batch start {start})')
        print(f'Finished upserting {total} rows into fit.{table_name}')

    def _last_run_date_from_env_or_state():
        env_date = os.getenv('LAST_RUN_DATE','').strip()
        if env_date:
            return env_date
        state_file = Path('etl') / 'state.json'
        if state_file.exists():
            try:
                import json
                s = json.loads(state_file.read_text())
                return s.get('last_date_processed','')
            except Exception:
                return ''
        return ''

    # daily_activity
    if args.incremental:
        last_date = _last_run_date_from_env_or_state()
        da_file = PROCESSED / f'daily_activity_clean_{last_date}.csv' if last_date else PROCESSED / 'daily_activity_clean.csv'
        # fallback to any incremental file
        if not da_file.exists():
            da_candidates = list(PROCESSED.glob('daily_activity_clean_*.csv'))
            da_file = da_candidates[-1] if da_candidates else PROCESSED / 'daily_activity_clean.csv'
    else:
        da_file = PROCESSED / 'daily_activity_clean.csv'

    if da_file.exists():
        df = pd.read_csv(da_file, parse_dates=['activity_date'])
        # Upsert based on (id, activity_date)
        upsert_dataframe(df, 'daily_activity', conflict_cols=['id','activity_date'], update_cols=[c for c in df.columns if c not in ['id','activity_date']])

    # daily_sleep
    if args.incremental:
        last_date = _last_run_date_from_env_or_state()
        ds_file = PROCESSED / f'daily_sleep_{last_date}.csv' if last_date else PROCESSED / 'daily_sleep.csv'
        if not ds_file.exists():
            ds_candidates = list(PROCESSED.glob('daily_sleep_*.csv'))
            ds_file = ds_candidates[-1] if ds_candidates else PROCESSED / 'daily_sleep.csv'
    else:
        ds_file = PROCESSED / 'daily_sleep.csv'

    if ds_file.exists():
        df = pd.read_csv(ds_file, parse_dates=['sleep_date'])
        upsert_dataframe(df, 'daily_sleep', conflict_cols=['id','sleep_date'], update_cols=[c for c in df.columns if c not in ['id','sleep_date']])

    # user_activity_summary (overwrite or upsert by id)
    if args.incremental:
        last_date = _last_run_date_from_env_or_state()
        uas_file = PROCESSED / f'user_activity_summary_{last_date}.csv' if last_date else PROCESSED / 'user_activity_summary.csv'
        if not uas_file.exists():
            uas_candidates = list(PROCESSED.glob('user_activity_summary_*.csv'))
            uas_file = uas_candidates[-1] if uas_candidates else PROCESSED / 'user_activity_summary.csv'
    else:
        uas_file = PROCESSED / 'user_activity_summary.csv'

    if uas_file.exists():
        df = pd.read_csv(uas_file)
        upsert_dataframe(df, 'user_summary', conflict_cols=['id'], update_cols=[c for c in df.columns if c != 'id'])

    # composite scores / recommendations from outputs -> append
    from sqlalchemy import inspect

    def append_to_table(raw_df, table_name):
        """Normalize headers, align with DB table columns, and append only matching columns."""
        if raw_df.empty:
            print(f'No rows to append for {table_name}')
            return
        # normalize column names to snake_case / lower so they match DB schema
        df2 = raw_df.copy()
        df2.columns = [c.strip().lower().replace(' ', '_') for c in df2.columns]

        inspector = inspect(engine)
        try:
            cols = [c['name'] for c in inspector.get_columns(table_name, schema='fit')]
        except Exception as e:
            print(f'Could not introspect table fit.{table_name}:', e)
            return

        keep = [c for c in df2.columns if c in cols]
        drop = [c for c in df2.columns if c not in cols]
        if not keep:
            print(f'No matching columns between DataFrame and fit.{table_name}; skipping append. Columns dropped: {drop}')
            return
        if drop:
            print(f'Appending to fit.{table_name}: dropping {len(drop)} unexpected columns: {drop}')
        try:
            df2[keep].to_sql(table_name, engine, schema='fit', if_exists='append', index=False, method='multi')
            print(f'Appended {len(df2)} rows to fit.{table_name} (kept columns: {keep})')
        except Exception as e:
            print(f'Failed to append to fit.{table_name}:', e)

    out_composite = Path('outputs') / 'composite_health_score.csv'
    out_rec = Path('outputs') / 'behavioral_recommendations.csv'
    if out_composite.exists():
        df_comp = pd.read_csv(out_composite)
        append_to_table(df_comp, 'composite_health_score')
    if out_rec.exists():
        df_rec = pd.read_csv(out_rec)
        append_to_table(df_rec, 'recommendations')
    
    out_comparison = Path('outputs') / 'scored_comparison.csv'
    if out_comparison.exists():
        df_comparison = pd.read_csv(out_comparison)
        append_to_table(df_comparison, 'scored_comparison')

    # update etl_state
    with engine.begin() as conn:
        last_date = None
        try:
            # prefer to use the most recent activity date from the DB
            r = conn.execute(text('SELECT max(activity_date) FROM fit.daily_activity'))
            last_date = r.scalar()
        except Exception:
            last_date = None
        conn.execute(text("INSERT INTO fit.etl_state (last_run, last_date_processed) VALUES (now(), :d)"), {'d': last_date})
        print('Updated fit.etl_state')

    # write local state.json
    try:
        import json
        from datetime import datetime
        state = {'last_run': datetime.utcnow().isoformat(), 'last_date_processed': str(last_date) if last_date is not None else None}
        Path('etl').mkdir(parents=True, exist_ok=True)
        Path('etl/state.json').write_text(json.dumps(state))
        print('Wrote etl/state.json')
    except Exception as e:
        print('Could not write local state.json', e)
else:
    print('DB writes skipped')
