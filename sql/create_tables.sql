-- Schema for Fitabase processed data
CREATE SCHEMA IF NOT EXISTS fit;

CREATE TABLE IF NOT EXISTS fit.daily_activity (
  id BIGINT,
  activity_date DATE,
  total_steps INTEGER,
  calories NUMERIC,
  total_distance NUMERIC,
  very_active_minutes INTEGER,
  fairly_active_minutes INTEGER,
  sedentary_minutes INTEGER,
  PRIMARY KEY (id, activity_date)
);

CREATE TABLE IF NOT EXISTS fit.daily_sleep (
  id BIGINT,
  sleep_date DATE,
  sleep_minutes INTEGER,
  sleep_hours NUMERIC,
  PRIMARY KEY (id, sleep_date)
);

CREATE TABLE IF NOT EXISTS fit.user_summary (
  id BIGINT PRIMARY KEY,
  avg_steps NUMERIC,
  avg_calories NUMERIC,
  avg_distance NUMERIC,
  avg_very_active NUMERIC,
  avg_sedentary NUMERIC,
  avg_sleep_hours NUMERIC
);

CREATE TABLE IF NOT EXISTS fit.composite_health_score (
  generated_at TIMESTAMP DEFAULT now(),
  composite_health_score NUMERIC,
  tier TEXT
);

CREATE TABLE IF NOT EXISTS fit.recommendations (
  generated_at TIMESTAMP DEFAULT now(),
  tier TEXT,
  recommendation TEXT
);

CREATE TABLE IF NOT EXISTS fit.scored_comparison (
  generated_at TIMESTAMP DEFAULT now(),
  type TEXT,
  metric TEXT,
  value NUMERIC,
  performance_percent NUMERIC
);

-- ETL state tracking
CREATE TABLE IF NOT EXISTS fit.etl_state (
  id SERIAL PRIMARY KEY,
  last_run TIMESTAMPTZ,
  last_date_processed DATE
);
