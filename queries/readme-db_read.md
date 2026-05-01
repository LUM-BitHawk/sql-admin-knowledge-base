
# SQL-Datenbank schreibgeschützt zu machen

Das Festlegen einer SQL-Datenbank insb. MS SQL Server als schreibgeschützt („Read-Only“) verhindert Änderungen an Daten und Struktur.

Verwenden Sie den folgenden Befehl, um die gesamte Datenbank schreibgeschützt zu machen:
```sql
ALTER DATABASE <Datenbankname> SET READ_ONLY
```

Verwenden Sie diesen Befehl, um die Datenbank schreibgeschützt zu setzen:
```sql
ALTER DATABASE <Datenbankname> READ ONLY = 1;
```

Um dies rückgängig zu machen, verwenden Sie:
```sql
ALTER DATABASE <Datenbankname> READ ONLY = 0;
```