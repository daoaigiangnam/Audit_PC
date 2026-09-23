# MSTAR PC Audit Tool

Windows endpoint collector for the MSTAR PC Audit platform.

## User workflow

The user enters only:

1. Audit Code
2. Phòng ban
3. Họ và tên

Customer and branch are resolved by the server from the Audit Code.

## Collector workflow

```text
User input
  -> Validate Audit Code
  -> Collect local PC inventory
  -> Build JSON payload
  -> POST HTTPS to PC Audit API
```

The endpoint does not create Excel files. Excel reporting is generated centrally by the web application.

## Collector data

The collector must preserve the complete data produced by the existing PowerShell inventory script, including computer identity, mainboard/BIOS, CPU, memory, storage, monitors, GPU, battery, Windows, network/LAN/Wi-Fi/WWAN, security, licenses and installed software.

## Requirements

- Windows 10/11 or supported Windows Server workstation
- Built-in Windows PowerShell 5.1 is sufficient for the collector
- No ImportExcel module is required
- No administrator installation is required for the user-facing tool unless a specific collector field requires elevated access

## Security

- API URL is HTTPS only.
- Audit Code is validated by the server.
- Customer/branch identifiers are not trusted from the endpoint.
- Do not hard-code an API password or shared secret in the collector.
