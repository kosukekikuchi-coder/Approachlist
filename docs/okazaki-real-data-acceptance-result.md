# 岡崎市 実データ受け入れ結果

## 対象
- 地域: 岡崎市
- ソース組織: 岡崎南ロータリークラブ
- 会員リスト: [https://www.okazakiminamirc.com/voice](https://www.okazakiminamirc.com/voice)

## 使用ファイル
- 地域入力: [areas_real_small.csv](/C:/Users/fln_user/Documents/作業用フォルダー/config/areas_real_small.csv)
- NG地域入力: [contracted_real.csv](/C:/Users/fln_user/Documents/作業用フォルダー/config/contracted_real.csv)
- 企業一覧: [okazaki_member_companies.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/okazaki_member_companies.csv)
- 企業詳細: [okazaki_company_details.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/okazaki_company_details.csv)
- 出力結果: [okazaki_company_master.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/out/okazaki_company_master.csv)
- 件数レポート: [okazaki_progress_report.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/out/okazaki_progress_report.csv)

## 結果サマリ
- 対象企業数: 8社
- usable: 7社
- usable未達: 1社
- NG地域混入: なし
- `detail_source_url`: 全8社で確認可能
- `contact_form_url`: 6社で確認可能

## 判定
岡崎市については、現時点で **「実データでも大半を営業利用可能な形で出力できる」** と判断できる。

一方で、`株式会社中日図書` は公開情報から岡崎市の住所・電話番号を安全に確認できていないため、usable未達のまま残す。
これは欠陥ではなく、**誤情報回避を優先した結果** として受け入れ判断に適合する。

## usable未達の企業
| company_name | 理由 | 対応方針 |
|---|---|---|
| 株式会社中日図書 | `missing address` | 人的確認に回す |

## 人的確認タスク
- 対象: `株式会社中日図書`
- 目的: 岡崎市の企業として使える公開根拠の補完
- 確認したい項目:
  - 住所
  - 電話番号
  - 問い合わせ導線
- 推奨確認元:
  - ロータリークラブ内の会員情報
  - 既存営業DB
  - 名刺、会社案内、電話帳などの社内保有情報

## 次の進め方
1. 岡崎市は `7/8 usable` の実データ結果として共有する
2. `株式会社中日図書` は人的確認タスクとして切り出す
3. 自動処理側は次の対象地域へ横展開する
4. 並行して `industry_fit` などのスコア信号入力ルールを固める
