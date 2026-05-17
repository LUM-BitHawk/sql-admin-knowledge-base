# Get-SQLMemoryGrantAnalysis

## Zweck

Umfassende Echtzeitanalyse der **Memory Grants** auf einem SQL Server. Die Abfrage kombiniert Daten aus sechs DMVs, um pro aktiver Sitzung folgendes zu zeigen:

- Angeforderten, gewährten und tatsächlich genutzten Speicher
- Wait-Status und Blockierungen
- CPU, I/O und Laufzeit der Abfrage
- Serverweit verfügbare Grant-Ressourcen
- Ausführungsplan und Query-Text
- Session- und Verbindungsdetails (Login, Host, Programm)

Einsatz bei **Memory-Pressure-Situationen**, `RESOURCE_SEMAPHORE`-Waits oder wenn Abfragen auf Memory Grants warten.

---

## Abfrage

```sql
SELECT
    SYSDATETIME()                                   AS SnapshotTime,

    -- === Session & Request ===
    r.session_id                                    AS SessionId,
    r.request_id                                    AS RequestId,
    r.command                                       AS Command,
    r.status                                        AS RequestStatus,
    r.wait_type                                     AS WaitType,
    r.wait_time                                     AS WaitTimeMs,
    r.blocking_session_id                           AS BlockingSessionId,

    -- === Memory Grant (Session-Ebene) ===
    mg.request_time                                 AS GrantRequestTime,
    mg.grant_time                                   AS GrantTime,
    mg.requested_memory_kb / 1024                   AS RequestedMemoryMB,
    mg.granted_memory_kb   / 1024                   AS GrantedMemoryMB,
    mg.required_memory_kb  / 1024                   AS RequiredMemoryMB,
    mg.max_used_memory_kb  / 1024                   AS MaxUsedMemoryMB,
    mg.query_cost                                   AS QueryCost,
    mg.dop                                          AS DegreeOfParallelism,
    mg.timeout_sec                                  AS GrantTimeoutSec,
    mg.wait_time_ms                                 AS GrantWaitTimeMs,
    CASE mg.is_next_candidate
        WHEN 1 THEN 'Yes'
        WHEN 0 THEN 'No'
        ELSE   'Granted'
    END                                             AS NextCandidate,

    -- === Performance-Metriken ===
    r.cpu_time                                      AS CpuTimeMs,
    r.total_elapsed_time                            AS ElapsedTimeMs,
    r.reads                                         AS PhysicalReads,
    r.writes                                        AS PhysicalWrites,
    r.logical_reads                                 AS LogicalReads,
    r.row_count                                     AS RowCount,

    -- === Query-Text: nur das aktive Statement ===
    SUBSTRING(
        q.[text],
        (r.statement_start_offset / 2) + 1,
        (CASE r.statement_end_offset
            WHEN -1 THEN DATALENGTH(q.[text])
            ELSE r.statement_end_offset
         END - r.statement_start_offset) / 2 + 1
    )                                               AS StatementText,

    -- === Ausführungsplan ===
    qp.query_plan                                   AS QueryPlan,

    -- === Server-weite Semaphore-Statistiken ===
    rs.pool_id                                      AS ResourcePoolId,
    rs.resource_semaphore_id                        AS SemaphoreId,
    rs.target_memory_kb      / 1024                 AS SrvTargetGrantMB,
    rs.max_target_memory_kb  / 1024                 AS SrvMaxTargetGrantMB,
    rs.total_memory_kb       / 1024                 AS SrvTotalSemaphoreMemMB,
    rs.available_memory_kb   / 1024                 AS SrvAvailableGrantMB,
    rs.granted_memory_kb     / 1024                 AS SrvTotalGrantedMB,
    rs.used_memory_kb        / 1024                 AS SrvUsedGrantedMB,
    rs.grantee_count                                AS SrvGranteeCount,
    rs.waiter_count                                 AS SrvWaiterCount,
    rs.timeout_error_count                          AS SrvTimeoutErrors,
    rs.forced_grant_count                           AS SrvForcedGrants,

    -- === Session-/Verbindungsdetails ===
    DB_NAME(r.database_id)                          AS DatabaseName,
    s.login_name                                    AS LoginName,
    s.host_name                                     AS HostName,
    s.program_name                                  AS ProgramName,
    c.client_net_address                            AS ClientIP,
    s.login_time                                    AS LoginTime,
    s.last_request_start_time                       AS LastRequestStart,
    c.connect_time                                  AS ConnectTime

FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s
    ON r.session_id = s.session_id
INNER JOIN sys.dm_exec_connections AS c
    ON r.session_id = c.session_id
LEFT JOIN sys.dm_exec_query_memory_grants AS mg
    ON r.session_id = mg.session_id
   AND r.request_id = mg.request_id
LEFT JOIN sys.dm_exec_query_resource_semaphores AS rs
    ON mg.resource_semaphore_id = rs.resource_semaphore_id
   AND mg.pool_id = rs.pool_id          -- Resource-Governor-sicher
INNER JOIN sys.databases AS d
    ON r.database_id = d.database_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS q
OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) AS qp
WHERE s.is_user_process = 1
ORDER BY mg.granted_memory_kb DESC, r.cpu_time DESC
OPTION (MAXDOP 1, LOOP JOIN);
```

---


## Beteiligte DMVs

| DMV | Inhalt |
|---|---|
| `sys.dm_exec_requests` | Aktuell laufende Requests (CPU, I/O, Waits) |
| `sys.dm_exec_sessions` | Alle Sitzungen (Login, Host, Programm) |
| `sys.dm_exec_connections` | Netzwerk-Verbindungsdetails |
| `sys.dm_exec_query_memory_grants` | Memory-Grant-Status pro Abfrage |
| `sys.dm_exec_query_resource_semaphores` | Serverweite Semaphore-Ressourcen |
| `sys.dm_exec_sql_text()` | SQL-Text aus dem Plan-Cache |
| `sys.dm_exec_query_plan()` | XML-Ausführungsplan |

---

## Voraussetzungen

- SQL Server 2008 oder höher (für `SYSDATETIME()`: 2008+)
- Berechtigung: `VIEW SERVER STATE`
- Nur **aktive Requests** werden angezeigt – abgeschlossene Abfragen erscheinen nicht

## Hinweise

- **`OPTION (MAXDOP 1, LOOP JOIN)`** verhindert, dass die DMV-Abfrage selbst parallelisiert wird und reduziert den Overhead auf dem ohnehin belasteten Server.
- **`RESOURCE_SEMAPHORE`-Waits**: Wenn `SrvWaiterCount > 0`, warten Abfragen auf Speicher – ein klares Zeichen für Memory Pressure.
- **Granted vs. Max Used**: Grosse Differenz zwischen `GrantedMemoryMB` und `MaxUsedMemoryMB` deutet auf überschätzte Grants hin → Statistiken aktualisieren.
- **Kein Memory Grant nötig**: Einfache Abfragen ohne Sort/Hash erhalten keinen Grant und erscheinen im Original nicht – die optimierte Version zeigt sie dank `LEFT JOIN`.
- **Regelmässiges Monitoring**: Ergebnisse periodisch in eine Staging-Tabelle schreiben, um Muster über die Zeit zu erkennen.
