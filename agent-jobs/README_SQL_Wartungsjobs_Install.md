# BitHawk SQL Wartungsjobs – Komplettes Installations-Paket (ohne VEEAM Plugin)

Dieses SQL-Skript richtet auf einem SQL Server eine vollstaendige Wartungs- und Backup-Umgebung fuer SLA-Kunden ein, die kein VEEAM Plugin verwenden. Es erstellt einen dedizierten SQL-Login, aktiviert benoetigte Server-Optionen und installiert neun automatisierte Jobs fuer Backup, Wartung und Reporting. Alle Backups werden auf `S:\SQLBackup\` abgelegt.

---

## 🛠️ Verwendung

Nach der Installation laufen alle neun Jobs automatisch gemaess Zeitplan. Fuer manuelle Aktionen:

**Einzelnen Job manuell starten:**

```sql
EXEC msdb.dbo.sp_start_job N'BitHawk_Backup_Full_Wochenende';
```

**QueryStore-Bericht abfragen:**

```sql
SELECT DatabaseName, ReportType, LEFT(QueryText, 120) AS QueryText,
       AvgCPUms, AvgDurationMs, ExecutionCount, AvgWaitCategory, AvgWaitTimeMs
FROM   msdb.dbo.BitHawk_QueryStore_Report
WHERE  CAST(ReportDate AS DATE) = CAST(GETDATE() AS DATE)
ORDER BY ReportDate DESC, AvgCPUms DESC;
```

**Alle BitHawk-Jobs mit Status pruefen:**

```sql
SELECT j.name, j.enabled, sp.name AS Owner, j.date_created
FROM   msdb.dbo.sysjobs j
JOIN   master.sys.server_principals sp ON j.owner_sid = sp.sid
WHERE  j.name LIKE N'BitHawk%'
ORDER BY j.name;
```

---

## Architektur

Das Skript durchlaeuft 15 Phasen sequenziell und installiert eine komplette Wochenablauf-Kette:

```
PHASE 1  – Voraussetzungspruefung (Agent-Status, SQL-Version)
PHASE 2  – SQL Login "BHSQLJobRun" anlegen (32-Zeichen-Passwort)
PHASE 3  – sysadmin + msdb-Rollen zuweisen
PHASE 4  – xp_cmdshell aktivieren
PHASE 5  – Berichtstabelle BitHawk_QueryStore_Report anlegen
     │
     ▼  Wochenablauf der 9 Jobs:
┌─────────────────────────────────────────────────────────────────┐
│  SAMSTAG                                                        │
│  00:00  Job 1 – Full Backup aller Datenbanken                   │
│  04:00  Job 2 – DBCC CHECKDB (Integritaetspruefung)             │
│  08:00  Job 3 – Index Rebuild (Fragmentierung > 30%)            │
│  10:00  Job 4 – Statistics Update (FULLSCAN)                    │
│  11:00  Job 5 – QueryStore Wochenbericht                        │
│  12:00  Job 6 – Backup Cleanup (alte Dateien loeschen)          │
├─────────────────────────────────────────────────────────────────┤
│  SONNTAG                                                        │
│  00:00  Job 7 – Differenzielles Backup                          │
├─────────────────────────────────────────────────────────────────┤
│  MONTAG – FREITAG                                               │
│  06:00–22:00  Job 8 – T-Log Backup (stuendlich)                 │
├─────────────────────────────────────────────────────────────────┤
│  TAEGLICH                                                       │
│  23:00  Job 9 – T-Log Cleanup (> 7 Tage)                       │
└─────────────────────────────────────────────────────────────────┘
     │
