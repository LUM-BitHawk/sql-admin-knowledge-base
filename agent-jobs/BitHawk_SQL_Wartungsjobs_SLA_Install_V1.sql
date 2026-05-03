/*
================================================================================
  ____  _ _   _   _               _
 | __ )(_) |_| | | | __ ___      _| | __
 |  _ \| | __| |_| |/ _` \ \ /\ / / |/ /
 | |_) | | |_|  _  | (_| |\ V  V /|   <
 |____/|_|\__|_| |_|\__,_| \_/\_/ |_|\_\

 SQL Server – Installations-Paket für SLA Kunden nach dem Plugin Installation
===================================================================================
 Datei    : BitHawk_SQL_Wartungsjobs_SLA_Install_V12.sql
 Version  : 1.0
 Erstellt : 2026-04-07
 Autor    : BitHawk AG
 Ersteller: Marcel Luginbühl

  Inhalt (Reihenfolge):
   PHASE 1  – Voraussetzungspruefung
   PHASE 2  – SQL Login BHSQLJobRun anlegen (SQL Authentication)
   PHASE 3  – SysAdmin + msdb-Rollen zuweisen
   PHASE 4  – xp_cmdshell aktivieren
   PHASE 5  – QueryStore-Berichtstabelle anlegen
   PHASE 6  – Job 1  BitHawk_Integrity_Check_Samstag         (Sa 04:00)
   PHASE 7  – Job 2  BitHawk_Statistics_Update_Samstag       (Sa 10:00)
   PHASE 8  – Job 3  BitHawk_QueryStore_Bericht_Samstag      (Sa 11:00)
   PHASE 9  – Verifikation aller Jobs und Benutzer
   ANHANG A – Query Store aktivieren (auskommentiert)
   ANHANG B – Deinstallation (auskommentiert)

ACHTUNG: Alle andere Job müssen mit dem Lieferanten und Hersteller Abgeklärt werden!

 Ausfuehren:
   sqlcmd -S %ServerName\Instanz"-E -i BitHawk_SQL_Wartungsjobs_SLA_Install_V12.sql
   oder in SSMS oeffnen und mit F5 ausfuehren (als sysadmin).

 HINWEIS: Das generierte Passwort wird am Ende der Ausgabe angezeigt.
          Bitte sofort sicher aufbewahren (z.B. KeePass-Kunde / BitHawk Vault).
================================================================================
*/

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

PRINT '========================================================================';
PRINT '  BitHawk SQL Server – Komplettes Installations-Paket v2.0';
PRINT '  Start: ' + CONVERT(NVARCHAR(20), GETDATE(), 120);
PRINT '========================================================================';
PRINT '';
GO

-- ============================================================================
-- PHASE 1: Voraussetzungspruefung
-- ============================================================================
PRINT '--- PHASE 1: Voraussetzungspruefung ------------------------------------';
GO

USE [master];
GO

-- SQL Server Agent pruefen
IF NOT EXISTS (
    SELECT 1 FROM sys.dm_server_services
    WHERE  servicename LIKE 'SQL Server Agent%'
      AND  status_desc = 'Running'
)
    PRINT '[WARN] SQL Server Agent laeuft nicht. Jobs werden angelegt, starten aber erst wenn der Agent aktiv ist.';
ELSE
    PRINT '[OK]   SQL Server Agent laeuft.';

-- SQL Server Version anzeigen
PRINT '[INFO] ' + @@SERVERNAME + ' | ' + @@VERSION;
PRINT '';
GO

-- ============================================================================
-- PHASE 2: SQL Login BHSQLJobRun anlegen (SQL Authentication)
--          32-stelliges Passwort wird deterministisch aus Zufallsbytes erzeugt
-- ============================================================================
PRINT '--- PHASE 2: SQL Login BHSQLJobRun anlegen -----------------------------';
GO

USE [master];
GO

-- Passwort-Generierung: 32 Zeichen aus sicheren Zufallsbytes
-- Zeichensatz: A-Z a-z 0-9 ! @ # $ % & * - _ (SQL-kompatibel, keine Anführungszeichen)
DECLARE @pwd        NVARCHAR(64);
DECLARE @chars      NVARCHAR(80);
DECLARE @rnd        VARBINARY(64);
DECLARE @i          INT;
DECLARE @byte_val   INT;
DECLARE @charset_len INT;

