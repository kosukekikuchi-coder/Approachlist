# 高山市 実データ着手メモ

## 対象地域
- 高山市
- 圏域人口: 101,057

参照:
- [areas_real_small.csv](/C:/Users/fln_user/Documents/作業用フォルダー/config/areas_real_small.csv)

## まず埋めるファイル
- 企業一覧: [takayama_member_companies.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/takayama_member_companies.csv)
- 企業詳細: [takayama_company_details.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/takayama_company_details.csv)

## 初期ソース候補
- 一次候補: [高山ロータリークラブ 会員職業紹介 ひと言PR](https://takayama-rc.jp/pr/index.html)

## このソースを使う理由
- 高山市の会社名、住所、電話番号がまとまっている
- 会員企業の地域整合を取りやすい
- 公式サイトへの導線も多く、企業詳細の補完に使いやすい

## 企業一覧で最低限必要な列
- `company_name`
- `municipality`
- `source_org`
- `source_url`

## 企業詳細で最低限必要な列
- `company_name`
- `municipality`
- `address`
- `phone`
- `website`
- `contact_form_url`
- `detail_source_url`
- `industry_fit`
- `local_focus`
- `network_affinity`
- `contactability`

## 最初の目標
- 高山市の企業を 5〜10社入れる
- 少なくとも以下を含める
  - usable達成企業 1社以上
  - `detail_source_url` が追える企業
  - スコア理由が出せる企業

## 現時点のメモ
- 2026-03-22 時点で、高山ロータリークラブの会員職業紹介ページから 8社を初期投入済み
- 住所、電話番号、会社サイト導線が確認できた企業を優先して投入
- `contact_form_url` は未入力

## 2026-03-22 実データ実行結果
- `takayama_member_companies.csv` と `takayama_company_details.csv` を使った `build-company-master` で 8社を出力
- usable 判定は 8社中 8社が `true`
- `detail_source_url` は全8社で確認可能
- `contact_form_url` は未入力のため未反映
- `local_focus=1`
- `network_affinity=1`
- `contactability=1`
  を初期入力
- 最新の再実行では、全8社が `priority_score=45` `priority_rank=B` で出力
- `score_reason` は `Local focus / Community network signal / Reachable contact path`

## 次に埋めると効果が高い項目
- `contact_form_url`
- `industry_fit`

## 2026-03-23 ルール適用の展開
- 高山市の8社について、`industry_fit=0.5` を反映
- 根拠は、公開ソースと公式サイトから事業内容が読み取りやすいこと
- `contact_form_url` は、公式サイト上で安全に確認できる問い合わせフォームを確認できなかったため空欄のまま
- 再計算後は、全8社が `priority_score=62` `priority_rank=A`
- `score_reason` は `Industry fit / Local focus / Community network signal / Reachable contact path`