PHASE 15 – Verifikation aller Objekte + Passwort-Ausgabe
```

Backup-Pfade: `S:\SQLBackup\Full\`, `S:\SQLBackup\Diff\`, `S:\SQLBackup\Log\<DBName>\`

Alle Jobs laufen unter dem Login `BHSQLJobRun` und protokollieren Fehler ins Windows Event-Log.

---

## 🚀 Installation

### Voraussetzungen

- **sysadmin**-Berechtigung auf dem Ziel-SQL-Server
- SQL Server Agent muss laufen (oder wird nach Aktivierung die Jobs ausfuehren)
- Backup-Ordner muessen vorhanden sein: `S:\SQLBackup\Full\`, `S:\SQLBackup\Diff\`, `S:\SQLBackup\Log\`

### Ausfuehrung

**Option A – SQL Server Management Studio (SSMS):**

1. Datei `BitHawk_SQL_Wartungsjobs_Install_V2.sql` in SSMS oeffnen.
2. Mit einem sysadmin-Konto verbinden.
3. Skript mit **F5** ausfuehren.
4. Ausgabe im Meldungsfenster pruefen – bei Erfolg erscheinen `[OK]`-Meldungen fuer jede Phase.
5. **Wichtig:** Das generierte Passwort fuer `BHSQLJobRun` wird nur einmal angezeigt — sofort in KeePass oder BitHawk Vault sichern.

**Option B – sqlcmd:**

```cmd
sqlcmd -S ServerName\Instanz -E -i BitHawk_SQL_Wartungsjobs_Install_V2.sql
```

### Nach der Installation

1. Backup-Ordner anlegen (falls nicht vorhanden): `S:\SQLBackup\Full`, `\Diff`, `\Log`
2. Query Store auf gewuenschten Datenbanken aktivieren (siehe Anhang A im Skript)
3. Test-Lauf: `BitHawk_Backup_Full_Wochenende` manuell starten

---

### Komponenten

| # | Job-Name | Zeitplan | Beschreibung |
|---|---|---|---|
| 1 | `BitHawk_Backup_Full_Wochenende` | Sa 00:00 | Vollstaendiges komprimiertes Backup aller Online-Datenbanken mit Checksumme. |
| 2 | `BitHawk_Integrity_Check_Samstag` | Sa 04:00 | `DBCC CHECKDB` mit `DATA_PURITY` und `ALL_ERRORMSGS` auf allen Online-Datenbanken. |
| 3 | `BitHawk_Index_Rebuild_Samstag` | Sa 08:00 | Rebuild aller Indizes mit Fragmentierung > 30% (`ONLINE=ON`, `SORT_IN_TEMPDB=ON`). |
| 4 | `BitHawk_Statistics_Update_Samstag` | Sa 10:00 | `UPDATE STATISTICS` mit `FULLSCAN` auf allen Benutzertabellen. |
| 5 | `BitHawk_QueryStore_Bericht_Samstag` | Sa 11:00 | Sammelt Top-CPU-Queries, Plan-Regressionen und Wait-Statistiken aus dem QueryStore. |
| 6 | `BitHawk_Backup_Cleanup_Samstag` | Sa 12:00 | Loescht Full-Backups > 14 Tage, Diff-Backups > 7 Tage, T-Logs > 7 Tage, Historie > 30 Tage. |
| 7 | `BitHawk_Backup_Diff_Sonntag` | So 00:00 | Differenzielles komprimiertes Backup aller Online-Datenbanken. |
| 8 | `BitHawk_Backup_TLog_Stuendlich_Werktags` | Mo–Fr 06:00–22:00 | Stuendliches T-Log Backup aller Datenbanken mit FULL/BULK_LOGGED Recovery. |
| 9 | `BitHawk_Backup_TLog_Cleanup_Taeglich` | Taeglich 23:00 | Loescht T-Log Dateien aelter als 7 Tage aus `S:\SQLBackup\Log\`. |

**Weitere Objekte:**

| Objekt | Typ | Beschreibung |
|---|---|---|
| `BHSQLJobRun` | SQL Login | Dedizierter Service-Account mit sysadmin-Rolle. Fuehrt alle Jobs aus. |
| `BitHawk_QueryStore_Report` | Tabelle (msdb) | Speichert die woechentlichen QueryStore-Analysen. |

---

### Deinstallation

Der Anhang C im Skript enthaelt ein vollstaendiges Deinstallations-Skript. Kurzfassung:

```sql
USE [msdb];
GO

-- Alle Jobs entfernen
EXEC msdb.dbo.sp_delete_job @job_name = N'BitHawk_Backup_Full_Wochenende',          @delete_unused_schedule = 1;
EXEC msdb.dbo.sp_delete_job @job_name = N'BitHawk_Integrity_Check_Samstag',          @delete_unused_schedule = 1;
EXEC msdb.dbo.sp_delete_job @job_name = N'BitHawk_Index_Rebuild_Samstag',            @delete_unused_schedule = 1;
EXEC msdb.dbo.sp_delete_job @job_name = N'BitHawk_Statistics_Update_Samstag',        @delete_unused_schedule = 1;
EXEC msdb.dbo.sp_delete_job @job_name = N'BitHawk_QueryStore_Bericht_Samstag',       @delete_unused_schedule = 1;
EXEC msdb.dbo.sp_delete_job @job_name = N'BitHawk_Backup_Cleanup_Samstag',           @delete_unused_schedule = 1;
EXEC msdb.dbo.sp_delete_job @job_name = N'BitHawk_Backup_Diff_Sonntag',             @delete_unused_schedule = 1;
EXEC msdb.dbo.sp_delete_job @job_name = N'BitHawk_Backup_TLog_Stuendlich_Werktags', @delete_unused_schedule = 1;
EXEC msdb.dbo.sp_delete_job @job_name = N'BitHawk_Backup_TLog_Cleanup_Taeglich',    @delete_unused_schedule = 1;

-- Login entfernen
USE [master];
DROP LOGIN [BHSQLJobRun];

-- Optional: Berichtstabelle entfernen
USE [msdb];
DROP TABLE dbo.BitHawk_QueryStore_Report;
```
