# BitHawk SQL Wartungsjobs – SLA Installations-Paket

Dieses SQL-Skript richtet auf einem SQL Server eine komplette Wartungsumgebung fuer SLA-Kunden ein. Es erstellt einen dedizierten SQL-Login, aktiviert benoetigte Server-Optionen und installiert drei automatisierte Wartungsjobs, die woechentlich am Samstag ausfuehren. Zusaetzlich wird eine Berichtstabelle fuer QueryStore-Analysen angelegt.

---

## 🛠️ Verwendung

Nach der Installation laufen die Jobs automatisch gemaess Zeitplan. Fuer manuelle Aktionen:

**Job manuell starten:**

```sql
EXEC msdb.dbo.sp_start_job N'BitHawk_Integrity_Check_Samstag';
EXEC msdb.dbo.sp_start_job N'BitHawk_Statistics_Update_Samstag';
EXEC msdb.dbo.sp_start_job N'BitHawk_QueryStore_Bericht_Samstag';
```

**QueryStore-Bericht abfragen:**

```sql
SELECT DatabaseName, ReportType, LEFT(QueryText, 120) AS QueryText,
       AvgCPUms, AvgDurationMs, ExecutionCount, AvgWaitCategory, AvgWaitTimeMs
FROM   msdb.dbo.BitHawk_QueryStore_Report
WHERE  CAST(ReportDate AS DATE) = CAST(GETDATE() AS DATE)
ORDER BY ReportDate DESC, AvgCPUms DESC;
```

**Installierte Jobs pruefen:**

```sql
SELECT j.name, j.enabled, sp.name AS Owner, j.date_created
FROM   msdb.dbo.sysjobs j
JOIN   master.sys.server_principals sp ON j.owner_sid = sp.sid
WHERE  j.name LIKE N'BitHawk%'
ORDER BY j.name;
```

---

## Architektur

Das Skript durchlaeuft mehrere Phasen sequenziell:

```
PHASE 1 – Voraussetzungspruefung (Agent-Status, Version)
    │
PHASE 2 – SQL Login "BHSQLJobRun" anlegen (32-Zeichen-Passwort)
    │
PHASE 3 – sysadmin + msdb-Rollen zuweisen
    │
PHASE 4 – xp_cmdshell aktivieren
    │
PHASE 5 – Berichtstabelle BitHawk_QueryStore_Report anlegen
    │
PHASE 6 – Job 1: Integrity Check         ➜ Samstag 04:00
    │
PHASE 7 – Job 2: Statistics Update       ➜ Samstag 10:00
    │
PHASE 8 – Job 3: QueryStore Bericht      ➜ Samstag 11:00
    │
PHASE 9 – Verifikation aller Objekte
    │
    └── Passwort-Ausgabe (einmalig, sicher aufbewahren!)
```

Alle Jobs laufen unter dem Login `BHSQLJobRun` und protokollieren Fehler ins Windows Event-Log.

---

## 🚀 Installation

### Voraussetzungen

- **sysadmin**-Berechtigung auf dem Ziel-SQL-Server
- SQL Server Agent muss laufen (oder wird nach Aktivierung die Jobs ausfuehren)
- Backup-Ordner muss ggf. vorab angelegt werden: `S:\SQLBackup\Full`, `Diff`, `Log`

### Ausfuehrung

**Option A – SQL Server Management Studio (SSMS):**

1. Datei `BitHawk_SQL_Wartungsjobs_SLA_Install_V1.sql` in SSMS oeffnen.
2. Mit einem sysadmin-Konto verbinden.
3. Skript mit **F5** ausfuehren.
4. Ausgabe im Meldungsfenster pruefen – bei Erfolg erscheinen `[OK]`-Meldungen fuer jede Phase.
5. **Wichtig:** Das generierte Passwort fuer `BHSQLJobRun` wird nur einmal angezeigt — sofort in KeePass oder BitHawk Vault sichern.

**Option B – sqlcmd:**

```cmd
sqlcmd -S ServerName\Instanz -E -i BitHawk_SQL_Wartungsjobs_SLA_Install_V1.sql
```

### Nach der Installation

1. Backup-Ordner anlegen: `S:\SQLBackup\Full`, `\Diff`, `\Log`
2. Query Store auf gewuenschten Datenbanken aktivieren (siehe Anhang A im Skript)
3. Optional einen Job manuell starten, um die Funktion zu testen

---

### Komponenten

| Objekt | Typ | Zeitplan | Beschreibung |
|---|---|---|---|
| `BHSQLJobRun` | SQL Login | – | Dedizierter Service-Account mit sysadmin-Rolle. Fuehrt alle Wartungsjobs aus. |
| `BitHawk_Integrity_Check_Samstag` | SQL Agent Job | Sa 04:00 | Fuehrt `DBCC CHECKDB` mit `DATA_PURITY` und `ALL_ERRORMSGS` auf allen Online-Datenbanken aus. |
| `BitHawk_Statistics_Update_Samstag` | SQL Agent Job | Sa 10:00 | Aktualisiert Statistiken aller Benutzertabellen mit `FULLSCAN` auf allen Datenbanken. |
| `BitHawk_QueryStore_Bericht_Samstag` | SQL Agent Job | Sa 11:00 | Sammelt Top-CPU-Queries, Plan-Regressionen und Wait-Statistiken aus dem QueryStore und persistiert sie in der Berichtstabelle. |
| `BitHawk_QueryStore_Report` | Tabelle (msdb) | – | Speichert die woechentlichen QueryStore-Analysen. Index auf `ReportDate` und `DatabaseName`. |

---

### Deinstallation

Der Anhang C im Skript enthaelt ein vollstaendiges Deinstallations-Skript. Kurzfassung:

```sql
-- Jobs entfernen
EXEC msdb.dbo.sp_delete_job @job_name = N'BitHawk_Integrity_Check_Samstag', @delete_unused_schedule = 1;
EXEC msdb.dbo.sp_delete_job @job_name = N'BitHawk_Statistics_Update_Samstag', @delete_unused_schedule = 1;
EXEC msdb.dbo.sp_delete_job @job_name = N'BitHawk_QueryStore_Bericht_Samstag', @delete_unused_schedule = 1;

-- Login entfernen
USE [master];
DROP LOGIN [BHSQLJobRun];

-- Optional: Berichtstabelle entfernen
USE [msdb];
DROP TABLE dbo.BitHawk_QueryStore_Report;
```
