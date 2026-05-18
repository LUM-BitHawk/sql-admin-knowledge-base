# Get-SQLDatabaseOverview

## Zweck

Liefert eine **Gesamtübersicht aller Datenbanken** auf einem SQL Server mit Besitzer, Grösse, Kompatibilitätsstufe und dem Datum der letzten Full- sowie Log-Sicherung. Ideal für tägliche Checks, Audit-Dokumentation und Backup-Monitoring.

---

## Abfrage

```sql
SELECT
    d.name                                          AS DatabaseName,
    SUSER_SNAME(d.owner_sid)                        AS OwnerName,
    d.database_id                                   AS DatabaseId,
    d.state_desc                                    AS [State],
    d.recovery_model_desc                           AS RecoveryModel,
    d.compatibility_level                           AS CompatLevel,

    -- Grösse: Summe aller Datendateien (ROWS) und Log-Dateien
    (SELECT SUM(mf.size) * 8 / 1024
     FROM sys.master_files mf
     WHERE mf.database_id = d.database_id
       AND mf.type = 0                             -- ROWS (Daten)
    )                                               AS DataSizeMB,
    (SELECT SUM(mf.size) * 8 / 1024
     FROM sys.master_files mf
     WHERE mf.database_id = d.database_id
       AND mf.type = 1                             -- LOG
    )                                               AS LogSizeMB,

    -- Backup-Daten: ein Scan auf backupset reicht
    bk.LastFullBackup,
    bk.LastLogBackup,
    bk.LastDiffBackup,
    -- Tage seit dem letzten Full-Backup
    DATEDIFF(DAY, bk.LastFullBackup, GETDATE())     AS DaysSinceFullBackup

FROM sys.databases AS d
LEFT JOIN (
    SELECT
        database_name,
        MAX(CASE WHEN type = 'D' THEN backup_finish_date END) AS LastFullBackup,
        MAX(CASE WHEN type = 'L' THEN backup_finish_date END) AS LastLogBackup,
        MAX(CASE WHEN type = 'I' THEN backup_finish_date END) AS LastDiffBackup
    FROM msdb.dbo.backupset
    GROUP BY database_name
) AS bk
    ON d.name = bk.database_name
ORDER BY d.name;
```

---

## PowerShell-Skript mit CSV-Export

Das folgende Skript führt die optimierte Abfrage aus und exportiert das Ergebnis als CSV nach `C:\Temp`. Der Dateiname enthält automatisch den **SQL-Instanznamen** und einen Zeitstempel.

```powershell
#Requires -Version 5.1
# ============================================================
# Get-SQLDatabaseOverview.ps1
# Exportiert eine DB-Übersicht als CSV nach C:\Temp
# ============================================================

# --- Parameter ---
param(
    [string]$SqlInstance = $env:COMPUTERNAME  # Standard: lokale Default-Instanz
)

# --- Zielverzeichnis sicherstellen ---
$ExportPath = 'C:\Temp'
if (-not (Test-Path -Path $ExportPath)) {
    New-Item -Path $ExportPath -ItemType Directory -Force | Out-Null
}

# --- Instanzname für Dateinamen bereinigen (Backslash ersetzen) ---
$SafeInstanceName = $SqlInstance -replace '\\', '_'
$Timestamp        = Get-Date -Format 'yyyyMMdd_HHmmss'
$CsvFile          = Join-Path -Path $ExportPath `
                    -ChildPath "DBOverview_${SafeInstanceName}_${Timestamp}.csv"

# --- SQL-Abfrage (optimierte Version) ---
$Query = @"
SELECT
    @@SERVERNAME                                        AS InstanceName,
    d.name                                              AS DatabaseName,
    SUSER_SNAME(d.owner_sid)                            AS OwnerName,
    d.database_id                                       AS DatabaseId,
    d.state_desc                                        AS [State],
    d.recovery_model_desc                               AS RecoveryModel,
    d.compatibility_level                               AS CompatLevel,
    (SELECT SUM(mf.size) * 8 / 1024
     FROM sys.master_files mf
     WHERE mf.database_id = d.database_id
       AND mf.type = 0
    )                                                   AS DataSizeMB,
    (SELECT SUM(mf.size) * 8 / 1024
     FROM sys.master_files mf
     WHERE mf.database_id = d.database_id
       AND mf.type = 1
    )                                                   AS LogSizeMB,
    bk.LastFullBackup,
    bk.LastLogBackup,
    bk.LastDiffBackup,
    DATEDIFF(DAY, bk.LastFullBackup, GETDATE())         AS DaysSinceFullBackup
