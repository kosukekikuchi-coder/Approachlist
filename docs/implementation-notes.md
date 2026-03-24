# Minimal CLI Implementation Notes

This repository now includes a fixture-driven CLI implementation for the first acceptance-test slice.

## Commands

Run commands from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\approachlist.ps1 resolve-areas
powershell -ExecutionPolicy Bypass -File .\scripts\approachlist.ps1 build-company-master
powershell -ExecutionPolicy Bypass -File .\scripts\approachlist.ps1 report-status
powershell -ExecutionPolicy Bypass -File .\scripts\approachlist.ps1 build-real-sales-list
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
- `data/out/real_sales_list.csv`
- `data/out/real_sales_list_usable.csv`
- `data/out/real_sales_list_report.csv`
- `logs/run.log`

## Notes

- The current implementation is fixture-based and avoids live crawling.
- Because Python is not available in this environment, the CLI is implemented in PowerShell while preserving the planned inputs and outputs.
- `company_master.csv` now includes `contact_form_url` for fixture cases where the official site exposes a contact path.
- `company_master.csv` now also includes `source_count` and `source_summary` so duplicate-integrated rows can still trace their contributing sources.
- `company_master.csv` now includes the raw signal columns `industry_fit`, `local_focus`, `network_affinity`, and `contactability` so score changes can be inspected directly.
- `build-real-sales-list` scans `data/real/*_member_companies.csv` and matching `*_company_details.csv`, then writes:
  - `real_sales_list.csv`: all rows
  - `real_sales_list_usable.csv`: only `is_usable=true`, reordered for sales use
  - `real_sales_list_report.csv`: municipality-level counts
