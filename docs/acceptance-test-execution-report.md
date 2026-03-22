# 受け入れテスト実行結果レポート

## 概要
- 実行日: 2026-03-22
- 対象実装: fixture-driven CLI prototype
- 実行方式: PowerShell CLI
- 対象コマンド:
  - `resolve-areas`
  - `build-company-master`
  - `report-status`
- 注意:
  - 今回の結果は実データ収集ではなく、repo内の fixture を使った検証結果
  - live crawling や実在サイトへのアクセスは行っていない

参照ファイル:
- [受け入れテスト仕様書](/C:/Users/fln_user/Documents/作業用フォルダー/docs/acceptance-test-spec.md)
- [実装メモ](/C:/Users/fln_user/Documents/作業用フォルダー/docs/implementation-notes.md)
- [地域選定結果](/C:/Users/fln_user/Documents/作業用フォルダー/data/out/resolved_areas.csv)
- [企業マスタ結果](/C:/Users/fln_user/Documents/作業用フォルダー/data/out/company_master.csv)
- [進捗レポート](/C:/Users/fln_user/Documents/作業用フォルダー/data/out/progress_report.csv)
- [実行ログ](/C:/Users/fln_user/Documents/作業用フォルダー/logs/run.log)

## 実行結果サマリ
| テストID | 観点 | 結果 | 根拠 |
|---|---|---|---|
| AT-001 | NGエリア除外 | 合格 | `resolved_areas.csv` で `契約市` が `contracted_area` で除外 |
| AT-002 | 人口境界値 | 合格 | `100000` と `400000` は選定、`400001` は除外 |
| AT-005 | 同名企業の誤紐づけ防止 | 合格 | `company_master.csv` の `中央設備` が詳細空欄、`Ambiguous company match`、`Low` |
| AT-006 | 情報欠損時の継続 | 合格 | 欠損企業を含んでも `company_master.csv` と `run.log` が出力 |
| AT-007 | usable 判定 | 合格 | 6件中3件が `is_usable=true`、未達も除外されず出力 |
| AT-008 | ソース明示 | 合格 | `detail_source_url` が出力されている |
| AT-009 | 問い合わせフォームURL | 合格 | `contact_form_url` 列が追加され、該当企業に値が入っている |
| AT-011 | スコア理由出力 | 合格 | `priority_score` `priority_rank` `score_reason` `score_confidence` を確認 |
| AT-012 | 情報不足時のスコア継続 | 合格 | `情報不足電設` が `C / Insufficient supporting data / Medium` で出力 |
| AT-013 | `scoring.yaml` 変更反映 | 合格 | 配点変更時にスコアが変化することを別実行で確認 |
| AT-014 | 進捗レポート | 合格 | `progress_report.csv` に件数、usable件数、error件数を確認 |

## 主要確認ポイント
### 地域選定
- `桜市 (100000)` は選定された
- `高砂市 (400000)` は選定された
- `中央市 (400001)` は `population_out_of_range` で除外された
- `契約市` は `contracted_area` で除外された

### 企業マスタ
- `中央設備` は曖昧マッチとして詳細情報を埋めていない
- `高砂設備` は電話番号・Webサイトが欠損していても出力継続している
- `外部フォーム工業` は `contact_form_url` に外部フォームURLが入っている
- `情報不足電設` は usable 未達かつスコア継続のケースとして出力されている

### 進捗・ログ
- `resolve-areas`: 入力6件、出力4件
- `build-company-master`: 出力6件、usable 3件、warning 1件
- ログには `Ambiguous company match: 中央設備 in 高砂市` が記録されている

## 既知の前提
- 今回は fixture ベースのため、実サイト由来の精度は未検証
- Python CLI は未導入で、PowerShell CLI で代替している
- 重複統合は今回の受け入れ対象外

## 次の課題
1. fixture ベースではなく、実データまたは実クロールを使った受け入れ確認に進む
2. 重複統合を受け入れ対象に戻すか判断する
3. Python CLI に寄せるか、PowerShell CLI を暫定正として扱うか決める
