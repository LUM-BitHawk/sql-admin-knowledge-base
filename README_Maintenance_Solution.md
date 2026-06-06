# SQL Server Maintenance Solution – BitHawk AG
> **Zielversion:** SQL Server 2022 / SQL Server 2025 (aktueller Standard)  
> **Lizenz:** Kostenlos / Open Source  
> **Mindestvoraussetzung:** SQL Server 2022 oder SQL Server 2025

---


## Übersicht

Die **SQL Server Maintenance Solution** von Ola Hallengren ist eine preisgekrönte, kostenlose Sammlung von Stored Procedures für die automatisierte Wartung von SQL Server-Datenbanken. Sie umfasst drei Kernbereiche:

| Stored Procedure         | Aufgabe                         | SQL Server 2022 | SQL Server 2025 |
|--------------------------|---------------------------------|:---------------:|:---------------:|
| `DatabaseBackup`         | Datenbanksicherungen            | ✅              | ✅              |
| `DatabaseIntegrityCheck` | Integritätsprüfungen (DBCC)     | ✅              | ✅              |
| `IndexOptimize`          | Index- und Statistikwartung     | ✅              | ✅              |

**Unterstützte Plattformen (2022/2025):** Windows Server, Linux (RHEL, Ubuntu, SUSE), Azure SQL Managed Instance, Container (Docker/Kubernetes).

---

## Installation

```sql
-- 1. Skript herunterladen und auf dem SQL Server ausführen:
--    https://ola.hallengren.com/scripts/MaintenanceSolution.sql
--
-- Das Skript erstellt automatisch:
--   - Alle drei Stored Procedures (dbo.DatabaseBackup, dbo.DatabaseIntegrityCheck, dbo.IndexOptimize)
--   - Die Logging-Tabelle dbo.CommandLog
--   - Vorkonfigurierte SQL Agent Jobs (T-SQL-Jobschritte für SQL Server 2017+)
```

---

## 1. DatabaseBackup – Datenbanksicherung

Führt vollständige, differenzielle oder Transaktionslog-Backups durch. Unterstützt lokale Verzeichnisse, Netzwerkfreigaben, Azure Blob Storage und AWS S3.

### Wichtigste Parameter