FROM sys.databases AS d
LEFT JOIN (
    SELECT
        database_name,
        MAX(CASE WHEN type = 'D' THEN backup_finish_date END) AS LastFullBackup,
        MAX(CASE WHEN type = 'L' THEN backup_finish_date END) AS LastLogBackup,
        MAX(CASE WHEN type = 'I' THEN backup_finish_date END) AS LastDiffBackup
    FROM msdb.dbo.backupset
    GROUP BY database_name
) AS bk
    ON d.name = bk.database_name
ORDER BY d.name;
"@

# --- Ausführung & Export ---
try {
    $Results = Invoke-Sqlcmd -ServerInstance $SqlInstance `
                             -Query $Query `
                             -QueryTimeout 60 `
                             -ErrorAction Stop

    $Results | Export-Csv -Path $CsvFile `
                          -Delimiter ';' `
                          -NoTypeInformation `
                          -Encoding UTF8

    Write-Host "Export erfolgreich: $CsvFile ($($Results.Count) Datenbanken)" `
               -ForegroundColor Green
}
catch {
    Write-Error "Fehler bei der Abfrage auf '$SqlInstance': $_"
    exit 1
}
```

### Aufruf-Beispiele

```powershell
# Lokale Default-Instanz
.\Get-SQLDatabaseOverview.ps1

# Benannte Instanz
.\Get-SQLDatabaseOverview.ps1 -SqlInstance "SERVER01\SQL2019"

# Remote-Server
.\Get-SQLDatabaseOverview.ps1 -SqlInstance "SQLPROD01"
```

### Erzeugte Datei

| Beispiel-Instanz | Dateiname |
|---|---|
| `SQLPROD01` | `C:\Temp\DBOverview_SQLPROD01_20260518_143022.csv` |
| `SERVER01\SQL2019` | `C:\Temp\DBOverview_SERVER01_SQL2019_20260518_143022.csv` |

Die CSV verwendet Semikolon als Trennzeichen und UTF-8-Encoding für problemlosen Import in Excel.

### Voraussetzung: SqlServer-Modul

```powershell
# Falls Invoke-Sqlcmd nicht verfügbar ist:
Install-Module -Name SqlServer -Scope CurrentUser -Force
Import-Module SqlServer
```

---

## Beispielausgabe

| DatabaseName | OwnerName | State | RecoveryModel | DataSizeMB | LogSizeMB | LastFullBackup | DaysSinceFullBackup |
|---|---|---|---|---|---|---|---|
| AppDB | sa | ONLINE | FULL | 2048 | 512 | 2026-05-17 22:00 | 1 |
| ArchiveDB | DOMAIN\sqladmin | ONLINE | SIMPLE | 15360 | 256 | 2026-05-10 03:00 | 8 |
| TestDB | sa | ONLINE | SIMPLE | 64 | 8 | NULL | NULL |

## Voraussetzungen

- SQL Server 2008 oder höher
- Berechtigung: `VIEW ANY DEFINITION` und Lesezugriff auf `msdb.dbo.backupset`
- `sys.master_files` liefert die allozierte Grösse, nicht den tatsächlich genutzten Platz

## Hinweise

- **Alloziert vs. Genutzt**: `sys.master_files.size` zeigt die allozierte Dateigrösse. Für den tatsächlich genutzten Platz pro DB muss `DBCC SQLPERF(LOGSPACE)` oder `sp_spaceused` im jeweiligen DB-Kontext ausgeführt werden.
- **Kein Backup = NULL**: Datenbanken ohne Eintrag in `backupset` zeigen `NULL` – das betrifft neue DBs oder solche, die noch nie gesichert wurden.
- **Recovery Model SIMPLE**: Bei `SIMPLE` sind Log-Backups nicht möglich – `LastLogBackup = NULL` ist hier erwartetes Verhalten.
- **Umlaut-Problem im Original**: Die `??`-Zeichen bei `Datenbankgrösse` und `Kompatibilitätsstufe` entstehen durch fehlende UTF-8-Unterstützung im Ausgabetool. ASCII-Aliase vermeiden das Problem.
