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
url = f"postgresql+psycopg2://{PG['user']}:{PG['pw']}@{PG['host']}:{PG['port']}/{PG['db']}"
engine = create_engine(url)
PROCESSED = Path('data') / 'processed'

def upsert_dataframe(df, table_name, conflict_cols, update_cols):
    temp_table = f"tmp_{table_name}"
    with engine.begin() as conn:
        conn.execute(text(f"CREATE TEMP TABLE {temp_table} (LIKE fit.{table_name} INCLUDING ALL) ON COMMIT DROP;"))
        try:
            df.to_sql(temp_table, con=conn, schema=None, if_exists='append', index=False, method='multi')
            cols = df.columns.tolist()
            insert_cols = ', '.join(cols)
            conflict_cols_sql = ', '.join(conflict_cols)
            set_sql = ', '.join([f"{c}=EXCLUDED.{c}" for c in update_cols])
            sql = f"INSERT INTO fit.{table_name} ({insert_cols}) SELECT {insert_cols} FROM {temp_table} ON CONFLICT ({conflict_cols_sql}) DO UPDATE SET {set_sql};"
            print('Running SQL: ', sql[:200], '...')
            conn.execute(text(sql))
            print('Upsert OK')
        except Exception as e:
            print('Upsert failed: ', repr(e))

if __name__ == '__main__':
    da_file = PROCESSED / 'daily_activity_clean.csv'
    df = pd.read_csv(da_file, parse_dates=['activity_date']).head(6)
    print('DF dtypes:', df.dtypes)
    print(df.head())
    upsert_dataframe(df, 'daily_activity', ['id','activity_date'], [c for c in df.columns if c not in ['id','activity_date']])
