/*
================================================================================
  ____  _ _   _   _               _
 | __ )(_) |_| | | | __ ___      _| | __
 |  _ \| | __| |_| |/ _` \ \ /\ / / |/ /
 | |_) | | |_|  _  | (_| |\ V  V /|   <
 |____/|_|\__|_| |_|\__,_| \_/\_/ |_|\_\

 SQL Server – Installations-Paket für SLA Kunden nach dem Plugin Installation
===================================================================================
 Datei    : BitHawk_AD_Login_Sync_Weekly_Job.sql
 Version  : 1.0
 Erstellt : 2026-04-29
 Autor    : BitHawk AG
 Ersteller: Marcel Luginbühl

================================================================================
  AD Login & Gruppen Synchronisation - Wöchentlicher SQL Agent Job
================================================================================
  Beschreibung:
    - Synchronisiert Windows-Logins und AD-Gruppen mit dem SQL Server
    - Entfernt Logins, deren AD-Konten in der Domäne gelöscht wurden
    - Erstellt einen SQL Agent Job der jeden Montag um 05:00 Uhr läuft

  Voraussetzungen:
    - sysadmin-Berechtigung auf dem SQL Server
    - SQL Server Agent muss laufen
    - xp_logininfo muss verfügbar sein (Standard bei Windows-Authentifizierung)

  Installation:
    Einfach das gesamte Skript auf dem Ziel-SQL-Server ausführen.

================================================================================
*/

USE [master];
GO


-- ============================================================================
-- SCHRITT 1: Stored Procedure für die AD-Synchronisation erstellen
-- ============================================================================

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_AD_Login_Sync' AND schema_id = SCHEMA_ID('dbo'))
    DROP PROCEDURE dbo.usp_AD_Login_Sync;
GO

CREATE PROCEDURE dbo.usp_AD_Login_Sync
    @DryRun BIT = 0,           -- 1 = Nur anzeigen, nichts ändern
    @VerboseLog BIT = 1        -- 1 = Detailliertes Logging
