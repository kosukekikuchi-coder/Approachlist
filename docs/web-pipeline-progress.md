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

- total rows: `75`
- usable rows: `44`

Municipality breakdown:

- 岡崎市: `29 / usable 17`
- 津山市: `5 / usable 5`
- 高山市: `22 / usable 9`
- 成田市: `16 / usable 9`
- 長浜市: `6 / usable 4`

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
- The usable export now requires municipality-match in the extracted address, which reduces obvious cross-area false positives.
- The Miyakonojo bootstrap test currently reaches `33 total / 27 usable` after source-type cleanup, generic-title normalization, and stronger address extraction.
- The Shimonoseki bootstrap test now completes end-to-end with `5 total / 3 usable`, confirming that an unregistered municipality can still reach sales-list output after the latest discovery fallback fixes.
- Structured member-table extraction is now prototyped for chamber / JC pages. On Shimonoseki this reduced obvious non-company carryover, but usable growth is still limited because official-site search for extracted member names remains weak.
- Bootstrap now reuses an existing municipality registry when source discovery temporarily returns `0` candidates, so unregistered-area setup is less likely to fail just because search results fluctuate.

## Current gaps

- Company-name normalization still leaves generic titles in some rows.
- Generic company-name normalization is still the main driver of noisy rows.
- Some sources produce noisy external links that need stronger source-type-specific filtering.
- Chamber / JC structured extraction still depends on weak official-site search when source pages do not link directly to company sites.
- Score signals are still mostly defaulted in the live-crawl path.

## Next focus

1. Improve company-name normalization for generic page titles.
2. Tighten source-type-specific noise filters so chamber pages yield fewer non-company candidates.
3. Refine extracted addresses so site-navigation text is less likely to remain in the field.
4. Add score-signal enrichment to the live-crawl path after name quality stabilizes.
