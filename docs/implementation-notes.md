# Minimal CLI Implementation Notes

This repository now includes a fixture-driven CLI implementation for the first acceptance-test slice.

## Commands

Run commands from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\approachlist.ps1 resolve-areas
powershell -ExecutionPolicy Bypass -File .\scripts\approachlist.ps1 build-company-master
powershell -ExecutionPolicy Bypass -File .\scripts\approachlist.ps1 report-status
```

## Files

- `config/areas.csv`
- `config/contracted.csv`
- `config/scoring.yaml`
- `data/fixtures/member_companies.csv`
- `data/fixtures/company_details.csv`
- `data/out/resolved_areas.csv`
- `data/out/company_master.csv`
- `data/out/progress_report.csv`
- `logs/run.log`

## Notes

- The current implementation is fixture-based and avoids live crawling.
- Because Python is not available in this environment, the CLI is implemented in PowerShell while preserving the planned inputs and outputs.