AS
BEGIN
    SET NOCOUNT ON;

    -- ========================================================================
    -- Variablen & Temp-Tabellen
    -- ========================================================================
    DECLARE @LoginName      NVARCHAR(256);
    DECLARE @LoginType      NVARCHAR(60);
    DECLARE @SQL            NVARCHAR(MAX);
    DECLARE @ErrorMsg       NVARCHAR(MAX);
    DECLARE @CountRemoved   INT = 0;
    DECLARE @CountChecked   INT = 0;
    DECLARE @CountErrors    INT = 0;
    DECLARE @CountGroupSync INT = 0;
    DECLARE @StartTime      DATETIME = GETDATE();

    -- Log-Tabelle erstellen (falls nicht vorhanden)
    IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'AD_Login_Sync_Log' AND schema_id = SCHEMA_ID('dbo'))
    BEGIN
        CREATE TABLE dbo.AD_Login_Sync_Log (
            LogID           INT IDENTITY(1,1) PRIMARY KEY,
            LogDate         DATETIME NOT NULL DEFAULT GETDATE(),
            LogLevel        VARCHAR(10) NOT NULL,  -- INFO, WARN, ERROR
            Category        VARCHAR(30) NOT NULL,  -- CHECK, REMOVE, SYNC, SUMMARY
            LoginName       NVARCHAR(256) NULL,
            Message         NVARCHAR(MAX) NOT NULL
        );

        CREATE NONCLUSTERED INDEX IX_AD_Login_Sync_Log_Date
            ON dbo.AD_Login_Sync_Log (LogDate DESC);
    END;

    -- Protokoll-Start
    INSERT INTO dbo.AD_Login_Sync_Log (LogLevel, Category, Message)
    VALUES ('INFO', 'SUMMARY', 'AD Login Synchronisation gestartet. DryRun=' + CAST(@DryRun AS VARCHAR(1)));

    -- Temp-Tabelle für xp_logininfo Ergebnisse
    CREATE TABLE #LoginInfo (
        AccountName     NVARCHAR(256),
        Type            VARCHAR(10),
        Privilege       VARCHAR(10),
        MappedLoginName NVARCHAR(256),
        PermissionPath  NVARCHAR(256)
    );

    -- Temp-Tabelle für zu prüfende Logins
    CREATE TABLE #WindowsLogins (
        LoginName   NVARCHAR(256),
        LoginType   NVARCHAR(60),
        IsOrphaned  BIT DEFAULT 0,
        ErrorMsg    NVARCHAR(MAX) NULL
    );

    -- ========================================================================
    -- SCHRITT A: Alle Windows-Logins und -Gruppen sammeln
    -- ========================================================================
    INSERT INTO #WindowsLogins (LoginName, LoginType)
    SELECT
        sp.name,
        sp.type_desc
    FROM sys.server_principals sp
    WHERE sp.type IN ('U', 'G')              -- U = Windows Login, G = Windows Gruppe
      AND sp.name NOT LIKE 'NT SERVICE\%'    -- System-Dienste ausschließen
      AND sp.name NOT LIKE 'NT AUTHORITY\%'  -- System-Konten ausschließen
      AND sp.name NOT LIKE 'BUILTIN\%'       -- Built-in Gruppen ausschließen
      AND sp.name <> 'sa'
      AND sp.is_disabled = 0;                -- Bereits deaktivierte ignorieren

    SELECT @CountChecked = @@ROWCOUNT;

    IF @VerboseLog = 1
        INSERT INTO dbo.AD_Login_Sync_Log (LogLevel, Category, Message)
        VALUES ('INFO', 'CHECK', CAST(@CountChecked AS VARCHAR(10)) + ' Windows-Logins/Gruppen werden geprüft.');

    -- ========================================================================
    -- SCHRITT B: Jeden Login gegen AD prüfen
    -- ========================================================================
    DECLARE login_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT LoginName, LoginType FROM #WindowsLogins;

    OPEN login_cursor;
    FETCH NEXT FROM login_cursor INTO @LoginName, @LoginType;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            -- xp_logininfo prüft, ob das AD-Konto noch existiert
            DELETE FROM #LoginInfo;

            INSERT INTO #LoginInfo
            EXEC xp_logininfo @acctname = @LoginName, @option = 'all';

            -- Wenn keine Zeilen zurückkommen, existiert das Konto nicht mehr
            IF NOT EXISTS (SELECT 1 FROM #LoginInfo)
            BEGIN
                UPDATE #WindowsLogins SET IsOrphaned = 1 WHERE LoginName = @LoginName;

                IF @VerboseLog = 1
                    INSERT INTO dbo.AD_Login_Sync_Log (LogLevel, Category, LoginName, Message)
                    VALUES ('WARN', 'CHECK', @LoginName,
                        'AD-Konto nicht gefunden - wird als verwaist markiert (' + @LoginType + ')');
            END
            ELSE
            BEGIN
                IF @VerboseLog = 1
                    INSERT INTO dbo.AD_Login_Sync_Log (LogLevel, Category, LoginName, Message)
                    VALUES ('INFO', 'CHECK', @LoginName, 'AD-Konto gültig (' + @LoginType + ')');
            END
        END TRY
        BEGIN CATCH
            -- Fehler bei xp_logininfo = Konto existiert wahrscheinlich nicht mehr
            SET @ErrorMsg = ERROR_MESSAGE();

            -- Typische Fehlermeldungen bei gelöschten Konten
            IF @ErrorMsg LIKE '%0x5%'           -- Zugriff verweigert
                OR @ErrorMsg LIKE '%0x534%'     -- Konto nicht zugeordnet
                OR @ErrorMsg LIKE '%0x525%'     -- Benutzer nicht gefunden
                OR @ErrorMsg LIKE '%nicht gefunden%'
                OR @ErrorMsg LIKE '%could not be found%'
                OR @ErrorMsg LIKE '%No mapping%'
            BEGIN
                UPDATE #WindowsLogins
                SET IsOrphaned = 1, ErrorMsg = @ErrorMsg
                WHERE LoginName = @LoginName;

                INSERT INTO dbo.AD_Login_Sync_Log (LogLevel, Category, LoginName, Message)
                VALUES ('WARN', 'CHECK', @LoginName,
                    'AD-Prüfung fehlgeschlagen (verwaist): ' + @ErrorMsg);
            END
            ELSE
            BEGIN
                -- Unerwarteter Fehler - nicht automatisch löschen
                UPDATE #WindowsLogins
                SET ErrorMsg = @ErrorMsg
                WHERE LoginName = @LoginName;

                SET @CountErrors = @CountErrors + 1;

                INSERT INTO dbo.AD_Login_Sync_Log (LogLevel, Category, LoginName, Message)
                VALUES ('ERROR', 'CHECK', @LoginName,
                    'Unerwarteter Fehler bei AD-Prüfung: ' + @ErrorMsg);
            END
        END CATCH

        FETCH NEXT FROM login_cursor INTO @LoginName, @LoginType;
    END

    CLOSE login_cursor;
    DEALLOCATE login_cursor;

    -- ========================================================================
    -- SCHRITT C: Verwaiste Logins entfernen
    -- ========================================================================
    DECLARE orphan_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT LoginName, LoginType
        FROM #WindowsLogins
        WHERE IsOrphaned = 1;

    OPEN orphan_cursor;
    FETCH NEXT FROM orphan_cursor INTO @LoginName, @LoginType;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            IF @DryRun = 0
            BEGIN
                -- Aktive Sessions beenden (optional, auskommentieren falls nicht gewünscht)
                DECLARE @SessionID INT;
                DECLARE session_cursor CURSOR LOCAL FAST_FORWARD FOR
                    SELECT session_id FROM sys.dm_exec_sessions
                    WHERE login_name = @LoginName;

                OPEN session_cursor;
                FETCH NEXT FROM session_cursor INTO @SessionID;

                WHILE @@FETCH_STATUS = 0
                BEGIN
                    BEGIN TRY
                        SET @SQL = N'KILL ' + CAST(@SessionID AS NVARCHAR(10));
                        EXEC sp_executesql @SQL;

                        INSERT INTO dbo.AD_Login_Sync_Log (LogLevel, Category, LoginName, Message)
                        VALUES ('INFO', 'REMOVE', @LoginName,
                            'Session ' + CAST(@SessionID AS VARCHAR(10)) + ' beendet.');
                    END TRY
                    BEGIN CATCH
                        -- Session-Kill-Fehler ignorieren
                        INSERT INTO dbo.AD_Login_Sync_Log (LogLevel, Category, LoginName, Message)
                        VALUES ('WARN', 'REMOVE', @LoginName,
                            'Session ' + CAST(@SessionID AS VARCHAR(10)) + ' konnte nicht beendet werden: ' + ERROR_MESSAGE());
                    END CATCH

                    FETCH NEXT FROM session_cursor INTO @SessionID;
                END

                CLOSE session_cursor;
                DEALLOCATE session_cursor;

                -- DB-Benutzer entfernen, die diesem Login zugeordnet sind
                DECLARE @DBName NVARCHAR(256);
                DECLARE @DBUser NVARCHAR(256);

                DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
                    SELECT name FROM sys.databases
                    WHERE state_desc = 'ONLINE'
                      AND database_id > 4;  -- System-DBs ausschließen

                OPEN db_cursor;
                FETCH NEXT FROM db_cursor INTO @DBName;

                WHILE @@FETCH_STATUS = 0
                BEGIN
                    BEGIN TRY
                        SET @SQL = N'
                            USE ' + QUOTENAME(@DBName) + N';
                            DECLARE @user NVARCHAR(256);
                            SELECT @user = dp.name
                            FROM sys.database_principals dp
                            INNER JOIN sys.server_principals sp
                                ON dp.sid = sp.sid
                            WHERE sp.name = @LoginParam
                              AND dp.type IN (''U'', ''G'');

                            IF @user IS NOT NULL
                            BEGIN
                                -- Schemas übertragen
                                DECLARE @schema NVARCHAR(256);
                                DECLARE schema_cur CURSOR LOCAL FAST_FORWARD FOR
                                    SELECT name FROM sys.schemas
                                    WHERE principal_id = USER_ID(@user)
                                      AND name <> @user;

                                OPEN schema_cur;
                                FETCH NEXT FROM schema_cur INTO @schema;
                                WHILE @@FETCH_STATUS = 0
                                BEGIN
                                    EXEC(''ALTER AUTHORIZATION ON SCHEMA::'' + @schema + '' TO dbo'');
                                    FETCH NEXT FROM schema_cur INTO @schema;
                                END
                                CLOSE schema_cur;
                                DEALLOCATE schema_cur;

                                EXEC(''DROP USER '' + QUOTENAME(@user));
                            END';

                        EXEC sp_executesql @SQL, N'@LoginParam NVARCHAR(256)', @LoginParam = @LoginName;

                        INSERT INTO dbo.AD_Login_Sync_Log (LogLevel, Category, LoginName, Message)
                        VALUES ('INFO', 'REMOVE', @LoginName,
                            'DB-Benutzer in [' + @DBName + '] entfernt.');
                    END TRY
                    BEGIN CATCH
                        INSERT INTO dbo.AD_Login_Sync_Log (LogLevel, Category, LoginName, Message)
                        VALUES ('ERROR', 'REMOVE', @LoginName,
                            'Fehler beim Entfernen des DB-Benutzers in [' + @DBName + ']: ' + ERROR_MESSAGE());
                    END CATCH

                    FETCH NEXT FROM db_cursor INTO @DBName;
                END

                CLOSE db_cursor;
                DEALLOCATE db_cursor;

                -- Server-Login entfernen
                SET @SQL = N'DROP LOGIN ' + QUOTENAME(@LoginName);
                EXEC sp_executesql @SQL;

                INSERT INTO dbo.AD_Login_Sync_Log (LogLevel, Category, LoginName, Message)
                VALUES ('INFO', 'REMOVE', @LoginName,
                    @LoginType + ' Login erfolgreich entfernt.');
            END
            ELSE
            BEGIN
                -- DryRun: Nur protokollieren
                INSERT INTO dbo.AD_Login_Sync_Log (LogLevel, Category, LoginName, Message)
                VALUES ('INFO', 'REMOVE', @LoginName,
                    '[DRYRUN] Würde entfernt werden (' + @LoginType + ')');
            END

            SET @CountRemoved = @CountRemoved + 1;

        END TRY
        BEGIN CATCH
            SET @CountErrors = @CountErrors + 1;

            INSERT INTO dbo.AD_Login_Sync_Log (LogLevel, Category, LoginName, Message)
            VALUES ('ERROR', 'REMOVE', @LoginName,
                'Fehler beim Entfernen: ' + ERROR_MESSAGE());
        END CATCH

        FETCH NEXT FROM orphan_cursor INTO @LoginName, @LoginType;
    END

    CLOSE orphan_cursor;
    DEALLOCATE orphan_cursor;

    -- ========================================================================
    -- SCHRITT D: AD-Gruppen-Mitgliedschaften aktualisieren
    -- ========================================================================
    DECLARE @GroupName NVARCHAR(256);

    DECLARE group_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT LoginName FROM #WindowsLogins
        WHERE LoginType = 'WINDOWS_GROUP'
          AND IsOrphaned = 0;

    OPEN group_cursor;
    FETCH NEXT FROM group_cursor INTO @GroupName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            -- Gruppeninfo aus AD aktualisieren (löst Cache-Refresh aus)
            DELETE FROM #LoginInfo;

            INSERT INTO #LoginInfo
            EXEC xp_logininfo @acctname = @GroupName, @option = 'members';

            SET @CountGroupSync = @CountGroupSync + 1;

            IF @VerboseLog = 1
            BEGIN
                DECLARE @MemberCount INT;
                SELECT @MemberCount = COUNT(*) FROM #LoginInfo;

                INSERT INTO dbo.AD_Login_Sync_Log (LogLevel, Category, LoginName, Message)
                VALUES ('INFO', 'SYNC', @GroupName,
                    'Gruppe aktualisiert - ' + CAST(@MemberCount AS VARCHAR(10)) + ' Mitglieder gefunden.');
            END
        END TRY
        BEGIN CATCH
            INSERT INTO dbo.AD_Login_Sync_Log (LogLevel, Category, LoginName, Message)
            VALUES ('WARN', 'SYNC', @GroupName,
                'Fehler bei Gruppen-Sync: ' + ERROR_MESSAGE());
        END CATCH

        FETCH NEXT FROM group_cursor INTO @GroupName;
    END

    CLOSE group_cursor;
    DEALLOCATE group_cursor;

    -- ========================================================================
    -- SCHRITT E: Zusammenfassung
    -- ========================================================================
    INSERT INTO dbo.AD_Login_Sync_Log (LogLevel, Category, Message)
    VALUES ('INFO', 'SUMMARY',
        'Synchronisation abgeschlossen. ' +
        'Geprüft: ' + CAST(@CountChecked AS VARCHAR(10)) + ', ' +
        'Entfernt: ' + CAST(@CountRemoved AS VARCHAR(10)) + ', ' +
        'Gruppen aktualisiert: ' + CAST(@CountGroupSync AS VARCHAR(10)) + ', ' +
        'Fehler: ' + CAST(@CountErrors AS VARCHAR(10)) + ', ' +
        'Dauer: ' + CAST(DATEDIFF(SECOND, @StartTime, GETDATE()) AS VARCHAR(10)) + ' Sek.');

    -- Alte Log-Einträge bereinigen (älter als 90 Tage)
    DELETE FROM dbo.AD_Login_Sync_Log
    WHERE LogDate < DATEADD(DAY, -90, GETDATE());

    -- Temp-Tabellen aufräumen
    DROP TABLE IF EXISTS #LoginInfo;
    DROP TABLE IF EXISTS #WindowsLogins;

    -- Ergebnis zurückgeben
    SELECT
        @CountChecked   AS LoginsGeprueft,
        @CountRemoved   AS LoginsEntfernt,
        @CountGroupSync AS GruppenAktualisiert,
        @CountErrors    AS Fehler,
        DATEDIFF(SECOND, @StartTime, GETDATE()) AS DauerSekunden;
END;
GO

PRINT '✓ Stored Procedure [dbo].[usp_AD_Login_Sync] erstellt.';
GO


-- ============================================================================
-- SCHRITT 2: SQL Agent Job erstellen
-- ============================================================================

USE [msdb];
GO

-- Bestehenden Job entfernen (falls vorhanden)
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'BitHawk_AD_Login_Synchronisation')
BEGIN
    EXEC msdb.dbo.sp_delete_job
        @job_name = N'BitHawk_AD_Login_Synchronisation',
        @delete_unused_schedule = 1;