| Parameter                        | Beschreibung                                                                                       | 2022 | 2025 |
|----------------------------------|----------------------------------------------------------------------------------------------------|:----:|:----:|
| `@Databases`                     | Datenbankauswahl (`USER_DATABASES`, `ALL_DATABASES`, Wildcards mit `%`, Ausschluss mit `-`)        | ✅   | ✅   |
| `@Directory`                     | Backup-Zielverzeichnis (lokal oder UNC); mehrere Verzeichnisse mit Komma trennen                   | ✅   | ✅   |
| `@URL`                           | Backup zu Azure Blob Storage oder AWS S3                                                           | ✅   | ✅   |
| `@BackupType`                    | `FULL`, `DIFF` oder `LOG`                                                                          | ✅   | ✅   |
| `@Compress`                      | `Y` / `N` – Komprimierung aktivieren                                                               | ✅   | ✅   |
| `@CompressionAlgorithm`          | `MS_XPRESS`, `QAT_DEFLATE` (Intel QAT), `ZSTD` *(neu in SQL Server 2025)*                          | ⚠️   | ✅   |
| `@CompressionLevel`              | `LOW`, `MEDIUM`, `HIGH` – Kompressionsstärke (gilt für ZSTD)                                       | –    | ✅   |
| `@Verify`                        | `Y` – Backup nach Erstellung verifizieren (`RESTORE VERIFYONLY`)                                   | ✅   | ✅   |
| `@Checksum`                      | `Y` – Prüfsummen aktivieren                                                                        | ✅   | ✅   |
| `@CleanupTime`                   | Alter in Stunden, nach dem alte Backup-Dateien gelöscht werden                                     | ✅   | ✅   |
| `@Encrypt`                       | `Y` – Backup verschlüsseln                                                                         | ✅   | ✅   |
| `@EncryptionAlgorithm`           | `AES_128`, `AES_192`, `AES_256`, `TRIPLE_DES_3KEY`                                                 | ✅   | ✅   |
| `@ServerCertificate`             | Zertifikat für die Backup-Verschlüsselung                                                          | ✅   | ✅   |
| `@ChangeBackupType`              | `Y` – Backup-Typ automatisch anpassen, wenn DIFF/LOG nicht möglich ist                             | ✅   | ✅   |
| `@NumberOfFiles`                 | Anzahl paralleler Backup-Dateien (max. 64)                                                         | ✅   | ✅   |
| `@MinBackupSizeForMultipleFiles` | Mindestgröße in MB, ab der auf mehrere Dateien gesichert wird                                      | ✅   | ✅   |
| `@MaxFileSize`                   | Maximale Dateigröße in MB (Dateianzahl wird dynamisch berechnet)                                   | ✅   | ✅   |
| `@MinModificationLevel`          | DIFF → FULL-Wechsel ab X % Datenbankänderung                                                       | ✅   | ✅   |
| `@MinLogSizeSinceLastLogBackup`  | Mindestgröße des Logs in MB seit letztem Log-Backup (Smart Log Backup)                             | ✅   | ✅   |
| `@MinTimeSinceLastLogBackup`     | Mindestzeitabstand in Sekunden seit letztem Log-Backup (kombiniert mit obigem)                     | ✅   | ✅   |
| `@AvailabilityGroups`            | Backup auf Availability-Group-Ebene auswählen                                                      | ✅   | ✅   |
| `@AllowNonCopyOnlyBackupsOnForwarder` | Non-Copy-Only Backups auf Distributed AG Forwarder *(SQL Server 2025)*                        | –    | ✅   |
| `@DatabasesInParallel`           | `Y` – Mehrere Datenbanken parallel sichern                                                         | ✅   | ✅   |
| `@LogToTable`                    | `Y` – Befehle in `dbo.CommandLog` protokollieren                                                   | ✅   | ✅   |
| `@Execute`                       | `N` – Nur Befehle ausgeben, nicht ausführen (Testmodus)                                            | ✅   | ✅   |

> ⚠️ `ZSTD` und `@CompressionLevel` sind ausschliesslich in SQL Server 2025 verfügbar.

---

### Beispiele – DatabaseBackup

