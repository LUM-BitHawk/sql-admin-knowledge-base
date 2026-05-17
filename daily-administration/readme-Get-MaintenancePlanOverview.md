# Get-MaintenancePlanOverview

## Zweck

Listet alle **aktiven SQL Server Maintenance Plans** mit ihren Subplänen und zugehörigen Agent-Jobs auf. Dient als schnelle Übersicht bei Dokumentation, Audits oder Fehlersuche in der Wartungsplanung.

## Abfrage

```sql
SELECT
    p.name                          AS MaintenancePlan,
    p.[description]                 AS PlanDescription,
    SUSER_SNAME(p.owner_sid)       AS PlanOwner,
    sp.subplan_name                 AS SubplanName,
    sp.subplan_description          AS SubplanDescription,
    j.name                          AS JobName,
    j.[description]                 AS JobDescription,
    j.[enabled]                     AS JobEnabled,
    -- Letzte Ausführung und Status
    h.run_date                      AS LastRunDate,
    h.run_time                      AS LastRunTime,
    CASE h.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Canceled'
        WHEN 4 THEN 'In Progress'
        ELSE 'Unknown'
    END                             AS LastRunStatus,
    -- Nächste geplante Ausführung
    js.next_run_date                AS NextRunDate,
    js.next_run_time                AS NextRunTime
FROM msdb.dbo.sysmaintplan_plans AS p
INNER JOIN msdb.dbo.sysmaintplan_subplans AS sp
    ON p.id = sp.plan_id
INNER JOIN msdb.dbo.sysjobs AS j
    ON sp.job_id = j.job_id
LEFT JOIN msdb.dbo.sysjobschedules AS js
    ON j.job_id = js.job_id
OUTER APPLY (
    SELECT TOP 1
        run_date,
        run_time,
        run_status
    FROM msdb.dbo.sysjobhistory
    WHERE job_id = j.job_id
      AND step_id = 0          -- Nur Gesamt-Ergebnis des Jobs
    ORDER BY instance_id DESC
) AS h
WHERE j.[enabled] = 1
ORDER BY p.name, sp.subplan_name;
```

### Hinweis zu den Alias-Namen

String-Aliase (`'Maintenance Plan'`) funktionieren in SQL Server, sind aber kein ANSI-Standard und können in manchen Tools Probleme verursachen. Besser: Aliase ohne Anführungszeichen oder mit eckigen Klammern (`[Maintenance Plan]`), wenn Leerzeichen nötig sind.

## Beispielausgabe

| MaintenancePlan | PlanOwner | SubplanName | JobName | LastRunStatus | NextRunDate |
|---|---|---|---|---|---|
| DB_Maintenance | sa | Full Backup | DB_Maintenance.Full Backup | Succeeded | 20260518 |
| DB_Maintenance | sa | Index Rebuild | DB_Maintenance.Index Rebuild | Succeeded | 20260518 |
| LogBackup_Plan | DOMAIN\sqladmin | Log Backup | LogBackup_Plan.Log Backup | Failed | 20260517 |

## Voraussetzungen

- SQL Server 2008 oder höher
- Berechtigung: Mitglied der Rolle **SQLAgentReaderRole** in `msdb` (oder `sysadmin`)
- SQL Server Agent muss aktiv sein

## Hinweise

- **Deaktivierte Jobs**: Die `WHERE`-Klausel filtert auf `enabled = 1`. Zum Anzeigen aller Jobs (auch deaktivierter) die Bedingung entfernen oder `j.[enabled]` als Spalte auswerten.
- **Keine Maintenance Plans vorhanden?** Die Tabellen `sysmaintplan_*` existieren nur, wenn mindestens ein Plan jemals erstellt wurde.
- **History-Tiefe**: `sysjobhistory` wird standardmäßig auf 1000 Zeilen pro Job begrenzt. Bei Bedarf unter SQL Server Agent → Properties → History anpassen.
- **SSIS-basierte Pläne**: Ab SQL Server 2012 nutzen Maintenance Plans intern SSIS-Pakete. Die Abfrage zeigt die Job-Ebene – für Paketdetails zusätzlich `msdb.dbo.sysssispackages` abfragen.
