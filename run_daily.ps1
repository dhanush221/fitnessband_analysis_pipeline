# run_daily.ps1
# Orchestrates daily incremental ETL -> DB upsert -> R scoring -> Power BI trigger

# Load environment (requires powershell 7 or Windows PowerShell with dotnet)
if (Test-Path .env) {
  Get-Content .env | ForEach-Object {
    if ($_ -match '^(\w+)=') { $parts = $_ -split '='; Set-Item -Path env:$($parts[0]) -Value ($parts[1]) }
  }
}

# Read last processed date from etl/state.json
$stateFile = 'etl/state.json'
$since = $null
if (Test-Path $stateFile) {
  $json = Get-Content $stateFile -Raw | ConvertFrom-Json
  if ($json.last_date_processed) { $since = $json.last_date_processed }
}

if ($since) {
  Write-Output "Running incremental ETL since $since"
  & 'C:\Python313\python.exe' etl/pipeline.py --since $since
  & 'C:\Python313\python.exe' -m pip install --quiet -r requirements.txt
  Set-Item -Path env:WRITE_TO_DB -Value 'true'
  & 'C:\Python313\python.exe' etl/to_postgres.py --incremental
} else {
  Write-Output "No last run found — running full ETL"
  & 'C:\Python313\python.exe' etl/pipeline.py
  & 'C:\Python313\python.exe' -m pip install --quiet -r requirements.txt
  Set-Item -Path env:WRITE_TO_DB -Value 'true'
  & 'C:\Python313\python.exe' etl/to_postgres.py
}

# Run R scoring to update composite score and optionally write to DB
& 'C:\Program Files\R\R-4.5.2\bin\Rscript.exe' -e "source('scripts/03_scoring_model.R')"

# Trigger Power BI refresh if configured
& 'C:\Python313\python.exe' etl/powerbi_trigger.py

Write-Output 'Daily run complete.'