```sql
-- ============================================================
-- A) Standard FULL Backup (SQL Server 2022 & 2025)
--    Komprimiert, verifiziert, Checksumme, 24h Aufbewahrung
-- ============================================================
EXECUTE dbo.DatabaseBackup
  @Databases    = 'USER_DATABASES',
  @Directory    = 'C:\Backup',
  @BackupType   = 'FULL',
  @Compress     = 'Y',
  @Checksum     = 'Y',
  @Verify       = 'Y',
  @CleanupTime  = 24,
  @LogToTable   = 'Y';

-- ============================================================
-- B) FULL Backup mit ZSTD-Komprimierung (nur SQL Server 2025)
--    Deutlich effizientere Komprimierung als MS_XPRESS
-- ============================================================
EXECUTE dbo.DatabaseBackup
  @Databases            = 'USER_DATABASES',
  @Directory            = 'C:\Backup',
  @BackupType           = 'FULL',
  @Compress             = 'Y',
  @CompressionAlgorithm = 'ZSTD',
  @CompressionLevel     = 'MEDIUM',
  @Checksum             = 'Y',
  @Verify               = 'Y',
  @CleanupTime          = 48,
  @LogToTable           = 'Y';

-- ============================================================
-- C) FULL Backup – verschlüsselt mit AES_256 (2022 & 2025)
-- ============================================================
EXECUTE dbo.DatabaseBackup
  @Databases           = 'USER_DATABASES',
  @Directory           = 'C:\Backup',
  @BackupType          = 'FULL',
  @Compress            = 'Y',
  @Checksum            = 'Y',
  @Verify              = 'Y',
  @Encrypt             = 'Y',
  @EncryptionAlgorithm = 'AES_256',
  @ServerCertificate   = 'MyCertificate',
  @LogToTable          = 'Y';

-- ============================================================
-- D) Smart Backup auf mehrere Dateien (2022 & 2025)
--    Datenbanken >= 10 GB → 8 Dateien, kleinere → 1 Datei
-- ============================================================
EXECUTE dbo.DatabaseBackup
  @Databases                    = 'USER_DATABASES',
  @Directory                    = 'C:\Backup',
  @BackupType                   = 'FULL',
  @Compress                     = 'Y',
  @Checksum                     = 'Y',
  @NumberOfFiles                = 8,
  @MinBackupSizeForMultipleFiles = 10240,
  @LogToTable                   = 'Y';

-- ============================================================
-- E) Backup zu Azure Blob Storage (2022 & 2025)
-- ============================================================
EXECUTE dbo.DatabaseBackup
  @Databases  = 'USER_DATABASES',
  @URL        = 'https://myaccount.blob.core.windows.net/mycontainer',
  @Credential = 'MyCredential',
  @BackupType = 'FULL',
  @Compress   = 'Y',
  @Checksum   = 'Y',
  @Verify     = 'Y',
  @LogToTable = 'Y';

-- ============================================================
-- F) Backup zu AWS S3 (2022 & 2025)
-- ============================================================
EXECUTE dbo.DatabaseBackup
  @Databases       = 'USER_DATABASES',
  @URL             = 's3://myaccount.s3.us-east-1.amazonaws.com/mybucket',
  @BackupType      = 'FULL',
  @Compress        = 'Y',
  @Checksum        = 'Y',
  @Verify          = 'Y',
  @MaxTransferSize = 20971520,
  @BackupOptions   = '{"s3": {"region":"us-east-1"}}',
  @LogToTable      = 'Y';

-- ============================================================
-- G) Differenzielles Backup mit Smart-Fallback (2022 & 2025)
--    Wechsel zu FULL wenn >50 % der Datenbank geändert wurde
-- ============================================================
EXECUTE dbo.DatabaseBackup
  @Databases            = 'USER_DATABASES',
  @Directory            = 'C:\Backup',
  @BackupType           = 'DIFF',
  @Compress             = 'Y',
  @Checksum             = 'Y',
  @ChangeBackupType     = 'Y',
  @MinModificationLevel = 50,
  @LogToTable           = 'Y';

-- ============================================================
-- H) Transaktionslog-Backup mit automatischem Fallback (2022 & 2025)
--    Backup nur wenn >= 1 GB Log generiert ODER >= 300 Sek. vergangen
-- ============================================================
EXECUTE dbo.DatabaseBackup
  @Databases                   = 'USER_DATABASES',
  @Directory                   = 'C:\Backup',
  @BackupType                  = 'LOG',
  @Compress                    = 'Y',
  @ChangeBackupType            = 'Y',
  @MinLogSizeSinceLastLogBackup = 1024,
  @MinTimeSinceLastLogBackup   = 300,
  @LogToTable                  = 'Y';

-- ============================================================
-- I) Backup auf Availability Group (2022 & 2025)
-- ============================================================
EXECUTE dbo.DatabaseBackup
  @AvailabilityGroups = 'AG1',
  @Directory          = 'C:\Backup',
  @BackupType         = 'FULL',
  @Compress           = 'Y',
  @Checksum           = 'Y',
  @Verify             = 'Y',
  @LogToTable         = 'Y';

-- ============================================================
-- J) Mirror Backup auf zwei Verzeichnisse (2022 & 2025)
-- ============================================================
EXECUTE dbo.DatabaseBackup
  @Databases         = 'USER_DATABASES',
  @Directory         = 'C:\Backup',
  @MirrorDirectory   = 'D:\BackupMirror',
  @BackupType        = 'FULL',
  @Compress          = 'Y',
  @Checksum          = 'Y',
  @Verify            = 'Y',
  @CleanupTime       = 24,
  @MirrorCleanupTime = 48,
  @LogToTable        = 'Y';
```

---

## 2. DatabaseIntegrityCheck – Integritätsprüfung

Führt DBCC-Konsistenzprüfungen auf Datenbank-, Dateigruppen- oder Tabellenebene durch. In SQL Server 2022/2025 können Integrity Checks parallel auf mehreren Replikaten einer Availability Group verteilt werden.

### Wichtigste Parameter

