# SQL Server – Datenbankzugriff via DNS-Auflösung auf TCP-Ports 1433–1455

## Übersicht

Diese Anleitung beschreibt, wie mehrere SQL-Server-Instanzen über **DNS-Namen** auf den TCP-Ports **1433 bis 1455** erreichbar gemacht werden. Ziel ist, dass Clients die Verbindung allein über einen DNS-Namen aufbauen – ohne IP-Adressen, ohne SQL Browser Service und ohne Port-Angabe im Connection String.

---

## Ausgangslage

SQL Server verwendet standardmässig TCP-Port **1433** für die Default-Instanz. Benannte Instanzen erhalten dynamische Ports, die der **SQL Server Browser Service** (UDP 1434) an den Client vermittelt. Das bringt Nachteile in streng verwalteten Netzwerken: Firewall-Regeln für dynamische Ports sind schwer zu pflegen, und der Browser Service ist ein zusätzlicher Angriffspunkt.

Die Lösung: Jede Instanz erhält einen **festen TCP-Port** im Bereich 1433–1455 und einen eigenen **DNS-Eintrag** (CNAME oder A-Record), der auf den Server zeigt. Der Client verbindet sich über den DNS-Namen, und der Port wird entweder im Connection String angegeben oder über einen **DNS SRV-Record** aufgelöst.

---

## Schritt 1 – Feste TCP-Ports in SQL Server konfigurieren

Jede SQL-Instanz bekommt einen eigenen, statischen Port.

### 1.1 SQL Server Configuration Manager öffnen

```
Windows-Taste → "SQL Server Configuration Manager"
```

Alternativ via MMC:

```
mmc.exe → Snap-In hinzufügen → SQL Server Configuration Manager
```

### 1.2 TCP/IP-Port setzen

Für jede Instanz den folgenden Pfad navigieren:

```
SQL Server Network Configuration
  → Protocols for [INSTANZNAME]
    → TCP/IP → Rechtsklick → Properties
      → Tab "IP Addresses"
        → Abschnitt "IPAll"
```

Dort die Felder anpassen:

| Feld | Wert | Erklärung |
|---|---|---|
| **TCP Dynamic Ports** | *(leer lassen)* | Dynamischen Port deaktivieren |
| **TCP Port** | z. B. `1434` | Festen Port zuweisen |

**Wichtig**: Das Feld `TCP Dynamic Ports` muss komplett leer sein (nicht `0`). Eine `0` bedeutet „dynamisch zuweisen".

### 1.3 SQL-Server-Dienst neu starten

```powershell
Restart-Service -Name 'MSSQL$INSTANZNAME' -Force
```

### 1.4 Beispiel-Zuordnung

| Instanz | Zweck | TCP-Port |
|---|---|---|
| MSSQLSERVER (Default) | Produktion ERP | 1433 |
| MSSQL$APP01 | Applikation 01 | 1434 |
| MSSQL$APP02 | Applikation 02 | 1435 |
| MSSQL$REPORTING | Reporting | 1436 |
| MSSQL$TEST | Testumgebung | 1440 |
| MSSQL$DEV | Entwicklung | 1455 |

---

## Schritt 2 – DNS-Einträge erstellen

### Variante A: CNAME- oder A-Records (empfohlen für die meisten Umgebungen)

Im DNS-Server (z. B. Windows DNS, AD-integriert) für jede Instanz einen eigenen Hostnamen anlegen.

#### A-Record (wenn der Server eine feste IP hat)

```
sql-erp.firma.local        A       10.0.1.50
sql-app01.firma.local       A       10.0.1.50
sql-app02.firma.local       A       10.0.1.50
sql-reporting.firma.local   A       10.0.1.50
sql-test.firma.local        A       10.0.1.51
sql-dev.firma.local         A       10.0.1.51
```

Mehrere A-Records können auf dieselbe IP zeigen, wenn die Instanzen auf demselben Server laufen.

#### CNAME-Record (wenn auf einen bestehenden Hostnamen verwiesen wird)

```
sql-erp.firma.local        CNAME   sqlserver01.firma.local
sql-app01.firma.local       CNAME   sqlserver01.firma.local
```

#### Per PowerShell (AD-integriertes DNS)

```powershell
# A-Record erstellen
Add-DnsServerResourceRecordA `
    -ZoneName "firma.local" `
    -Name "sql-app01" `
    -IPv4Address "10.0.1.50"

# CNAME erstellen
Add-DnsServerResourceRecordCName `
    -ZoneName "firma.local" `
    -Name "sql-app01" `
    -HostNameAlias "sqlserver01.firma.local"
```

#### Auflösung testen

```powershell
Resolve-DnsName -Name sql-app01.firma.local
nslookup sql-app01.firma.local
```

### Variante B: DNS SRV-Records (Port-Auflösung ohne Connection-String-Anpassung)

SRV-Records ermöglichen es, den Port direkt im DNS zu hinterlegen. Der Client kann den Port dann automatisch auflösen, ohne ihn im Connection String angeben zu müssen.

