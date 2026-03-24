# 重複統合 テスト実行結果

## 対象
- [重複統合 受け入れテストケース](/C:/Users/fln_user/Documents/作業用フォルダー/docs/duplicate-integration-test-cases.md)
- 対象スクリプト: [approachlist.ps1](/C:/Users/fln_user/Documents/作業用フォルダー/scripts/approachlist.ps1)

## 使用した入力
- 地域: [duplicate_areas.csv](/C:/Users/fln_user/Documents/作業用フォルダー/config/duplicate_areas.csv)
- NG地域: [duplicate_contracted.csv](/C:/Users/fln_user/Documents/作業用フォルダー/config/duplicate_contracted.csv)
- 会員企業: [duplicate_member_companies.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/fixtures/duplicate_member_companies.csv)
- 企業詳細: [duplicate_company_details.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/fixtures/duplicate_company_details.csv)

## 出力
- 地域抽出: [duplicate_resolved_areas.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/out/duplicate_resolved_areas.csv)
- 企業出力: [duplicate_company_master.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/out/duplicate_company_master.csv)
- レポート: [duplicate_progress_report.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/out/duplicate_progress_report.csv)
- ログ: [duplicate-run.log](/C:/Users/fln_user/Documents/作業用フォルダー/logs/duplicate-run.log)

## 実行結果
| テストID | 結果 | 根拠 |
|---|---|---|
| DIT-001 | 合格 | `株式会社くまがい印刷` は2ソース入力から1件に統合され、`source_count=2` と `source_summary` が出力された |
| DIT-002 | 合格 | `株式会社くまがい印刷` と `秋田印刷製本株式会社` で、Webサイトや詳細ソースを持つ強い情報側が採用された |
| DIT-003 | 合格 | `株式会社フロム・エー` と `株式会社　フロム・エー` は正規化後の社名が近くても、電話番号・住所が一致しないため別件のまま出力された |

## 件数
- 入力企業数: 6
- 出力企業数: 4
- usable: 4

## 確認できたこと
- 同一企業の重複掲載を保守的ルールで1件にまとめられる
- 統合後もソース追跡情報を保持できる
- 強いソースの詳細を優先できる
- 近似社名だけでは誤統合しない

## 補足
- 初回実装では `source_count` と `source_summary` を追加し、重複統合後も出所を追えるようにした
- 初回方針どおり、`municipality` 一致に加えて `phone` または `address` 一致を重視している
