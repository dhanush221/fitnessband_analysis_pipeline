# simulate_day.ps1
# Progresses the Data Pipeline by exactly ONE day.
# Useful for demos or simulating a daily data feed for Power BI.

Write-Host "--- Simulating One Day of Data Processing ---" -ForegroundColor Cyan

# 1. Run ETL in one-day mode (Processes the next available date)
Write-Host "Running ETL Step (Next Day)..."
py etl/pipeline.py --one-day

# check if pipeline succeeded/produced data? (Implicit via script output)

# 1.5 Run R Scoring Model to update Health Scores & Comparison for the new data
Write-Host "Recalculating Health Scores (R)..."
& "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" scripts/03_scoring_model.R
& "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" scripts/04_recommendations.R

# 2. Push the new incremental data to Postgres
# Note: pipeline.py updates state.json. to_postgres.py --incremental reads state.json.
Write-Host "Syncing to Database..."
py etl/to_postgres.py --incremental

Write-Host "--- Simulation Complete. Check Power BI! ---" -ForegroundColor Green
