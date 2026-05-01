
#  SQL TempDB grösse ermitteln

Die Grösse der SQL Server tempdb kann schnell über SQL Server Management Studio (SSMS) oder per T-SQL Abfrage ermittelt werden. Da die tempdb bei jedem Neustart neu erstellt wird, ist eine Überwachung der aktuellen Grösse wichtig.

```sql
SELECT name AS file_name,
       type_desc AS file_type,
       size * 8.0 / 1024 AS size_mb,
       max_size * 8.0 / 1024 AS max_size_mb,
       CAST(IIF(max_size = 0, 0, 1) AS bit) AS is_autogrowth_enabled,
       CASE WHEN growth = 0 THEN growth
            WHEN growth > 0 AND is_percent_growth = 0 THEN growth * 8.0 / 1024
            WHEN growth > 0 AND is_percent_growth = 1 THEN growth
       END
       AS growth_increment_value,
       CASE WHEN growth = 0 THEN 'Autogrowth is disabled.'
            WHEN growth > 0 AND is_percent_growth = 0  THEN 'Megabytes'
            WHEN growth > 0 AND is_percent_growth = 1  THEN 'Percent'
       END
       AS growth_increment_value_unit
FROM tempdb.sys.database_files;
```


Shrinken 
```sql
ALTER DATABASE tempdb MODIFY FILE
(NAME = 'tempdev', SIZE = 2048MB);

ALTER DATABASE tempdb MODIFY FILE
(NAME = 'templog', SIZE = 2048MB);
```
