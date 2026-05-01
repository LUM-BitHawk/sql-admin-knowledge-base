# SQL msdb delete verwaiste Einträge löschen

Um verwaiste Einträge in der msdb-Datenbank des SQL Servers zu löschen – meistens handelt es sich um Job-Historien, Backup-Verläufe oder Agent-Benutzer –, sollten Sie gezielte DELETE-Statements verwenden. 

**Hinweis:** Die msdb ist eine Systemdatenbank, daher ist Vorsicht geboten. 

Hier sind die gängigsten Methoden, um verwaiste Daten zu bereinigen:
1. SQL Server Agent Historie löschen (Der häufigste Fall)
Wenn Jobs gelöscht wurden, aber deren Verlauf in sysjobhistory verbleibt, können Sie alte Einträge mit sp_purge_jobhistory entfernen. 

```sql
USE msdb;
GO
-- Löscht die gesamte Historie, die älter als 30 Tage ist
EXEC dbo.sp_purge_jobhistory @oldest_date = '2026-04-01'; 
GO
```

-- **Alternativ:** Löscht die Historie eines bestimmten Jobs

```sql
EXEC dbo.sp_purge_jobhistory @job_name = 'MeinJobName';
GO
```

2. Verwaiste Backup- und Wiederherstellungsverläufe
Einträge in backupmediafamily, backupset etc., die keinen Bezug mehr zu existierenden Datenbanken haben, können bereinigt werden.

```sql
USE msdb;
GO
-- Löscht Backup-Verlauf älter als 60 Tage
EXEC sp_delete_backuphistory @oldest_date = '2026-03-01';
GO
```

3. Verwaiste Agent-Benutzer beheben
Wenn ein Login gelöscht wurde, aber der Benutzer in der msdb (oder einer anderen Datenbank) verbleibt, ist er "verwaist". 
Identifizieren:

```sql
USE msdb;
GO
EXEC sp_change_users_login 'Report';
GO
```


Reparieren (neu verknüpfen):

```sql
USE msdb;
GO
ALTER USER [VerwaisterBenutzer] WITH Login = [VorhandenerLogin];
GO
```


Wichtige Hinweise
• Backup: Erstellen Sie vor dem Löschen in Systemdatenbanken unbedingt eine Sicherung.
• Kein TRUNCATE: Verwenden Sie DELETE mit WHERE-Klauseln, um keine wichtigen Protokolldaten zu verlieren.
Reihenfolge: Bei manuellen Löschungen aus Systemtabellen (nicht empfohlen) ist auf Fremdschlüsselbeziehungen zu achten. 