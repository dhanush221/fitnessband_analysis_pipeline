-- fit.vw_analysis_master
-- A joined view of Daily Activity and Sleep for Power BI
CREATE OR REPLACE VIEW fit.vw_analysis_master AS
SELECT 
    da.id,
    da.activity_date AS date,
    da.total_steps,
    da.calories,
    da.total_distance,
    da.very_active_minutes,
    da.fairly_active_minutes,
    da.sedentary_minutes,
    -- Join Sleep Data
    COALESCE(ds.sleep_minutes, 0) AS sleep_minutes,
    COALESCE(ds.sleep_hours, 0) AS sleep_hours,
    -- Derived Metrics
    CASE WHEN da.total_steps >= 10000 THEN true ELSE false END AS goal_met_steps,
    CASE WHEN ds.sleep_hours >= 7 THEN true ELSE false END AS goal_met_sleep,
    -- Composite Key for Row Identification in BI
    CONCAT(da.id, '_', da.activity_date) AS row_key
FROM fit.daily_activity da
LEFT JOIN fit.daily_sleep ds 
    ON da.id = ds.id 
    AND da.activity_date = ds.sleep_date;
