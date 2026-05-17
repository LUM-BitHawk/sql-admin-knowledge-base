
# tempdb plötzlich voll und muss handeln

Wenn die tempdb im SQL Server plötzlich voll ist, führt dies meist zum Abbruch von Abfragen. 

```sql
USE master;
GO
ALTER DATABASE tempdb MODIFY FILE ( NAME = templog, SIZE = 7GB, FILEGROWTH = 0 );
ALTER DATABASE tempdb MODIFY FILE ( NAME = tempdev, SIZE = 7GB, FILEGROWTH = 0 );
ALTER DATABASE tempdb MODIFY FILE ( NAME = temp2, SIZE = 7GB, FILEGROWTH = 0 );
ALTER DATABASE tempdb MODIFY FILE ( NAME = temp3, SIZE = 7GB, FILEGROWTH = 0 );
ALTER DATABASE tempdb MODIFY FILE ( NAME = temp4, SIZE = 7GB, FILEGROWTH = 0 );
```


Temp DB Abfragen

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