#### SRV-Record-Format

```
_mssql._tcp.sql-app01.firma.local   SRV   0 0 1434 sqlserver01.firma.local
_mssql._tcp.sql-app02.firma.local   SRV   0 0 1435 sqlserver01.firma.local
```

| Feld | Bedeutung |
|---|---|
| `_mssql._tcp` | Service- und Protokoll-Bezeichner |
| `0 0` | Priorität und Gewichtung |
| `1434` | TCP-Port der Instanz |
| `sqlserver01.firma.local` | Zielhost |

#### Per PowerShell

```powershell
Add-DnsServerResourceRecord `
    -ZoneName "firma.local" `
    -Name "_mssql._tcp.sql-app01" `
    -Srv `
    -DomainName "sqlserver01.firma.local" `
    -Priority 0 `
    -Weight 0 `
    -Port 1434
```

**Hinweis**: Nicht alle SQL-Client-Bibliotheken unterstützen SRV-Auflösung nativ. SSMS und die meisten ODBC/OLE-DB-Treiber tun es nicht. SRV-Records eignen sich primär für Eigenentwicklungen, die die Auflösung selbst implementieren, oder für neuere Treiber (z. B. Microsoft.Data.SqlClient ab Version 5.x mit `ServerSPN`-Support).

---

## Schritt 3 – Connection Strings konfigurieren

### 3.1 Mit Port im Connection String (Standard-Methode)

Der Port wird mit einem **Komma** (nicht Doppelpunkt) nach dem Hostnamen angegeben.

```
Server=sql-app01.firma.local,1434;Database=MeineDB;Integrated Security=True;
```

| Anwendung | Syntax |
|---|---|
| **SSMS** | `sql-app01.firma.local,1434` im Feld "Server name" |
| **.NET (SqlClient)** | `Server=sql-app01.firma.local,1434;...` |
| **ODBC** | `Server=sql-app01.firma.local,1434;...` |
| **JDBC** | `jdbc:sqlserver://sql-app01.firma.local:1434;...` (Doppelpunkt!) |
| **Python (pyodbc)** | `Server=sql-app01.firma.local,1434;...` |
| **PowerShell** | `Invoke-Sqlcmd -ServerInstance "sql-app01.firma.local,1434"` |

**Achtung**: JDBC verwendet einen **Doppelpunkt** als Port-Trenner, alle anderen Microsoft-Treiber ein **Komma**.

### 3.2 Ohne Port (nur mit DNS-Alias auf Port 1433)

Wenn eine Instanz auf dem **Standard-Port 1433** läuft, reicht der DNS-Name allein:

```
Server=sql-erp.firma.local;Database=MeineDB;Integrated Security=True;
```

### 3.3 SQL Server Alias als Alternative (Client-seitig)

Falls der Port nicht im Connection String stehen soll und SRV-Records keine Option sind, kann auf jedem Client ein **SQL Server Alias** konfiguriert werden.

```
SQL Server Configuration Manager (Client)
  → SQL Native Client Configuration
    → Aliases → Rechtsklick → New Alias
```

| Feld | Wert |
|---|---|
| Alias Name | `sql-app01` |
| Protocol | TCP/IP |
| Server | `sql-app01.firma.local` |
| Port No | `1434` |

Oder per Registry/PowerShell für automatisierte Verteilung:

```powershell
# 64-Bit Alias
$RegPath = 'HKLM:\SOFTWARE\Microsoft\MSSQLServer\Client\ConnectTo'
if (-not (Test-Path $RegPath)) {
    New-Item -Path $RegPath -Force | Out-Null
}
New-ItemProperty -Path $RegPath `
    -Name 'sql-app01' `
    -Value 'DBMSSOCN,sql-app01.firma.local,1434' `
    -PropertyType String -Force

# 32-Bit Alias (für 32-Bit-Anwendungen auf 64-Bit-OS)
$RegPath32 = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\MSSQLServer\Client\ConnectTo'
if (-not (Test-Path $RegPath32)) {
    New-Item -Path $RegPath32 -Force | Out-Null
}
New-ItemProperty -Path $RegPath32 `
    -Name 'sql-app01' `
    -Value 'DBMSSOCN,sql-app01.firma.local,1434' `
    -PropertyType String -Force
```

`DBMSSOCN` steht für TCP/IP. Danach können Clients einfach `sql-app01` als Servernamen verwenden.

---

## Schritt 4 – Firewall-Regeln

Für jeden verwendeten Port eine eingehende Regel auf dem SQL Server erstellen.

### Windows Firewall per PowerShell

```powershell
# Einzelner Port
New-NetFirewallRule `
    -DisplayName "SQL Server - TCP 1434 (APP01)" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 1434 `
    -Action Allow `
    -Profile Domain

# Gesamter Bereich 1433-1455
New-NetFirewallRule `
    -DisplayName "SQL Server - TCP 1433-1455" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 1433-1455 `
    -Action Allow `
    -Profile Domain
```