| Parameter                    | Beschreibung                                                                                      | 2022 | 2025 |
|------------------------------|---------------------------------------------------------------------------------------------------|:----:|:----:|
| `@Databases`                 | Datenbankauswahl (wie bei DatabaseBackup)                                                         | ✅   | ✅   |
| `@CheckCommands`             | `CHECKDB`, `CHECKFILEGROUP`, `CHECKTABLE`, `CHECKALLOC`, `CHECKCATALOG` oder Kombinationen        | ✅   | ✅   |
| `@PhysicalOnly`              | `Y` – Nur physische Strukturen prüfen (schneller, empfohlen für sehr grosse DBs)                  | ✅   | ✅   |
| `@NoIndex`                   | `Y` – Non-Clustered Indexes von der Prüfung ausschliessen                                         | ✅   | ✅   |
| `@ExtendedLogicalChecks`     | `Y` – Erweiterte logische Prüfungen (kann nicht mit `@PhysicalOnly` kombiniert werden)            | ✅   | ✅   |
| `@DataPurity`                | `Y` – Ungültige oder ausserhalb des Wertebereichs liegende Spaltenwerte prüfen                    | ✅   | ✅   |
| `@TabLock`                   | `Y` – Sperren statt internem Datenbank-Snapshot verwenden                                         | ✅   | ✅   |
| `@MaxDOP`                    | Anzahl CPUs für die Prüfung (Standard: global konfigurierter MAXDOP-Wert)                         | ✅   | ✅   |
| `@FileGroups`                | Dateigruppen für `CHECKFILEGROUP` (z. B. `MeineDB.PRIMARY`)                                      | ✅   | ✅   |
| `@Objects`                   | Tabellen für `CHECKTABLE` (z. B. `MeineDB.dbo.Tabelle`)                                          | ✅   | ✅   |
| `@AvailabilityGroups`        | Availability Groups auswählen                                                                     | ✅   | ✅   |
| `@AvailabilityGroupReplicas` | `ALL`, `PRIMARY`, `SECONDARY`, `PREFERRED_BACKUP_REPLICA`                                        | ✅   | ✅   |
| `@TimeLimit`                 | Maximale Laufzeit in Sekunden                                                                     | ✅   | ✅   |
| `@LockTimeout`               | Wartezeit in Sekunden auf eine Sperre, bevor der Befehl abbricht                                  | ✅   | ✅   |
| `@DatabaseOrder`             | Reihenfolge der Prüfung (z. B. nach letztem guten Check: `DATABASE_LAST_GOOD_CHECK_ASC`)         | ✅   | ✅   |
| `@DatabasesInParallel`       | `Y` – Mehrere Datenbanken parallel prüfen                                                         | ✅   | ✅   |
| `@LogToTable`                | `Y` – Befehle in `dbo.CommandLog` protokollieren                                                  | ✅   | ✅   |

---

### Beispiele – DatabaseIntegrityCheck

