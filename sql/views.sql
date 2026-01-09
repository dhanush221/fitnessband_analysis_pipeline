-- Views to support Power BI reporting

CREATE SCHEMA IF NOT EXISTS fit;

-- Simple view for per-day activity with week bucket and day of week
CREATE OR REPLACE VIEW fit.vw_daily_activity AS
SELECT
  id,
  activity_date,
  date_trunc('week', activity_date)::date AS week_start,
  extract(dow from activity_date)::int AS day_of_week,
  total_steps,
  calories,
  total_distance,
  very_active_minutes,
  fairly_active_minutes,
  sedentary_minutes
FROM fit.daily_activity;

-- Daily summary (aggregated across users)
CREATE OR REPLACE VIEW fit.vw_daily_activity_summary AS
SELECT
  activity_date,
  COUNT(DISTINCT id) AS distinct_users,
  SUM(total_steps) AS total_steps,
  AVG(total_steps) AS avg_steps_per_user,
  AVG(very_active_minutes) AS avg_very_active_minutes,
  AVG(sedentary_minutes) AS avg_sedentary_minutes
FROM fit.daily_activity
GROUP BY activity_date
ORDER BY activity_date;

-- Latest snapshot of daily activity
CREATE OR REPLACE VIEW fit.vw_latest_daily_activity AS
SELECT * FROM fit.vw_daily_activity
WHERE activity_date = (SELECT max(activity_date) FROM fit.daily_activity)
ORDER BY id;

-- Composite score + human recommendations (match by tier; pick most recent rec for the tier)
CREATE OR REPLACE VIEW fit.vw_composite_recommendations AS
SELECT
  c.generated_at AS composite_generated_at,
  c.composite_health_score,
  c.tier,
  r.generated_at AS rec_generated_at,
  r.recommendation
FROM fit.composite_health_score c
LEFT JOIN LATERAL (
  SELECT recommendation, generated_at
  FROM fit.recommendations r2
  WHERE r2.tier = c.tier
  ORDER BY r2.generated_at DESC
  LIMIT 1
) r ON true;

-- Ideal benchmark table (small, editable) to compare against
CREATE TABLE IF NOT EXISTS fit.ideal_benchmarks (
  metric TEXT PRIMARY KEY,
  ideal_value NUMERIC,
  unit TEXT,
  description TEXT
);

INSERT INTO fit.ideal_benchmarks (metric, ideal_value, unit, description)
VALUES
  ('avg_steps_per_day', 10000, 'steps', 'Recommended daily steps'),
  ('avg_sleep_hours', 7.5, 'hours', 'Recommended daily sleep hours'),
  ('composite_health_score', 85, 'score', 'Target composite health score')
ON CONFLICT (metric) DO NOTHING;

-- Simple comparison view joining user summary (or daily summary) to ideal benchmarks
CREATE OR REPLACE VIEW fit.vw_compare_to_ideal AS
SELECT
  'population_avg_steps' AS metric,
  s.activity_date::date AS period_start,
  s.avg_steps_per_user AS value,
  b.ideal_value,
  (s.avg_steps_per_user - b.ideal_value) AS diff_from_ideal,
  b.unit
FROM fit.vw_daily_activity_summary s
JOIN fit.ideal_benchmarks b ON b.metric = 'avg_steps_per_day'
ORDER BY s.activity_date;