END
GO

-- Job erstellen
DECLARE @JobID UNIQUEIDENTIFIER;
DECLARE @ReturnCode INT = 0;
DECLARE @ScheduleID INT;

EXEC @ReturnCode = msdb.dbo.sp_add_job
    @job_name = N'BitHawk_AD_Login_Synchronisation',
    @enabled = 1,
    @notify_level_eventlog = 2,     -- Bei Fehler ins Event-Log
    @notify_level_email = 2,        -- Bei Fehler per E-Mail (falls Operator konfiguriert)
    @description = N'Synchronisiert Windows-Logins und AD-Gruppen mit dem SQL Server. Entfernt verwaiste Logins, deren AD-Konten gelöscht wurden. Läuft jeden Montag um 05:00 Uhr.',
    @category_name = N'[Uncategorized (Local)]',
    @owner_login_name = N'sa',
    @job_id = @JobID OUTPUT;

IF @ReturnCode <> 0 GOTO QuitWithRollback;

-- Job-Schritt 1: AD Sync ausführen
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep
    @job_id = @JobID,
    @step_name = N'BitHawk_AD_Login_Synchronisation',
    @step_id = 1,
    @subsystem = N'TSQL',
    @command = N'EXEC master.dbo.usp_AD_Login_Sync @DryRun = 0, @VerboseLog = 1;',
    @database_name = N'master',
    @on_success_action = 3,         -- Weiter zum nächsten Schritt
    @on_fail_action = 2,            -- Job als fehlgeschlagen melden
    @retry_attempts = 1,
    @retry_interval = 5;            -- 5 Minuten Wartezeit bei Retry