```sql
-- ============================================================
-- A) Vollständige Integritätsprüfung aller User-Datenbanken
-- ============================================================
EXECUTE dbo.DatabaseIntegrityCheck
  @Databases     = 'USER_DATABASES',
  @CheckCommands = 'CHECKDB',
  @LogToTable    = 'Y';

-- ============================================================
-- B) Nur physische Strukturen prüfen (empfohlen für VLDBs)
--    Deutlich schneller, deckt Hardware-Fehler ab
-- ============================================================
EXECUTE dbo.DatabaseIntegrityCheck
  @Databases     = 'USER_DATABASES',
  @CheckCommands = 'CHECKDB',
  @PhysicalOnly  = 'Y',
  @LogToTable    = 'Y';

-- ============================================================
-- C) Erweiterte logische Prüfungen (2022 & 2025)
--    Prüft auch indizierte Views, XML-Indizes etc.
-- ============================================================
EXECUTE dbo.DatabaseIntegrityCheck
  @Databases            = 'USER_DATABASES',
  @CheckCommands        = 'CHECKDB',
  @ExtendedLogicalChecks = 'Y',
  @LogToTable           = 'Y';

-- ============================================================
-- D) Auf Availability Group Secondary Replica prüfen (2022 & 2025)
--    Entlastet den Primary vollständig
-- ============================================================
EXECUTE dbo.DatabaseIntegrityCheck
  @Databases                = 'USER_DATABASES',
  @CheckCommands            = 'CHECKDB',
  @AvailabilityGroups       = 'AG1',
  @AvailabilityGroupReplicas = 'SECONDARY',
  @LogToTable               = 'Y';

-- ============================================================
-- E) Prüfung priorisiert nach ältestem letztem Check (2022 & 2025)
--    Sichert, dass keine DB lange ohne Check bleibt
-- ============================================================
EXECUTE dbo.DatabaseIntegrityCheck
  @Databases     = 'USER_DATABASES',
  @CheckCommands = 'CHECKDB',
  @DatabaseOrder = 'DATABASE_LAST_GOOD_CHECK_ASC',
  @TimeLimit     = 7200,  -- max. 2 Stunden
  @LogToTable    = 'Y';

-- ============================================================
-- F) Bestimmte Dateigruppe prüfen
-- ============================================================
EXECUTE dbo.DatabaseIntegrityCheck
  @Databases     = 'AdventureWorks',
  @CheckCommands = 'CHECKFILEGROUP',
  @FileGroups    = 'AdventureWorks.PRIMARY',
  @LogToTable    = 'Y';

-- ============================================================
-- G) Bestimmte Tabelle prüfen
-- ============================================================
EXECUTE dbo.DatabaseIntegrityCheck
  @Databases     = 'AdventureWorks',
  @CheckCommands = 'CHECKTABLE',
  @Objects       = 'AdventureWorks.Production.Product',
  @LogToTable    = 'Y';

-- ============================================================
-- H) Allokation + Katalog prüfen (leichtgewichtig, für täglich)
-- ============================================================
EXECUTE dbo.DatabaseIntegrityCheck
  @Databases     = 'USER_DATABASES',
  @CheckCommands = 'CHECKALLOC,CHECKCATALOG',
  @LogToTable    = 'Y';
```

---

## 3. IndexOptimize – Index- und Statistikwartung

Führt intelligente Index-Rebuilds oder -Reorganisierungen durch und aktualisiert Statistiken basierend auf dem aktuellen Fragmentierungsgrad. SQL Server 2022/2025 unterstützt unterbrechbare Online-Rebuilds nativ – das verbessert die Planbarkeit in Wartungsfenstern erheblich.

### Wichtigste Parameter

| Parameter                  | Beschreibung                                                                                       | 2022 | 2025 |
|----------------------------|----------------------------------------------------------------------------------------------------|:----:|:----:|
| `@Databases`               | Datenbankauswahl (wie bei DatabaseBackup)                                                          | ✅   | ✅   |
| `@FragmentationLow`        | Aktion bei niedrigem Fragmentierungsgrad (Standard: `NULL` = keine Aktion)                         | ✅   | ✅   |
| `@FragmentationMedium`     | Aktion bei mittlerem Fragmentierungsgrad                                                           | ✅   | ✅   |
| `@FragmentationHigh`       | Aktion bei hohem Fragmentierungsgrad                                                               | ✅   | ✅   |
| `@FragmentationLevel1`     | Grenzwert in % für niedrig → mittel (Standard: 5 %)                                                | ✅   | ✅   |
| `@FragmentationLevel2`     | Grenzwert in % für mittel → hoch (Standard: 30 %)                                                  | ✅   | ✅   |
| `@UpdateStatistics`        | `ALL`, `COLUMNS` oder `INDEX` – Statistiken aktualisieren                                          | ✅   | ✅   |
| `@OnlyModifiedStatistics`  | `Y` – Nur Statistiken aktualisieren, wenn Zeilen geändert wurden                                   | ✅   | ✅   |
| `@Resumable`               | `Y` – Unterbrechbare Online Index-Rebuilds (bei Abbruch fortsetzbar)                               | ✅   | ✅   |
| `@Indexes`                 | Bestimmte Indexes auswählen oder ausschliessen                                                     | ✅   | ✅   |
| `@TimeLimit`               | Maximale Laufzeit in Sekunden (Index-Job läuft max. X Sek., dann Pause)                            | ✅   | ✅   |
| `@LockTimeout`             | Wartezeit auf Sperre in Sekunden                                                                   | ✅   | ✅   |
| `@DatabaseOrder`           | Reihenfolge der Datenbanken                                                                        | ✅   | ✅   |
| `@DatabasesInParallel`     | `Y` – Mehrere Datenbanken parallel bearbeiten                                                      | ✅   | ✅   |
| `@LogToTable`              | `Y` – Befehle in `dbo.CommandLog` protokollieren                                                   | ✅   | ✅   |

