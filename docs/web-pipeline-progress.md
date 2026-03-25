# Web Pipeline Progress

## Scope

This note tracks the live-crawl prototype that starts from selected municipalities and produces sales-list CSV files.

Current command:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\approachlist.ps1 run-web-pipeline
```

## Current flow

`run-web-pipeline` now chains:

1. `build-source-workset`
2. `extract-member-candidates`
3. `normalize-member-candidates`
4. `extract-company-details`
5. `build-company-master`
6. `build-sales-list-from-company-master`

## Verified outputs

- `company_master_web_*.csv`
- `web_sales_list_*.csv`
- `web_sales_list_*_usable.csv`
- `web_sales_list_*_report.csv`

## Small-set result

Input municipalities:

- 岡崎市
- 津山市
- 高山市

Latest result:

- total rows: `57`
- usable rows: `27`

Key files:

- `data/out/company_master_web_small.csv`
- `data/out/web_sales_list_small.csv`
- `data/out/web_sales_list_small_usable.csv`
- `data/out/web_sales_list_small_report.csv`

## Five-city result

Input municipalities:

- 岡崎市
- 津山市
- 高山市
- 成田市
- 長浜市

Latest result:

- total rows: `76`
- usable rows: `35`

Municipality breakdown:

- 岡崎市: `29 / usable 16`
- 津山市: `6 / usable 4`
- 高山市: `21 / usable 6`
- 成田市: `16 / usable 7`
- 長浜市: `4 / usable 2`

Key files:

- `data/out/company_master_web_five.csv`
- `data/out/web_sales_list_five.csv`
- `data/out/web_sales_list_five_usable.csv`
- `data/out/web_sales_list_five_report.csv`

## Current strengths

- Region-selection to sales-list export is now connected in one command.
- Official-site-origin `contact_form_url` is captured when available.
- The pipeline already produces usable rows without hand-maintained `member_companies.csv` / `company_details.csv`.
- Cleaner Narita source pages improved the five-city usable count.

## Current gaps

- Company-name normalization still leaves generic titles in some rows.
- Address extraction is still the main driver of unusable rows.
- Some sources produce noisy external links that need stronger source-type-specific filtering.
- Score signals are still mostly defaulted in the live-crawl path.

## Next focus

1. Improve company-name normalization for generic page titles.
2. Strengthen address extraction for official-site pages without simple postal-mark patterns.
3. Add source-type-specific noise filters so chamber pages yield fewer non-company candidates.
4. Raise usable coverage on Narita and Nagahama before expanding to more municipalities.