IF @ReturnCode <> 0 GOTO QuitWithRollback;

-- Job-Schritt 2: Ergebnis-Bericht im Log
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep
    @job_id = @JobID,
    @step_name = N'Sync-Bericht ausgeben',
    @step_id = 2,
    @subsystem = N'TSQL',
    @command = N'
        SELECT TOP 50
            LogDate,
            LogLevel,
            Category,
            LoginName,
            Message
        FROM master.dbo.AD_Login_Sync_Log
        WHERE LogDate >= DATEADD(HOUR, -1, GETDATE())
        ORDER BY LogID DESC;

        -- Fehlerprüfung: Job als fehlgeschlagen melden wenn kritische Fehler
        IF EXISTS (
            SELECT 1 FROM master.dbo.AD_Login_Sync_Log
            WHERE LogDate >= DATEADD(HOUR, -1, GETDATE())
              AND LogLevel = ''ERROR''
        )
        BEGIN
            RAISERROR(''AD Login Sync: Es sind Fehler aufgetreten. Siehe AD_Login_Sync_Log.'', 16, 1);
        END',
    @database_name = N'master',
    @on_success_action = 1,         -- Job erfolgreich beenden
    @on_fail_action = 2,            -- Job als fehlgeschlagen melden
    @retry_attempts = 0;

