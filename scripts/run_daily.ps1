<#
.SYNOPSIS
  Run daily ETL and DB load for the next unprocessed date.

.DESCRIPTION
  Runs the one-day ETL (python etl/pipeline.py --one-day) and then loads the resulting
  processed files into Postgres (python etl/to_postgres.py --incremental).

  Output (stdout/stderr) is captured to logs/run_daily_YYYY-MM-DD_HH-mm-ss.log

.PARAMETER Python
  Path to the Python executable to use (defaults to `python` on PATH).
#>
param(
    [string]$Python = "python",
    [string]$RScript = ""
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$logDir = Join-Path $scriptDir '..\logs'
# create logs directory if missing
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$logDir = (Get-Item $logDir).FullName

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = Join-Path $logDir "run_daily_$timestamp.log"

Write-Output "Starting daily ETL at $(Get-Date)" | Tee-Object -FilePath $logFile -Append

# change to repository root (parent of scripts directory) so relative paths resolve
$root = (Get-Item (Join-Path $scriptDir '..')).FullName

try {
    Push-Location $root
    $pipelineScript = Join-Path $root 'etl\pipeline.py'
    $toPostgresScript = Join-Path $root 'etl\to_postgres.py'

    Write-Output "Checking Python executable: $Python --version" | Tee-Object -FilePath $logFile -Append
    & $Python --version 2>&1 | Tee-Object -FilePath $logFile -Append
    Write-Output "Exit code after --version: $LASTEXITCODE" | Tee-Object -FilePath $logFile -Append
    if ($LASTEXITCODE -ne 0) { throw "Python executable $Python failed to run --version (exit $LASTEXITCODE)" }

    Write-Output "Running: $Python $pipelineScript --one-day" | Tee-Object -FilePath $logFile -Append
    & $Python $pipelineScript --one-day 2>&1 | Tee-Object -FilePath $logFile -Append
    Write-Output "Exit code after pipeline: $LASTEXITCODE" | Tee-Object -FilePath $logFile -Append
    if ($LASTEXITCODE -ne 0) { throw "etl/pipeline.py failed with exit code $LASTEXITCODE" }

    Write-Output "Running: $Python $toPostgresScript --incremental" | Tee-Object -FilePath $logFile -Append
    & $Python $toPostgresScript --incremental 2>&1 | Tee-Object -FilePath $logFile -Append
    Write-Output "Exit code after to_postgres: $LASTEXITCODE" | Tee-Object -FilePath $logFile -Append
    if ($LASTEXITCODE -ne 0) { throw "etl/to_postgres.py failed with exit code $LASTEXITCODE" }

    # ------------------------------------------------------------------
    # R analysis export (optional)
    # Resolve Rscript path from parameter or from .env R_SCRIPT entry
    if (-not $RScript) {
        $envFile = Join-Path $root '.env'
        if (Test-Path $envFile) {
            $lines = Get-Content $envFile
            foreach ($line in $lines) {
                if ($line -match '^\s*R_SCRIPT\s*=\s*(.+)$') {
                    $val = $Matches[1].Trim()
                    $val = $val.Trim('"').Trim("'")
                    $RScript = $val
                    break
                }
            }
        }
    }

    if ($RScript) {
        Write-Output "Rscript resolved to: $RScript" | Tee-Object -FilePath $logFile -Append
        if (Test-Path $RScript) {
            $rScriptFile = Join-Path $root 'analysis/export_analysis_to_db.R'
            Write-Output "Running R: $RScript $rScriptFile" | Tee-Object -FilePath $logFile -Append
            & $RScript $rScriptFile 2>&1 | Tee-Object -FilePath $logFile -Append
            Write-Output "Exit code after Rscript: $LASTEXITCODE" | Tee-Object -FilePath $logFile -Append
            if ($LASTEXITCODE -ne 0) {
                "WARNING: R export failed (exit $LASTEXITCODE), check log" | Tee-Object -FilePath $logFile -Append
            } else {
                "R export completed successfully" | Tee-Object -FilePath $logFile -Append
            }
        } else {
            "WARNING: Resolved Rscript path does not exist: $RScript - skipping R export" | Tee-Object -FilePath $logFile -Append
        }
    } else {
        "No Rscript configured; skipping R export" | Tee-Object -FilePath $logFile -Append
    }

    "SUCCESS: Completed run at $(Get-Date)" | Tee-Object -FilePath $logFile -Append
    exit 0
}
catch {
    "ERROR: $($_.Exception.Message)" | Tee-Object -FilePath $logFile -Append
    exit 1
}
finally {
    try { Pop-Location } catch { }
}