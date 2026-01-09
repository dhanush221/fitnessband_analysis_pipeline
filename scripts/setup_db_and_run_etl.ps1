<#
.SYNOPSIS
  Create DB (if missing), apply schema, run ETL, push to Postgres, and verify results.
.DESCRIPTION
  This script reads `.env` from the repo root and sets environment variables for the session.
  It will:
   - create the database if it does not exist (requires that the configured PG user has CREATE DB privileges)
   - apply `sql/create_tables.sql` against the target DB
   - run `etl/pipeline.py` and `etl/to_postgres.py --incremental`
   - run verification queries against the `fit` schema
.PARAMETER CreateUser
  Optional switch to create a new DB user (not enabled by default).
.EXAMPLE
  .\setup_db_and_run_etl.ps1
#>

[CmdletBinding()]
param(
    [switch]$CreateUser,
    [string]$NewUserName = "fituser",
    [string]$NewUserPassword = "ChangeMe123!"
)

# Resolve repository root (script is in scripts/)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot = Resolve-Path "$scriptDir\.."
$envPath = Join-Path $repoRoot '.env'

if (-not (Test-Path $envPath)) {
    Write-Error "No .env file found at $envPath. Create one first or populate variables manually."
    exit 1
}

# Parse .env and set session env vars
Get-Content $envPath | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq '' -or $line.StartsWith('#')) { return }
    $parts = $line -split '=', 2
    if ($parts.Count -ne 2) { return }
    $k = $parts[0].Trim()
    $v = $parts[1].Trim().Trim('"')
    # Export for child processes using a safe method for dynamic names
    Set-Item -Path "Env:\$k" -Value $v
} 

# ease-of-use variables
$pgHost = $env:PG_HOST
$pgPort = $env:PG_PORT
$pgDb   = $env:PG_DB
$pgUser = $env:PG_USER
$pgPass = $env:PG_PASSWORD
$pythonExe = if ($env:PYTHON_EXE) { $env:PYTHON_EXE } else { 'python' }
$createTablesSql = Join-Path $repoRoot 'sql\create_tables.sql'

# Export password for psql use
if ($pgPass) { $env:PGPASSWORD = $pgPass }

Write-Host "Using DB: $pgUser@$($pgHost):$($pgPort)/$pgDb"

# Check whether the DB exists
$checkCmd = "SELECT 1 FROM pg_database WHERE datname='$pgDb';"
$exists = & psql -h $pgHost -p $pgPort -U $pgUser -tAc $checkCmd 2>&1
$exists = $exists.Trim()

if ($exists -ne '1') {
    Write-Host "Database '$pgDb' not found — attempting to create it..."
    try {
        & psql -h $pgHost -p $pgPort -U $pgUser -c "CREATE DATABASE \"$pgDb\";"
    } catch {
        Write-Error "Failed to create database. Check credentials and privileges. $_"
        exit 1
    }
} else {
    Write-Host "Database '$pgDb' already exists — skipping create."
}

# Optionally create a new low-privileged user
if ($CreateUser.IsPresent) {
    Write-Host "Creating user $NewUserName (if not exists)..."
    try {
        & psql -h $pgHost -p $pgPort -U $pgUser -c "DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$NewUserName') THEN CREATE ROLE $NewUserName LOGIN PASSWORD '$NewUserPassword'; END IF; END $$;"
        & psql -h $pgHost -p $pgPort -U $pgUser -c "GRANT CONNECT ON DATABASE \"$pgDb\" TO $NewUserName;"
        Write-Host "User provisioning attempted (check output for details)."
    } catch {
        Write-Warning "Failed to create/grant user: $_"
    }
}

# Apply schema
if (-not (Test-Path $createTablesSql)) {
    Write-Error "create_tables.sql not found at $createTablesSql"
    exit 1
}

Write-Host "Applying schema from $createTablesSql..."
try {
    & psql -h $pgHost -p $pgPort -U $pgUser -d $pgDb -f $createTablesSql
} catch {
    Write-Error "Schema apply failed: $_"
    exit 1
}

# Run ETL pipeline (full run)
Write-Host "Running ETL pipeline (etl/pipeline.py)..."
$etlExit = & $pythonExe "$repoRoot\etl\pipeline.py"
if ($LASTEXITCODE -ne 0) {
    Write-Error "etl/pipeline.py failed (exit code $LASTEXITCODE). Aborting."
    exit $LASTEXITCODE
}

# Push to Postgres (incremental)
if ($env:WRITE_TO_DB -eq 'true' -or $env:WRITE_TO_DB -eq 'True') {
    Write-Host "Writing processed data to Postgres (etl/to_postgres.py --incremental)..."
    $pushExit = & $pythonExe "$repoRoot\etl\to_postgres.py" --incremental
    if ($LASTEXITCODE -ne 0) {
        Write-Error "etl/to_postgres.py failed (exit code $LASTEXITCODE). Aborting."
        exit $LASTEXITCODE
    }
} else {
    Write-Host "WRITE_TO_DB is not true — skipping DB write."
}

# Verification queries
Write-Host "Schema and table verification:"
& psql -h $pgHost -p $pgPort -U $pgUser -d $pgDb -c "\dt fit.*"

Write-Host "Row counts (sample):"
& psql -h $pgHost -p $pgPort -U $pgUser -d $pgDb -c "SELECT 'daily_activity' AS table, COUNT(*) FROM fit.daily_activity;"
& psql -h $pgHost -p $pgPort -U $pgUser -d $pgDb -c "SELECT 'daily_sleep' AS table, COUNT(*) FROM fit.daily_sleep;"
& psql -h $pgHost -p $pgPort -U $pgUser -d $pgDb -c "SELECT 'user_summary' AS table, COUNT(*) FROM fit.user_summary;"
& psql -h $pgHost -p $pgPort -U $pgUser -d $pgDb -c "SELECT * FROM fit.etl_state ORDER BY last_run DESC LIMIT 5;"

Write-Host "Done. If any step failed, examine the logs above and re-run the failing command."