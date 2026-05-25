$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$dbPath = Join-Path $projectRoot "db.sqlite3"
$backupDir = Join-Path $projectRoot "backups"

if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupPath = Join-Path $backupDir "db_backup_$timestamp.sqlite3"

Copy-Item -Path $dbPath -Destination $backupPath -Force
Write-Output "Backup created: $backupPath"