IF @ReturnCode <> 0 GOTO QuitWithRollback;

-- Zeitplan: Jeden Montag um 05:00 Uhr
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule
    @job_id = @JobID,
    @name = N'Wöchentlich Montag 05:00',
    @enabled = 1,
    @freq_type = 8,                 -- Wöchentlich
    @freq_interval = 2,             -- Montag (1=So, 2=Mo, 4=Di, 8=Mi...)
    @freq_subday_type = 1,          -- Einmal am Tag
    @freq_recurrence_factor = 1,    -- Jede Woche
    @active_start_time = 050000,    -- 05:00:00 Uhr
    @schedule_id = @ScheduleID OUTPUT;

IF @ReturnCode <> 0 GOTO QuitWithRollback;

-- Job dem lokalen Server zuweisen
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver
    @job_id = @JobID,
    @server_name = N'(local)';

IF @ReturnCode <> 0 GOTO QuitWithRollback;

PRINT '✓ SQL Agent Job "BitHawk_AD_Login_Synchronisation" erstellt.';
PRINT '  Zeitplan: Jeden Montag um 05:00 Uhr';
PRINT '';
PRINT '  Manueller Test: EXEC msdb.dbo.sp_start_job @job_name = N''BitHawk_AD_Login_Synchronisation''';
PRINT '  DryRun-Test:    EXEC master.dbo.usp_AD_Login_Sync @DryRun = 1, @VerboseLog = 1';
PRINT '  Log anzeigen:   SELECT TOP 100 * FROM master.dbo.AD_Login_Sync_Log ORDER BY LogID DESC';
GOTO EndSave;

