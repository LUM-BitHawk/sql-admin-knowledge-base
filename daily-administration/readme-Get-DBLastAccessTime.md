# Get-DBLastAccessTime

## Zweck

Ermittelt für **alle Datenbanken** auf einem SQL Server den Zeitpunkt des letzten Benutzerzugriffs (Seek, Scan, Lookup, Update). Nützlich für die Identifikation ungenutzter Datenbanken bei Konsolidierungen oder Migrationen.

## Abfrage

```sql
SELECT
    d.name                          AS DatabaseName,
    MAX(s.last_user_seek)           AS LastSeek,
    MAX(s.last_user_scan)           AS LastScan,
    MAX(s.last_user_lookup)         AS LastLookup,
    MAX(s.last_user_update)         AS LastUpdate,
    -- Ein einzelner Wert: der letzte Zugriff über alle Typen hinweg
    (SELECT MAX(v)
     FROM (VALUES
         (MAX(s.last_user_seek)),
         (MAX(s.last_user_scan)),
         (MAX(s.last_user_lookup)),
         (MAX(s.last_user_update))
     ) AS dates(v)
    )                               AS LastAccess
FROM sys.databases AS d
LEFT JOIN sys.dm_db_index_usage_stats AS s
    ON d.database_id = s.database_id
GROUP BY d.name
ORDER BY LastAccess DESC;
```

### Erklärung VALUES-Trick

`VALUES` erzeugt eine virtuelle Tabelle aus den vier Datumswerten. `MAX(v)` darüber liefert den jüngsten Zeitpunkt – ohne verschachtelte Subqueries oder `UNION ALL`.

## Beispielausgabe

| DatabaseName | LastSeek | LastScan | LastLookup | LastUpdate | LastAccess |
|---|---|---|---|---|---|
| AppDB | 2026-05-17 08:12 | 2026-05-17 09:01 | 2026-05-16 14:30 | 2026-05-17 09:01 | 2026-05-17 09:01 |
| ArchiveDB | NULL | 2025-11-03 11:00 | NULL | NULL | 2025-11-03 11:00 |
| UnusedDB | NULL | NULL | NULL | NULL | NULL |

## Voraussetzungen

- SQL Server 2008 oder höher (für `VALUES`-Syntax)
- Berechtigung: `VIEW SERVER STATE`
- `sys.dm_db_index_usage_stats` wird bei SQL-Server-Neustart zurückgesetzt – Werte gelten nur seit dem letzten Start

## Hinweise

- **DMV-Reset**: Die Statistiken gehen bei jedem Neustart des SQL-Dienstes verloren. Für langfristige Auswertungen die Ergebnisse regelmäßig in eine Protokolltabelle schreiben.
- **Systemdatenbanken ausschließen**: Optional `WHERE d.database_id > 4` ergänzen.
- **Nur „tote" DBs finden**: `HAVING MAX(s.last_user_seek) IS NULL AND MAX(s.last_user_scan) IS NULL ...` anhängen.
