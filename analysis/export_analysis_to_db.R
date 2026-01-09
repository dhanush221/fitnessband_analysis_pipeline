# analysis/export_analysis_to_db.R
# A small example script that reads processed CSVs or DB tables, computes
# simple comparisons vs. 'ideal' benchmarks, and writes results back to Postgres

library(DBI)
library(RPostgres)
library(dplyr)
library(readr)

# Read DB connection info from env (or adjust manually)
host <- Sys.getenv('PG_HOST', 'localhost')
port <- as.integer(Sys.getenv('PG_PORT', '5433'))
db <- Sys.getenv('PG_DB', 'fitbit')
user <- Sys.getenv('PG_USER', 'postgres')
password <- Sys.getenv('PG_PASSWORD', '')

con <- dbConnect(RPostgres::Postgres(), host = host, port = port, dbname = db, user = user, password = password)

# Example: compute population daily avg steps, compare to 'ideal_benchmarks'
# Prefer querying the view we created for Power BI
daily <- dbGetQuery(con, 'SELECT * FROM fit.vw_daily_activity_summary')
ideal <- dbGetQuery(con, "SELECT * FROM fit.ideal_benchmarks WHERE metric = 'avg_steps_per_day'")

if (nrow(ideal) > 0 && nrow(daily) > 0) {
  res <- daily %>%
    transmute(
      period_start = activity_date,
      metric = 'avg_steps_per_day',
      value = avg_steps_per_user,
      ideal_value = as.numeric(ideal$ideal_value[1]),
      diff_from_ideal = value - ideal_value,
      unit = ideal$unit[1]
    )
  # write to DB (overwrite)
  dbWriteTable(con, Id(schema = 'fit', table = 'r_analysis_summary'), res, overwrite = TRUE)
  message('Wrote fit.r_analysis_summary (', nrow(res), ' rows)')
} else {
  message('No data available to compute analysis summary')
}

# Close connection
dbDisconnect(con)
