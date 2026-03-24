# 秋田市 実データ重複統合結果

## 対象
- [秋田市 実データ着手メモ](/C:/Users/fln_user/Documents/作業用フォルダー/docs/akita-real-data-start.md)
- [重複統合 受け入れテストケース](/C:/Users/fln_user/Documents/作業用フォルダー/docs/duplicate-integration-test-cases.md)

## 使用ファイル
- 入力企業一覧: [akita_member_companies.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/akita_member_companies.csv)
- 入力企業詳細: [akita_company_details.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/akita_company_details.csv)
- 出力企業一覧: [akita_company_master.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/out/akita_company_master.csv)
- 出力レポート: [akita_progress_report.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/out/akita_progress_report.csv)

## 結果
- 入力企業数: 11
- 出力企業数: 9
- usable: 9

## 確認できたこと

### 1. 同一企業の統合
- `株式会社くまがい印刷` は2ソース入力から1件に統合された
- `秋田印刷製本株式会社` も2ソース入力から1件に統合された
- 両社とも `source_count=2` になり、`source_summary` で出所を追える

### 2. 強いソースの優先
- `株式会社くまがい印刷` は、公式サイト由来の `website` と `contact_form_url` が採用された
- `秋田印刷製本株式会社` は、Webサイトを保持したまま1件化できた

### 3. 誤統合防止
- `株式会社フロム・エー`
- `株式会社　フロム・エー`

は、正規化後の社名は近いが、電話番号と住所表記が一致しないため別件のまま残った

## 評価
秋田市の実データフローでも、初回の保守的な重複統合ルールは機能した。

特に次を確認できた。

- 同一企業を1件に束ねられる
- 強いソース情報を優先できる
- 近似社名だけでは誤統合しない

## 現時点の補足
- 今回は `municipality` 一致に加えて `phone` または `address` 一致を重視している
- 住所正規化は最小限であり、高度な表記ゆれ対応はまだ未実装
