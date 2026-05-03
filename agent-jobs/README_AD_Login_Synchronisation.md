# BitHawk AD Login Synchronisation

Dieses SQL-Skript synchronisiert Windows-Logins und Active-Directory-Gruppen mit dem SQL Server. Es erkennt verwaiste Konten, deren AD-Eintraege in der Domaene geloescht wurden, und entfernt diese automatisch. Ein SQL Agent Job fuehrt die Synchronisation woechentlich aus.

---

## 🛠️ Verwendung

**DryRun ausfuehren** (nur pruefen, nichts loeschen):

```sql
EXEC master.dbo.usp_AD_Login_Sync @DryRun = 1, @VerboseLog = 1;
```

**Manuell ausfuehren** (Aenderungen werden durchgefuehrt):

```sql
EXEC master.dbo.usp_AD_Login_Sync @DryRun = 0, @VerboseLog = 1;
```

**Job sofort starten:**

```sql
EXEC msdb.dbo.sp_start_job N'BitHawk_AD_Login_Synchronisation';
```

**Log pruefen:**

```sql
SELECT * FROM master.dbo.AD_Login_Sync_Log ORDER BY LogID DESC;
```

---

## Architektur

Das Skript besteht aus einer Stored Procedure und einem SQL Agent Job, die zusammenarbeiten:

```
SQL Agent Job (Montag 05:00)
│
├── Schritt 1: EXEC usp_AD_Login_Sync
│   ├── A) Windows-Logins und -Gruppen aus sys.server_principals sammeln
│   ├── B) Jedes Konto via xp_logininfo gegen AD pruefen
│   ├── C) Verwaiste Logins und zugehoerige DB-Benutzer entfernen
│   ├── D) AD-Gruppen-Mitgliedschaften aktualisieren
│   └── E) Zusammenfassung in Log-Tabelle schreiben
│
└── Schritt 2: Sync-Bericht ausgeben / Fehler melden
```

Die Ergebnisse werden in der Tabelle `master.dbo.AD_Login_Sync_Log` protokolliert. Log-Eintraege aelter als 90 Tage werden automatisch bereinigt.

---

## 🚀 Installation

### Voraussetzungen

- **sysadmin**-Berechtigung auf dem SQL Server
- SQL Server Agent muss aktiv sein
- `xp_logininfo` muss verfuegbar sein (Standard bei Windows-Authentifizierung)

### Ausfuehrung

1. Das gesamte Skript `AD_Login_Sync_Weekly_Job.sql` auf dem Ziel-SQL-Server oeffnen (z. B. in SQL Server Management Studio).
2. Das Skript vollstaendig ausfuehren.
3. Die Ausgabe im Meldungsfenster pruefen — bei Erfolg erscheint:
   - `✓ Stored Procedure [dbo].[usp_AD_Login_Sync] erstellt.`
   - `✓ SQL Agent Job "BitHawk_AD_Login_Synchronisation" erstellt.`
4. Optional einen DryRun starten, um die Funktion zu testen, bevor der Job produktiv laeuft.

---

### Komponenten

| Objekt | Typ | Beschreibung |
|---|---|---|
| `master.dbo.usp_AD_Login_Sync` | Stored Procedure | Kernlogik: prueft Windows-Logins gegen AD, entfernt verwaiste Konten, aktualisiert Gruppen-Mitgliedschaften. |
| `master.dbo.AD_Login_Sync_Log` | Tabelle | Protokolltabelle fuer alle Aktionen und Fehler. Wird beim ersten Lauf automatisch erstellt. |
| `BitHawk_AD_Login_Synchronisation` | SQL Agent Job | Zeitgesteuerter Job, der die Stored Procedure jeden Montag um 05:00 Uhr ausfuehrt. |

---

### Deinstallation

```sql
EXEC msdb.dbo.sp_delete_job @job_name = N'BitHawk_AD_Login_Synchronisation';
DROP PROCEDURE master.dbo.usp_AD_Login_Sync;
DROP TABLE master.dbo.AD_Login_Sync_Log;
```