Aktionswerte für Fragmentierungsparameter:

| Wert                                                              | Bedeutung                                             |
|-------------------------------------------------------------------|-------------------------------------------------------|
| `NULL`                                                            | Keine Aktion                                          |
| `INDEX_REORGANIZE`                                                | Reorganisierung (online, keine Unterbrechung nötig)   |
| `INDEX_REBUILD_ONLINE`                                            | Online-Rebuild (Tabelle bleibt lesbar)                |
| `INDEX_REBUILD_OFFLINE`                                           | Offline-Rebuild (Tabelle gesperrt)                    |
| `INDEX_REORGANIZE,INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE`     | Priorisiert: Reorganize → Online → Offline            |
| `INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE`                      | Priorisiert: Online → Offline                         |

---

### Beispiele – IndexOptimize

```sql
-- ============================================================
-- A) Standard intelligente Index-Wartung (2022 & 2025)
--    5–30 %  → Reorganize
--    > 30 %  → Online-Rebuild (Offline als Fallback)
--    < 5 %   → keine Aktion
-- ============================================================
EXECUTE dbo.IndexOptimize
  @Databases           = 'USER_DATABASES',
  @FragmentationLow    = NULL,
  @FragmentationMedium = 'INDEX_REORGANIZE,INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE',
  @FragmentationHigh   = 'INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE',
  @FragmentationLevel1 = 5,
  @FragmentationLevel2 = 30,
  @LogToTable          = 'Y';

-- ============================================================
-- B) Index-Wartung + Statistiken aktualisieren (2022 & 2025)
--    Nur Statistiken mit Änderungen werden aktualisiert
-- ============================================================
EXECUTE dbo.IndexOptimize
  @Databases              = 'USER_DATABASES',
  @FragmentationLow       = NULL,
  @FragmentationMedium    = 'INDEX_REORGANIZE,INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE',
  @FragmentationHigh      = 'INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE',
  @FragmentationLevel1    = 5,
  @FragmentationLevel2    = 30,
  @UpdateStatistics       = 'ALL',
  @OnlyModifiedStatistics = 'Y',
  @LogToTable             = 'Y';

-- ============================================================
-- C) Unterbrechbare Online-Rebuilds (2022 & 2025)
--    Abgebrochene Rebuilds können später fortgesetzt werden
--    Ideal für knappe Wartungsfenster
-- ============================================================
EXECUTE dbo.IndexOptimize
  @Databases           = 'USER_DATABASES',
  @FragmentationLow    = NULL,
  @FragmentationMedium = 'INDEX_REORGANIZE,INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE',
  @FragmentationHigh   = 'INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE',
  @FragmentationLevel1 = 5,
  @FragmentationLevel2 = 30,
  @Resumable           = 'Y',
  @LogToTable          = 'Y';

-- ============================================================
-- D) Index-Wartung mit Zeitlimit (2022 & 2025)
--    Stoppt nach 2 Stunden – Rest beim nächsten Lauf
--    Optimal in Kombination mit @Resumable = 'Y'
-- ============================================================
EXECUTE dbo.IndexOptimize
  @Databases           = 'USER_DATABASES',
  @FragmentationLow    = NULL,
  @FragmentationMedium = 'INDEX_REORGANIZE,INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE',
  @FragmentationHigh   = 'INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE',
  @FragmentationLevel1 = 5,
  @FragmentationLevel2 = 30,
  @Resumable           = 'Y',
  @TimeLimit           = 7200,  -- 2 Stunden
  @LogToTable          = 'Y';

-- ============================================================
-- E) Nur Statistiken aktualisieren – kein Index-Rebuild
--    Inkl. inkrementeller Statistiken auf Partitionen (2022 & 2025)
-- ============================================================
EXECUTE dbo.IndexOptimize
  @Databases              = 'USER_DATABASES',
  @FragmentationLow       = NULL,
  @FragmentationMedium    = NULL,
  @FragmentationHigh      = NULL,
  @UpdateStatistics       = 'ALL',
  @OnlyModifiedStatistics = 'Y',
  @LogToTable             = 'Y';

-- ============================================================
-- F) Nur bestimmte Datenbank und bestimmte Indizes warten
-- ============================================================
EXECUTE dbo.IndexOptimize
  @Databases           = 'AdventureWorks',
  @Indexes             = 'AdventureWorks.Sales.%',  -- alle Indizes im Schema Sales
  @FragmentationLow    = NULL,
  @FragmentationMedium = 'INDEX_REORGANIZE,INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE',
  @FragmentationHigh   = 'INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE',
  @FragmentationLevel1 = 5,
  @FragmentationLevel2 = 30,
  @LogToTable          = 'Y';
```

