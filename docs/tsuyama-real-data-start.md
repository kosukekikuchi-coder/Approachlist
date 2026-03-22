# 津山市 実データ着手メモ

## 対象地域
- 津山市
- 圏域人口: 136,547

参照:
- [areas_real_small.csv](/C:/Users/fln_user/Documents/作業用フォルダー/config/areas_real_small.csv)

## まず埋めるファイル
- 企業一覧: [tsuyama_member_companies.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/tsuyama_member_companies.csv)
- 企業詳細: [tsuyama_company_details.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/tsuyama_company_details.csv)

## 初期ソース候補
- 一次候補: [津山商工会議所 企業PR情報「ミシュランガイド京都・大阪+岡山2021」に掲載された会員事業所のご紹介](https://tsuyamacci-info.com/companypr/jigyousyo-pr/%E3%80%8C%E3%83%9F%E3%82%B7%E3%83%A5%E3%83%A9%E3%83%B3%E3%82%AC%E3%82%A4%E3%83%89%E4%BA%AC%E9%83%BD%E3%83%BB%E5%A4%A7%E9%98%AA%E5%B2%A1%E5%B1%B12021%E3%80%8D%E3%81%AB%E6%8E%B2%E8%BC%89%E3%81%95)
- 補助候補: [津山商工会議所 会員企業検索](https://search.tsuyamacci-info.com)
- 入口ページ: [津山商工会議所 経営支援アプリ](https://www.tsuyama-cci.or.jp/webapp.html)

## このソースを使う理由
- 津山市の会員事業所名、住所、電話番号、Web導線がまとまっている
- 商工会議所系なので地域整合を取りやすい
- 最初の 5〜10社を低コストで作るのに向いている

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
- 津山市の企業を 5〜10社入れる
- 少なくとも以下を含める
  - usable達成企業 1社以上
  - usable未達企業 1社以上
  - `contact_form_url` がある企業 1社以上
  - `detail_source_url` が追える企業

## 次の実作業
1. 津山商工会議所の会員企業検索から最初の候補企業を 5〜10社選ぶ
2. `tsuyama_member_companies.csv` に企業一覧を入れる
3. 企業公式サイトまたは公開情報から `tsuyama_company_details.csv` を埋める
4. 現行CLIに読ませて `company_master` を出力する

## 現時点のメモ
- 2026-03-22 時点で、津山商工会議所の企業PR記事から 8社を初期投入済み
- 誤紐づけ防止を優先し、記事内で確認できた情報のみを初期反映
- `contact_form_url` とスコア信号列は未入力

## 2026-03-22 実データ実行結果
- `tsuyama_member_companies.csv` と `tsuyama_company_details.csv` を使った `build-company-master` で 8社を出力
- usable 判定は 8社中 8社が `true`
- `detail_source_url` は全8社で確認可能
- `contact_form_url` は未入力のため未反映
- 商工会議所会員で津山市所在地、かつ電話確認済みという根拠に合わせて
  - `local_focus=1`
  - `network_affinity=1`
  - `contactability=1`
  を入力
- 最新の再実行では、全8社が `priority_score=45` `priority_rank=B` で出力
- `score_reason` は `Local focus / Community network signal / Reachable contact path`

## 次に埋めると効果が高い項目
- `contact_form_url`
- `industry_fit`
- `local_focus`
- `network_affinity`
- `contactability`
