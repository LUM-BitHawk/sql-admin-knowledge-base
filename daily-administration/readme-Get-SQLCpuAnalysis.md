# Get-SQLCpuAnalysis

## Zweck

Zwei Abfragen zur Analyse der **CPU-Auslastung auf einem SQL Server**:

1. **Top CPU Queries** – Die 10 teuersten Abfragen nach kumulierter CPU-Zeit.
2. **CPU nach Benutzer** – Aktuelle CPU-Last gruppiert nach Login.

Einsatz bei Performance-Problemen, Kapazitätsplanung oder zur Identifikation von Optimierungskandidaten.

---

## 1 – Top CPU Queries

```sql
SELECT TOP 10
    qs.last_execution_time                                      AS LastExecution,
    qs.execution_count                                          AS ExecCount,
    qs.total_worker_time                                        AS TotalCpuUs,
    -- Division-by-zero-sicher
    qs.total_worker_time  / NULLIF(qs.execution_count, 0)       AS AvgCpuUs,
    qs.last_worker_time                                         AS LastCpuUs,
    qs.total_elapsed_time / NULLIF(qs.execution_count, 0)       AS AvgElapsedUs,
    qs.total_logical_reads / NULLIF(qs.execution_count, 0)      AS AvgLogicalReads,
    -- Nur den relevanten Statement-Abschnitt extrahieren
    SUBSTRING(
        qt.[text],
        (qs.statement_start_offset / 2) + 1,
        (CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(qt.[text])
            ELSE qs.statement_end_offset
         END - qs.statement_start_offset) / 2 + 1
    )                                                           AS StatementText,
    -- Ausführungsplan als Bonus
    qp.query_plan                                               AS QueryPlan,
    DB_NAME(qt.dbid)                                            AS DatabaseName
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS qt
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
ORDER BY qs.total_worker_time DESC;
```

### Verbesserungen

| Thema | Original | Optimiert |
|---|---|---|
| Division by Zero | Kein Schutz | `NULLIF(execution_count, 0)` |
| Statement-Text | Ganzer Batch (`qt.text`) | `SUBSTRING` → nur das betroffene Statement |
| Ausführungsplan | fehlt | `CROSS APPLY sys.dm_exec_query_plan` → XML-Plan |
| Logical Reads | fehlt | `AvgLogicalReads` → zeigt I/O-Last |
| Datenbank | fehlt | `DB_NAME(qt.dbid)` → Zuordnung zur DB |
| Gesamt-CPU | fehlt | `TotalCpuUs` → Gesamtlast, nicht nur Durchschnitt |

> **Hinweis**: Alle Zeitwerte sind in **Mikrosekunden** (µs). Für Millisekunden durch 1000 teilen.

---

## 2 – CPU-Auslastung nach Benutzer

### Originalabfrage

```sql
SELECT
    login_name,
    SUM(cpu_time) AS total_cpu_time
FROM sys.dm_exec_sessions s
INNER JOIN sys.dm_exec_requests r
    ON s.session_id = r.session_id
GROUP BY login_name
ORDER BY total_cpu_time DESC;
```

### Optimierte Abfrage

```sql
SELECT
    s.login_name                        AS LoginName,
    COUNT(DISTINCT s.session_id)        AS SessionCount,
    COUNT(r.request_id)                 AS ActiveRequests,
    SUM(r.cpu_time)                     AS TotalCpuMs,
    SUM(r.total_elapsed_time)           AS TotalElapsedMs,
    SUM(r.logical_reads)               AS TotalLogicalReads,
    SUM(r.writes)                       AS TotalWrites,
    MAX(r.wait_type)                    AS CurrentWaitType
FROM sys.dm_exec_sessions AS s
INNER JOIN sys.dm_exec_requests AS r
    ON s.session_id = r.session_id
WHERE s.is_user_process = 1            -- Systemprozesse ausschließen
GROUP BY s.login_name
ORDER BY TotalCpuMs DESC;
```

### Verbesserungen

| Thema | Original | Optimiert |
|---|---|---|
| Systemprozesse | Enthalten | `is_user_process = 1` → nur Benutzer |
| Kontext | Nur CPU | + Session-Anzahl, aktive Requests, Reads, Writes |
| Wait-Typ | fehlt | `CurrentWaitType` → zeigt aktuelle Engpässe |
| Spalten-Aliase | Einfach | Konsistente ANSI-Aliase |

### Wichtig

Diese Abfrage zeigt nur **aktuell aktive Requests**. Benutzer ohne laufende Abfrage erscheinen nicht. Für die kumulative Session-CPU stattdessen `s.cpu_time` aus `sys.dm_exec_sessions` allein verwenden:

```sql
SELECT
    login_name              AS LoginName,
    COUNT(*)                AS SessionCount,
    SUM(cpu_time)           AS TotalSessionCpuMs
FROM sys.dm_exec_sessions
WHERE is_user_process = 1
GROUP BY login_name
ORDER BY TotalSessionCpuMs DESC;
```

---

## Voraussetzungen

- SQL Server 2008 oder höher
- Berechtigung: `VIEW SERVER STATE`
- DMV-Daten werden bei SQL-Server-Neustart zurückgesetzt

## Hinweise

- **Plan-Cache-Clearing**: `DBCC FREEPROCCACHE` setzt `dm_exec_query_stats` zurück – Werte gelten nur seit dem letzten Cache-Clear oder Neustart.
- **TOP 10 anpassen**: Für breitere Analysen `TOP 50` oder die Einschränkung ganz entfernen.
- **Ausführungsplan**: Die Spalte `QueryPlan` liefert XML – im SSMS per Klick als grafischen Plan öffnen.
- **Regelmäßiges Monitoring**: Ergebnisse periodisch in eine Protokolltabelle schreiben, um Trends über Neustarts hinweg zu erkennen.
