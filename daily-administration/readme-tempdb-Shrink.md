# Export-MSSQLEventlog

## Zweck

Exportiert alle Einträge aus dem Windows Application-Eventlog, deren Quelle mit `MSSQL*` beginnt, in eine CSV-Datei. Dient zur schnellen Analyse von SQL-Server-Fehlern und -Warnungen außerhalb der Event Viewer.

## Befehl

```powershell
Get-EventLog -LogName Application |
    Where-Object { $_.Source -like "MSSQL*" } |
    Export-Csv -Path C:\Temp\msql_error.csv -Delimiter ";" -NoTypeInformation
```

## Ablauf

1. **Get-EventLog** – Liest sämtliche Einträge aus dem Log *Application*.
2. **Where-Object** – Filtert auf Quellen, die mit `MSSQL` beginnen (z. B. `MSSQLSERVER`, `MSSQL$InstanceName`).
3. **Export-Csv** – Schreibt die Ergebnisse als CSV mit Semikolon-Trennung nach `C:\Temp\msql_error.csv`.

## Voraussetzungen

- Windows PowerShell 5.1 oder höher
- Lokale **Administrator-Rechte** (Eventlog-Lesezugriff)
- Zielverzeichnis `C:\Temp` muss existieren

## Ausgabe

| Datei | Format | Trennzeichen |
|---|---|---|
| `C:\Temp\msql_error.csv` | CSV (UTF-8) | `;` |

Die CSV enthält u. a. die Spalten `TimeGenerated`, `EntryType`, `Source`, `EventID` und `Message`.

## Hinweise

- `Get-EventLog` ist auf klassische Windows-Logs beschränkt. Für neuere Logs alternativ `Get-WinEvent` verwenden.
- Bei großen Logs kann der Befehl langsam sein – optional mit `-Newest 500` die Anzahl begrenzen.
- `-NoTypeInformation` unterdrückt die PowerShell-Typzeile in der ersten Zeile der CSV.