### Optional: SQL Browser deaktivieren

Wenn alle Instanzen feste Ports haben und keine Clients den Browser benötigen:

```powershell
Stop-Service -Name 'SQLBrowser' -Force
Set-Service  -Name 'SQLBrowser' -StartupType Disabled
```

---

## Schritt 5 – Verbindung testen

### PowerShell

```powershell
# TCP-Port erreichbar?
Test-NetConnection -ComputerName sql-app01.firma.local -Port 1434

# SQL-Verbindung testen
Invoke-Sqlcmd -ServerInstance "sql-app01.firma.local,1434" `
              -Query "SELECT @@SERVERNAME AS Instance, @@VERSION AS Version"
```

### SSMS

Im Feld "Server name" eingeben:

```
sql-app01.firma.local,1434
```

### sqlcmd (Kommandozeile)

```cmd
sqlcmd -S sql-app01.firma.local,1434 -Q "SELECT @@SERVERNAME"
```

---

## Zusammenfassung: Gesamtübersicht

```
┌──────────────┐     DNS-Auflösung      ┌──────────────────────┐
│   Client     │ ──────────────────────► │  DNS Server          │
│              │  sql-app01.firma.local  │                      │
│  SSMS        │ ◄────────────────────── │  A: 10.0.1.50        │
│  .NET App    │     IP: 10.0.1.50      │  (opt. SRV: Port)    │
│  PowerShell  │                        └──────────────────────┘
└──────┬───────┘
       │
       │  TCP-Verbindung auf Port 1434
       ▼
┌──────────────────────────────────────────────────────┐
│  SQL Server Host: 10.0.1.50                          │
│                                                      │
│  ┌─────────────────────┐  ┌────────────────────────┐ │
│  │ Default Instance    │  │ APP01 Instance         │ │
│  │ TCP 1433            │  │ TCP 1434               │ │
│  └─────────────────────┘  └────────────────────────┘ │
│  ┌─────────────────────┐  ┌────────────────────────┐ │
│  │ APP02 Instance      │  │ REPORTING Instance     │ │
│  │ TCP 1435            │  │ TCP 1436               │ │
│  └─────────────────────┘  └────────────────────────┘ │
└──────────────────────────────────────────────────────┘
```

---

## Checkliste

- [ ] Feste TCP-Ports für alle Instanzen im SQL Server Configuration Manager gesetzt
- [ ] Feld "TCP Dynamic Ports" ist leer (nicht `0`)
- [ ] SQL-Dienste nach Port-Änderung neu gestartet
- [ ] DNS-Einträge (A oder CNAME) für jede Instanz erstellt
- [ ] DNS-Auflösung getestet (`Resolve-DnsName`, `nslookup`)
- [ ] Firewall-Regeln für die Ports 1433–1455 eingehend aktiv
- [ ] SQL Browser Service deaktiviert (falls nicht mehr benötigt)
- [ ] Connection Strings in allen Applikationen aktualisiert
- [ ] Verbindung via DNS-Name + Port aus Client-Netzwerk getestet
- [ ] Bei Kerberos: SPNs für die DNS-Aliase registriert (siehe Hinweise)

---

## Häufige Fehler

| Symptom | Ursache | Lösung |
|---|---|---|
| Timeout beim Verbinden | Firewall blockiert den Port | `Test-NetConnection` prüfen, Firewall-Regel erstellen |
| „SQL Server does not exist" | DNS-Name löst nicht auf | `nslookup` prüfen, DNS-Eintrag erstellen |
| Verbindung auf falscher Instanz | Port-Zuordnung stimmt nicht | SQL Server Configuration Manager prüfen |
| Kerberos-Authentifizierung schlägt fehl | SPN fehlt für den DNS-Alias | `setspn -S MSSQLSvc/sql-app01.firma.local:1434 DOMAIN\SqlServiceAccount` |
| Port wird dynamisch überschrieben | "TCP Dynamic Ports" enthält `0` | Feld komplett leeren, Dienst neu starten |

---

## Hinweise

- **Kerberos / SPN**: Bei Windows-Authentifizierung über DNS-Aliase muss ein SPN registriert werden, sonst fällt die Authentifizierung auf NTLM zurück. Pro DNS-Name und Port einen SPN setzen: `setspn -S MSSQLSvc/sql-app01.firma.local:1434 DOMAIN\SqlServiceAccount`.
- **Always On Availability Groups**: Listener verwenden eigene IPs und Ports – dort ist die DNS-Konfiguration bereits integriert. Diese Anleitung betrifft Standalone-Instanzen und Failover Cluster Instances.
- **Port-Bereich**: Der Bereich 1433–1455 ist eine Konvention, kein technisches Limit. Jeder freie Port zwischen 1024 und 65535 ist verwendbar. Der Bereich hält die Ports übersichtlich beieinander.
- **Dokumentation pflegen**: Eine zentrale Tabelle (Instanz → DNS-Name → Port → Zweck) als Single Source of Truth führen und bei jeder Änderung aktualisieren.