---

## Logging & Monitoring

Alle drei Stored Procedures schreiben in die Tabelle `dbo.CommandLog`, wenn `@LogToTable = 'Y'` gesetzt ist.

```sql
-- Alle ausgeführten Wartungsbefehle anzeigen
SELECT
  DatabaseName,
  SchemaName,
  ObjectName,
  ObjectType,
  IndexName,
  StatisticsName,
  PartitionNumber,
  ExtendedInfo,
  Command,
  CommandType,
  StartTime,
  EndTime,
  DATEDIFF(SECOND, StartTime, EndTime) AS DurationSec,
  ErrorNumber,
  ErrorMessage
FROM dbo.CommandLog
ORDER BY StartTime DESC;

-- Fehlgeschlagene Befehle der letzten 7 Tage
SELECT *
FROM dbo.CommandLog
WHERE ErrorNumber <> 0
  AND StartTime >= DATEADD(DAY, -7, GETDATE())
ORDER BY StartTime DESC;

-- Letzter erfolgreicher CHECKDB pro Datenbank
SELECT DatabaseName, MAX(EndTime) AS LastSuccessfulCheck
FROM dbo.CommandLog
WHERE CommandType = 'CHECKDB'
  AND ErrorNumber = 0
GROUP BY DatabaseName
ORDER BY LastSuccessfulCheck ASC;
```

---

## Empfohlener Wartungsplan (SQL Server 2022 / 2025)

| Job                         | Häufigkeit          | Stored Procedure / Aktion                    |
|-----------------------------|---------------------|----------------------------------------------|
| Full Backup                 | Täglich (z. B. 22 Uhr) | `DatabaseBackup` `@BackupType = 'FULL'`   |
| Differenzielles Backup      | Alle 6 Stunden      | `DatabaseBackup` `@BackupType = 'DIFF'`      |
| Log-Backup                  | Alle 15–30 Min.     | `DatabaseBackup` `@BackupType = 'LOG'`       |
| Integritätsprüfung (CHECKDB)| Wöchentlich (So.)   | `DatabaseIntegrityCheck` `@CheckCommands = 'CHECKDB'` |
| Index- & Statistikwartung   | Wöchentlich (Sa.)   | `IndexOptimize` mit Fragmentierungslogik     |
| Statistiken aktualisieren   | Täglich (nach Backup) | `IndexOptimize` `@UpdateStatistics = 'ALL'` |

---

## Ausführung via SQL Agent (SQL Server 2022 / 2025)

SQL Server 2022 und 2025 nutzen ausschliesslich **T-SQL-Jobschritte** – kein CmdExec/sqlcmd mehr nötig.

```sql
-- SQL Agent Job-Schritt (T-SQL) – Beispiel Full Backup
EXECUTE dbo.DatabaseBackup
  @Databases   = 'USER_DATABASES',
  @Directory   = 'C:\Backup',
  @BackupType  = 'FULL',
  @Compress    = 'Y',
  @Checksum    = 'Y',
  @Verify      = 'Y',
  @CleanupTime = 24,
  @LogToTable  = 'Y';
```

`MaintenanceSolution.sql` erstellt bei der Installation alle Jobs automatisch mit T-SQL-Jobschritten.

---