SET @chars       = N'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%&*-_';
SET @charset_len = LEN(@chars);
SET @pwd         = N'';
SET @rnd         = CRYPT_GEN_RANDOM(64);   -- 64 kryptografisch sichere Zufallsbytes
SET @i           = 1;

WHILE @i <= 32
BEGIN
    SET @byte_val = CAST(SUBSTRING(@rnd, @i, 1) AS INT) % @charset_len + 1;
    SET @pwd      = @pwd + SUBSTRING(@chars, @byte_val, 1);
    SET @i        = @i + 1;
END;

-- Passwort in temporaere Tabelle schreiben (fuer spaetere Anzeige)
IF OBJECT_ID('tempdb..#BHPwd') IS NOT NULL DROP TABLE #BHPwd;
CREATE TABLE #BHPwd (pwd NVARCHAR(64));
INSERT INTO  #BHPwd VALUES (@pwd);

-- Login anlegen oder Passwort aktualisieren
IF EXISTS (
    SELECT 1 FROM sys.server_principals
    WHERE  name = N'BHSQLJobRun'
      AND  type = 'S'
)
BEGIN
    -- Login existiert bereits -> Passwort aktualisieren
    DECLARE @alter_sql NVARCHAR(300);
    SET @alter_sql = N'ALTER LOGIN [BHSQLJobRun] WITH PASSWORD = N''' + @pwd + N''';';
    EXEC sp_executesql @alter_sql;
    PRINT '[OK]   Login BHSQLJobRun existiert bereits – Passwort aktualisiert.';
END
ELSE
BEGIN
    DECLARE @create_sql NVARCHAR(400);
    SET @create_sql =
        N'CREATE LOGIN [BHSQLJobRun]'
      + N' WITH PASSWORD          = N''' + @pwd + N''','
      + N'      DEFAULT_DATABASE  = [master],'
      + N'      CHECK_EXPIRATION  = OFF,'
      + N'      CHECK_POLICY      = ON;';
    EXEC sp_executesql @create_sql;
    PRINT '[OK]   SQL Login BHSQLJobRun angelegt.';
END
GO

-- ============================================================================
-- PHASE 3: SysAdmin-Rolle und msdb-Rollen zuweisen
-- ============================================================================
PRINT '';
PRINT '--- PHASE 3: Rollen zuweisen -------------------------------------------';
GO

USE [master];
GO

-- SysAdmin
IF IS_SRVROLEMEMBER('sysadmin', 'BHSQLJobRun') = 0
BEGIN
    ALTER SERVER ROLE [sysadmin] ADD MEMBER [BHSQLJobRun];
    PRINT '[OK]   SysAdmin-Rolle zugewiesen.';
END
ELSE
    PRINT '[OK]   SysAdmin-Rolle bereits vorhanden.';
GO

-- msdb-Benutzer und Rollen
USE [msdb];
GO

IF NOT EXISTS (
    SELECT 1 FROM msdb.sys.database_principals
    WHERE  name = N'BHSQLJobRun'
)
BEGIN
    CREATE USER [BHSQLJobRun] FOR LOGIN [BHSQLJobRun];
    PRINT '[OK]   msdb-Benutzer BHSQLJobRun angelegt.';
END
ELSE
    PRINT '[OK]   msdb-Benutzer BHSQLJobRun bereits vorhanden.';
GO

-- SQLAgentOperatorRole: Jobs ausfuehren, History lesen
EXEC msdb.dbo.sp_addrolemember
    @rolename   = N'SQLAgentOperatorRole',
    @membername = N'BHSQLJobRun';

-- SQLAgentUserRole: Jobs erstellen und verwalten
EXEC msdb.dbo.sp_addrolemember
    @rolename   = N'SQLAgentUserRole',
    @membername = N'BHSQLJobRun';

PRINT '[OK]   msdb-Rollen SQLAgentOperatorRole + SQLAgentUserRole gesetzt.';
PRINT '';
GO

-- ============================================================================
-- PHASE 4: xp_cmdshell aktivieren (benoetigt fuer T-Log Unterordner-Anlage)
-- ============================================================================
PRINT '--- PHASE 4: xp_cmdshell aktivieren ------------------------------------';
GO

EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
GO

EXEC sp_configure 'xp_cmdshell', 1;
RECONFIGURE;
GO

PRINT '[OK]   xp_cmdshell aktiviert.';
PRINT '';
GO

-- ============================================================================
-- PHASE 5: QueryStore-Berichtstabelle in msdb anlegen
-- ============================================================================
PRINT '--- PHASE 5: QueryStore-Berichtstabelle --------------------------------';
GO

USE [msdb];
GO

IF OBJECT_ID('msdb.dbo.BitHawk_QueryStore_Report', 'U') IS NULL
BEGIN
    CREATE TABLE msdb.dbo.BitHawk_QueryStore_Report (
        ReportID        INT           IDENTITY(1,1) PRIMARY KEY,
        ReportDate      DATETIME2     NOT NULL DEFAULT SYSDATETIME(),
        DatabaseName    SYSNAME       NOT NULL,
        ReportType      NVARCHAR(100) NOT NULL,
        QueryID         BIGINT        NULL,
        PlanID          BIGINT        NULL,
        QueryText       NVARCHAR(MAX) NULL,
        AvgCPUms        DECIMAL(18,2) NULL,
        AvgDurationMs   DECIMAL(18,2) NULL,
        AvgLogicalReads DECIMAL(18,2) NULL,
        AvgMemoryKB     DECIMAL(18,2) NULL,
        ExecutionCount  BIGINT        NULL,
        AvgWaitCategory NVARCHAR(128) NULL,
        AvgWaitTimeMs   DECIMAL(18,2) NULL
    );

    CREATE INDEX IX_BitHawk_QSReport_Date_DB
        ON msdb.dbo.BitHawk_QueryStore_Report (ReportDate DESC, DatabaseName);

    PRINT '[OK]   Tabelle BitHawk_QueryStore_Report angelegt.';
END
ELSE
    PRINT '[OK]   Tabelle BitHawk_QueryStore_Report bereits vorhanden.';

PRINT '';
GO

-- ============================================================================
-- PHASE 6: Job 1 – BitHawk_Integrity_Check_Samstag  (Samstag 04:00)
-- ============================================================================
PRINT '--- PHASE 7: Job 2/9 – BitHawk_Integrity_Check_Samstag ----------------';
GO

USE [msdb];
GO

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'BitHawk_Integrity_Check_Samstag')
BEGIN
    EXEC sp_delete_job @job_name = N'BitHawk_Integrity_Check_Samstag', @delete_unused_schedule = 1;
    PRINT '       -> Bestehender Job entfernt.';
END

EXEC sp_add_job
    @job_name              = N'BitHawk_Integrity_Check_Samstag',
    @description           = N'DBCC CHECKDB mit DATA_PURITY und ALL_ERRORMSGS fuer alle Online-Datenbanken.',
    @enabled               = 1,
    @owner_login_name      = N'BHSQLJobRun',
    @notify_level_eventlog = 2;

EXEC sp_add_jobstep
    @job_name          = N'BitHawk_Integrity_Check_Samstag',
    @step_name         = N'DBCC CHECKDB alle DBs',
    @subsystem         = N'TSQL',
    @on_success_action = 1,
    @on_fail_action    = 2,
    @command           = N'
DECLARE @DB  SYSNAME;
DECLARE @SQL NVARCHAR(500);

DECLARE db_cursor CURSOR FOR
    SELECT name FROM sys.databases
    WHERE  state_desc  = ''ONLINE''
      AND  name        <> ''tempdb''
      AND  is_read_only = 0;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DB;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @SQL = ''DBCC CHECKDB('' + QUOTENAME(@DB)
             + '') WITH NO_INFOMSGS, ALL_ERRORMSGS, DATA_PURITY;'';
    EXEC sp_executesql @SQL;
    FETCH NEXT FROM db_cursor INTO @DB;
END;

CLOSE      db_cursor;
DEALLOCATE db_cursor;
';

EXEC sp_add_schedule
    @schedule_name          = N'BitHawk_Sched_Samstag_0400',
    @freq_type              = 8,
    @freq_interval          = 64,
    @freq_recurrence_factor = 1,
    @active_start_time      = 040000;

EXEC sp_attach_schedule
    @job_name      = N'BitHawk_Integrity_Check_Samstag',
    @schedule_name = N'BitHawk_Sched_Samstag_0400';

EXEC sp_add_jobserver @job_name = N'BitHawk_Integrity_Check_Samstag';

PRINT '[OK]   Job 2 installiert: BitHawk_Integrity_Check_Samstag';
PRINT '';
GO

-- ============================================================================
-- PHASE 7: Job 2 – BitHawk_Statistics_Update_Samstag  (Samstag 10:00)
-- ============================================================================
PRINT '--- PHASE 9: Job 4/9 – BitHawk_Statistics_Update_Samstag --------------';
GO

USE [msdb];
GO

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'BitHawk_Statistics_Update_Samstag')
BEGIN
    EXEC sp_delete_job @job_name = N'BitHawk_Statistics_Update_Samstag', @delete_unused_schedule = 1;
    PRINT '       -> Bestehender Job entfernt.';
END

EXEC sp_add_job
    @job_name              = N'BitHawk_Statistics_Update_Samstag',
    @description           = N'UPDATE STATISTICS FULLSCAN aller Benutzertabellen auf allen Datenbanken.',
    @enabled               = 1,
    @owner_login_name      = N'BHSQLJobRun',
    @notify_level_eventlog = 2;

EXEC sp_add_jobstep
    @job_name          = N'BitHawk_Statistics_Update_Samstag',
    @step_name         = N'Statistics Update alle DBs',
    @subsystem         = N'TSQL',
    @on_success_action = 1,
    @on_fail_action    = 2,
    @command           = N'
DECLARE @DB  SYSNAME;
DECLARE @SQL NVARCHAR(MAX);

DECLARE db_cursor CURSOR FOR
    SELECT name FROM sys.databases
    WHERE  state_desc  = ''ONLINE''
      AND  name       NOT IN (''tempdb'', ''model'')
      AND  is_read_only = 0;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DB;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @SQL = ''
    USE '' + QUOTENAME(@DB) + '';

    DECLARE @tbl NVARCHAR(512);
    DECLARE tbl_cur CURSOR FOR
        SELECT QUOTENAME(s.name) + ''''.'''' + QUOTENAME(t.name)
        FROM   sys.tables  t
        JOIN   sys.schemas s ON t.schema_id = s.schema_id
        WHERE  t.type = ''''U'''';

    OPEN tbl_cur;
    FETCH NEXT FROM tbl_cur INTO @tbl;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC(''''UPDATE STATISTICS '''' + @tbl + '''' WITH FULLSCAN;'''');
        FETCH NEXT FROM tbl_cur INTO @tbl;
    END;
    CLOSE      tbl_cur;
    DEALLOCATE tbl_cur;
    '';

    EXEC sp_executesql @SQL;
    FETCH NEXT FROM db_cursor INTO @DB;
END;

CLOSE      db_cursor;
DEALLOCATE db_cursor;
';

EXEC sp_add_schedule
    @schedule_name          = N'BitHawk_Sched_Samstag_1000',
    @freq_type              = 8,
    @freq_interval          = 64,
    @freq_recurrence_factor = 1,
    @active_start_time      = 100000;

EXEC sp_attach_schedule
    @job_name      = N'BitHawk_Statistics_Update_Samstag',
    @schedule_name = N'BitHawk_Sched_Samstag_1000';

EXEC sp_add_jobserver @job_name = N'BitHawk_Statistics_Update_Samstag';

PRINT '[OK]   Job 4 installiert: BitHawk_Statistics_Update_Samstag';
PRINT '';
GO

-- ============================================================================
-- PHASE 8: Job 3 – BitHawk_QueryStore_Bericht_Samstag  (Samstag 11:00)
-- ============================================================================
PRINT '--- PHASE 10: Job 5/9 – BitHawk_QueryStore_Bericht_Samstag ------------';
GO

USE [msdb];
GO

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'BitHawk_QueryStore_Bericht_Samstag')
BEGIN
    EXEC sp_delete_job @job_name = N'BitHawk_QueryStore_Bericht_Samstag', @delete_unused_schedule = 1;
    PRINT '       -> Bestehender Job entfernt.';
END

EXEC sp_add_job
    @job_name              = N'BitHawk_QueryStore_Bericht_Samstag',
    @description           = N'QueryStore Wochenbericht: Top CPU-Queries, Plan-Regressionen und Wait-Statistiken. Persistiert in msdb.dbo.BitHawk_QueryStore_Report.',
    @enabled               = 1,
    @owner_login_name      = N'BHSQLJobRun',
    @notify_level_eventlog = 2;

EXEC sp_add_jobstep
    @job_name          = N'BitHawk_QueryStore_Bericht_Samstag',
    @step_name         = N'QueryStore Analyse alle DBs',
    @subsystem         = N'TSQL',
    @on_success_action = 1,
    @on_fail_action    = 2,
    @command           = N'
-- Zieltabelle sicherstellen
IF OBJECT_ID(''msdb.dbo.BitHawk_QueryStore_Report'', ''U'') IS NULL
BEGIN
    CREATE TABLE msdb.dbo.BitHawk_QueryStore_Report (
        ReportID        INT           IDENTITY(1,1) PRIMARY KEY,
        ReportDate      DATETIME2     NOT NULL DEFAULT SYSDATETIME(),
        DatabaseName    SYSNAME       NOT NULL,
        ReportType      NVARCHAR(100) NOT NULL,
        QueryID         BIGINT        NULL,
        PlanID          BIGINT        NULL,
        QueryText       NVARCHAR(MAX) NULL,
        AvgCPUms        DECIMAL(18,2) NULL,
        AvgDurationMs   DECIMAL(18,2) NULL,
        AvgLogicalReads DECIMAL(18,2) NULL,
        AvgMemoryKB     DECIMAL(18,2) NULL,
        ExecutionCount  BIGINT        NULL,
        AvgWaitCategory NVARCHAR(128) NULL,
        AvgWaitTimeMs   DECIMAL(18,2) NULL
    );
END;

DECLARE @DB  SYSNAME;
DECLARE @SQL NVARCHAR(MAX);

DECLARE db_cursor CURSOR FOR
    SELECT name FROM sys.databases
    WHERE  state_desc        = ''ONLINE''
      AND  is_query_store_on = 1
      AND  name             NOT IN (''tempdb'', ''model'', ''master'', ''msdb'')
      AND  is_read_only      = 0;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DB;

WHILE @@FETCH_STATUS = 0
BEGIN

    -- A) Top 20 CPU-intensivste Queries (letzte 7 Tage)
    SET @SQL = ''
    USE '' + QUOTENAME(@DB) + '';
    INSERT INTO msdb.dbo.BitHawk_QueryStore_Report
        (DatabaseName, ReportType, QueryID, PlanID, QueryText,
         AvgCPUms, AvgDurationMs, AvgLogicalReads, AvgMemoryKB,
         ExecutionCount, AvgWaitCategory, AvgWaitTimeMs)
    SELECT TOP 20
        DB_NAME(), ''''Top CPU Queries'''',
        q.query_id, p.plan_id, LEFT(qt.query_sql_text, 2000),
        ROUND(AVG(rs.avg_cpu_time)             / 1000.0, 2),
        ROUND(AVG(rs.avg_duration)              / 1000.0, 2),
        ROUND(AVG(rs.avg_logical_io_reads),              2),
        ROUND(AVG(rs.avg_query_max_used_memory),         2),
        SUM(rs.count_executions), NULL, NULL
    FROM sys.query_store_query                  q
    JOIN sys.query_store_query_text             qt  ON q.query_text_id            = qt.query_text_id
    JOIN sys.query_store_plan                   p   ON q.query_id                 = p.query_id
    JOIN sys.query_store_runtime_stats          rs  ON p.plan_id                  = rs.plan_id
    JOIN sys.query_store_runtime_stats_interval rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
    WHERE rsi.start_time >= DATEADD(DAY, -7, SYSDATETIME())
    GROUP BY q.query_id, p.plan_id, qt.query_sql_text
    ORDER BY AVG(rs.avg_cpu_time) DESC;
    '';
    EXEC sp_executesql @SQL;

    -- B) Top 10 Plan-Regressionen (letzte 7 Tage)
    SET @SQL = ''
    USE '' + QUOTENAME(@DB) + '';
    INSERT INTO msdb.dbo.BitHawk_QueryStore_Report
        (DatabaseName, ReportType, QueryID, PlanID, QueryText,
         AvgCPUms, AvgDurationMs, AvgLogicalReads, AvgMemoryKB,
         ExecutionCount, AvgWaitCategory, AvgWaitTimeMs)
    SELECT TOP 10
        DB_NAME(), ''''Regressionen Plan-Wechsel'''',
        q.query_id, p.plan_id, LEFT(qt.query_sql_text, 2000),
        ROUND(AVG(rs.avg_cpu_time)             / 1000.0, 2),
        ROUND(AVG(rs.avg_duration)              / 1000.0, 2),
        ROUND(AVG(rs.avg_logical_io_reads),              2),
        ROUND(AVG(rs.avg_query_max_used_memory),         2),
        SUM(rs.count_executions), NULL, NULL
    FROM sys.query_store_query                  q
    JOIN sys.query_store_query_text             qt  ON q.query_text_id            = qt.query_text_id
    JOIN sys.query_store_plan                   p   ON q.query_id                 = p.query_id
    JOIN sys.query_store_runtime_stats          rs  ON p.plan_id                  = rs.plan_id
    JOIN sys.query_store_runtime_stats_interval rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
    WHERE rsi.start_time  >= DATEADD(DAY, -7, SYSDATETIME())
      AND p.is_forced_plan = 0
    GROUP BY q.query_id, p.plan_id, qt.query_sql_text
    HAVING COUNT(DISTINCT p.plan_id) > 1
    ORDER BY AVG(rs.avg_duration) DESC;
    '';
    EXEC sp_executesql @SQL;

    -- C) Top 10 Wait-Statistiken
    SET @SQL = ''
    USE '' + QUOTENAME(@DB) + '';
    INSERT INTO msdb.dbo.BitHawk_QueryStore_Report
        (DatabaseName, ReportType, QueryID, PlanID, QueryText,
         AvgCPUms, AvgDurationMs, AvgLogicalReads, AvgMemoryKB,
         ExecutionCount, AvgWaitCategory, AvgWaitTimeMs)
    SELECT TOP 10
        DB_NAME(), ''''Top Wait Stats'''',
        q.query_id, p.plan_id, LEFT(qt.query_sql_text, 2000),
        ROUND(AVG(rs.avg_cpu_time)             / 1000.0, 2),
        ROUND(AVG(rs.avg_duration)              / 1000.0, 2),
        ROUND(AVG(rs.avg_logical_io_reads),              2),
        ROUND(AVG(rs.avg_query_max_used_memory),         2),
        SUM(rs.count_executions),
        CAST(ws.wait_category_desc AS NVARCHAR(128)),
        ROUND(AVG(ws.avg_query_wait_time_ms),            2)
    FROM sys.query_store_query                  q
    JOIN sys.query_store_query_text             qt  ON q.query_text_id            = qt.query_text_id
    JOIN sys.query_store_plan                   p   ON q.query_id                 = p.query_id
    JOIN sys.query_store_runtime_stats          rs  ON p.plan_id                  = rs.plan_id
    JOIN sys.query_store_runtime_stats_interval rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
    JOIN sys.query_store_wait_stats             ws  ON p.plan_id                  = ws.plan_id
    WHERE rsi.start_time >= DATEADD(DAY, -7, SYSDATETIME())
    GROUP BY q.query_id, p.plan_id, qt.query_sql_text, ws.wait_category_desc
    ORDER BY AVG(ws.avg_query_wait_time_ms) DESC;
    '';
    EXEC sp_executesql @SQL;

    FETCH NEXT FROM db_cursor INTO @DB;
END;

CLOSE      db_cursor;
DEALLOCATE db_cursor;

RAISERROR(N''BitHawk QueryStore Bericht abgeschlossen.'', 0, 1, ) WITH NOWAIT;
';

EXEC sp_add_schedule
    @schedule_name          = N'BitHawk_Sched_Samstag_1100',
    @freq_type              = 8,
    @freq_interval          = 64,
    @freq_recurrence_factor = 1,
    @active_start_time      = 110000;

EXEC sp_attach_schedule
    @job_name      = N'BitHawk_QueryStore_Bericht_Samstag',
    @schedule_name = N'BitHawk_Sched_Samstag_1100';

EXEC sp_add_jobserver @job_name = N'BitHawk_QueryStore_Bericht_Samstag';

PRINT '[OK]   Job 5 installiert: BitHawk_QueryStore_Bericht_Samstag';
PRINT '';
GO
-- ============================================================================
-- PHASE 15: Verifikation
-- ============================================================================
PRINT '========================================================================';
PRINT '  PHASE 15: Verifikation';
PRINT '========================================================================';
GO

USE [msdb];
GO

-- Login und Rolle pruefen
PRINT '-- Login BHSQLJobRun:';
SELECT
    sp.name                                    AS LoginName,
    sp.type_desc                               AS LoginTyp,
    sp.is_disabled                             AS Deaktiviert,
    ISNULL(srm.role_principal_id, 0)           AS IstSysAdmin
FROM master.sys.server_principals              sp
LEFT JOIN master.sys.server_role_members       srm
       ON sp.principal_id = srm.member_principal_id
      AND srm.role_principal_id = SUSER_ID('sysadmin')
WHERE sp.name = N'BHSQLJobRun';
GO

-- Alle BitHawk Jobs mit Owner und naechster Ausfuehrung
PRINT '';
PRINT '-- BitHawk Jobs (Owner + Zeitplan):';
SELECT
    j.name                                                  AS JobName,
    j.enabled                                               AS Aktiv,
    sp.name                                                 AS Owner,
    CASE s.freq_type
        WHEN 1 THEN 'Einmalig'
        WHEN 4 THEN 'Taeglich'
        WHEN 8 THEN 'Woechentlich'
        ELSE        CAST(s.freq_type AS NVARCHAR)
    END                                                     AS Rhythmus,
    STUFF(
        RIGHT('000000' + CAST(s.active_start_time AS NVARCHAR(6)), 6),
        3, 0, ':'
    )                                                       AS StartZeit,
    j.date_created                                          AS Erstellt
FROM msdb.dbo.sysjobs                                       j
JOIN master.sys.server_principals                           sp ON j.owner_sid   = sp.sid
JOIN msdb.dbo.sysjobschedules                               js ON j.job_id      = js.job_id
JOIN msdb.dbo.sysschedules                                  s  ON js.schedule_id = s.schedule_id
WHERE j.name LIKE N'BitHawk%'
ORDER BY j.name;
GO

-- Passwort aus Temp-Tabelle ausgeben
PRINT '';
PRINT '========================================================================';
PRINT '  *** WICHTIG: Generiertes Passwort fuer BHSQLJobRun ***';
PRINT '========================================================================';

IF OBJECT_ID('tempdb..#BHPwd') IS NOT NULL
BEGIN
    DECLARE @anzeige NVARCHAR(64);
    SELECT @anzeige = pwd FROM #BHPwd;
    PRINT '  Passwort : ' + @anzeige;
    PRINT '  Login    : BHSQLJobRun';
    PRINT '  Typ      : SQL Authentication';
    PRINT '  Rolle    : sysadmin';
    PRINT '';
    PRINT '  Bitte sofort in KeePass / BitHawk Vault sichern!';
    PRINT '  Diese Ausgabe erscheint NUR bei der Installation.';
    DROP TABLE #BHPwd;
END
ELSE
    PRINT '  [INFO] Passwort-Tabelle nicht gefunden – Login war bereits vorhanden.';

PRINT '========================================================================';
PRINT '  Installation abgeschlossen: ' + CONVERT(NVARCHAR(20), GETDATE(), 120);
PRINT '  Naechste Schritte:';
PRINT '    1. Backup-Ordner anlegen: S:\SQLBackup\Full  \Diff  \Log';
PRINT '    2. Query Store aktivieren (Anhang A)';
PRINT '    3. Test-Lauf: BitHawk_Backup_Full_Wochenende manuell starten';
PRINT '========================================================================';
GO

-- ============================================================================
-- ANHANG A: Query Store aktivieren (Datenbankname anpassen, dann einkommentieren)
-- ============================================================================
/*
ALTER DATABASE [IhreDatenbank]
SET QUERY_STORE = ON (
    OPERATION_MODE              = READ_WRITE,
    CLEANUP_POLICY              = (STALE_QUERY_THRESHOLD_DAYS = 30),
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    INTERVAL_LENGTH_MINUTES     = 60,
    MAX_STORAGE_SIZE_MB         = 1000,
    QUERY_CAPTURE_MODE          = AUTO,
    SIZE_BASED_CLEANUP_MODE     = AUTO,
    MAX_PLANS_PER_QUERY         = 200
);
GO

-- Status aller Datenbanken pruefen:
SELECT name, is_query_store_on, recovery_model_desc
FROM   sys.databases
WHERE  name NOT IN ('tempdb')
ORDER  BY name;
GO
*/

-- ============================================================================
-- ANHANG B: QueryStore-Bericht abfragen
-- ============================================================================
/*
SELECT
    DatabaseName,
    ReportType,
    LEFT(QueryText, 120)   AS QueryText,
    AvgCPUms,
    AvgDurationMs,
    ExecutionCount,
    AvgWaitCategory,
    AvgWaitTimeMs,
    ReportDate
FROM msdb.dbo.BitHawk_QueryStore_Report
WHERE CAST(ReportDate AS DATE) = CAST(GETDATE() AS DATE)
ORDER BY ReportDate DESC, AvgCPUms DESC;
*/

-- ============================================================================
-- ANHANG C: DEINSTALLATION – alle BitHawk Jobs + Login entfernen
--           Diesen Block auskommentieren und einzeln ausfuehren.
-- ============================================================================
/*
USE [msdb];
GO

-- Jobs entfernen
DECLARE @jobs TABLE (jname SYSNAME);
INSERT INTO @jobs VALUES
    (N'BitHawk_Backup_Full_Wochenende'),
    (N'BitHawk_Integrity_Check_Samstag'),
    (N'BitHawk_Index_Rebuild_Samstag'),
    (N'BitHawk_Statistics_Update_Samstag'),
    (N'BitHawk_QueryStore_Bericht_Samstag'),
    (N'BitHawk_Backup_Cleanup_Samstag'),
    (N'BitHawk_Backup_Diff_Sonntag'),
    (N'BitHawk_Backup_TLog_Stuendlich_Werktags'),
    (N'BitHawk_Backup_TLog_Cleanup_Taeglich');

DECLARE @n SYSNAME;
DECLARE c CURSOR FOR SELECT jname FROM @jobs;
OPEN c; FETCH NEXT FROM c INTO @n;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @n)
    BEGIN
        EXEC msdb.dbo.sp_delete_job @job_name = @n, @delete_unused_schedule = 1;
        PRINT 'Entfernt: ' + @n;
    END
    FETCH NEXT FROM c INTO @n;
END;
CLOSE c; DEALLOCATE c;
GO

-- Login entfernen
USE [master];
GO

IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'BHSQLJobRun')
BEGIN
    DROP LOGIN [BHSQLJobRun];
    PRINT 'Login BHSQLJobRun entfernt.';
END
GO

-- Optional: Berichtstabelle entfernen
-- USE [msdb];
-- DROP TABLE dbo.BitHawk_QueryStore_Report;
-- GO
*/

-- ==================================================================================
-- Ende: BitHawk_SQL_Wartungsjobs_SLA_Install_V12.sql  |  Version 1.0  |  BitHawk AG
-- ==================================================================================