QuitWithRollback:
    PRINT '✗ FEHLER beim Erstellen des SQL Agent Jobs!';
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

EndSave:
GO

PRINT '';
PRINT '================================================================================';
PRINT '  Installation abgeschlossen.';
PRINT '================================================================================';
PRINT '';
PRINT '  Objekte:';
PRINT '    [master].[dbo].[usp_AD_Login_Sync]     - Stored Procedure';
PRINT '    [master].[dbo].[AD_Login_Sync_Log]      - Log-Tabelle (wird beim 1. Lauf erstellt)';
PRINT '    SQL Agent Job: "BitHawk_AD_Login_Synchronisation"';
PRINT '';
PRINT '  Befehle:';
PRINT '    DryRun (nur prüfen, nichts löschen):';
PRINT '      EXEC master.dbo.usp_AD_Login_Sync @DryRun = 1;';
PRINT '';
PRINT '    Manuell ausführen:';
PRINT '      EXEC master.dbo.usp_AD_Login_Sync @DryRun = 0;';
PRINT '';
PRINT '    Job sofort starten:';
PRINT '      EXEC msdb.dbo.sp_start_job N''BitHawk_AD_Login_Synchronisation'';';
PRINT '';
PRINT '    Log prüfen:';
PRINT '      SELECT * FROM master.dbo.AD_Login_Sync_Log ORDER BY LogID DESC;';
PRINT '';
PRINT '  Deinstallation:';
PRINT '    EXEC msdb.dbo.sp_delete_job @job_name = N''BitHawk_AD_Login_Synchronisation'';';
PRINT '    DROP PROCEDURE master.dbo.usp_AD_Login_Sync;';
PRINT '    DROP TABLE master.dbo.AD_Login_Sync_Log;';
PRINT '================================================================================';
GO
