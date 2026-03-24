# 長浜市 実データ着手メモ

## 対象地域
- 長浜市
- 圏域人口: 144,357

参照:
- [areas_real.csv](/C:/Users/fln_user/Documents/作業用フォルダー/config/areas_real.csv)

## まず埋めるファイル
- 企業一覧: [nagahama_member_companies.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/nagahama_member_companies.csv)
- 企業詳細: [nagahama_company_details.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/nagahama_company_details.csv)

## 初期ソース候補
- 一次候補: [長浜商工会議所 会員事業所紹介](https://nagahama.or.jp/member/)
- 入口ページ: [長浜商工会議所](https://nagahama.or.jp/)

## このソースを使う理由
- 長浜市に紐づく会員事業所の公開導線がある
- 会員紹介ページを起点に小規模な企業一覧を作りやすい
- 商工会議所ソースとして、既存の型を横展開しやすい

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
- 長浜市の企業を 5〜10社入れる
- 少なくとも以下を含める
  - usable達成企業 1社以上
  - `detail_source_url` が追える企業
  - スコア理由が出せる企業

## 次の実作業
1. 長浜商工会議所の会員事業所紹介から最初の候補企業を 5〜10社選ぶ
2. `nagahama_member_companies.csv` に企業一覧を入れる
3. 企業公式サイトまたは公開情報から `nagahama_company_details.csv` を埋める
4. 現行CLIに読ませて `company_master` を出力する

## 2026-03-24 候補企業の初期選定
- 長浜商工会議所の会員事業所紹介ページ1ページ目から、最初の候補企業を 8社選定
- 使用した公開導線
  - [長浜商工会議所 会員事業所紹介](https://nagahama.or.jp/member/)
- 先に入れた企業
  - アイシス行政書士事務所
  - 有限会社アイズブライト
  - Ｉｔｉｃｅ
  - 有限会社アイティー・ウェーブ
  - 饗場歯科医院
  - 株式会社アインコーポレーション
  - 株式会社ＯＷＬＡＲＴＳ
  - 株式会社あおば
- 次は、この8社で `company_master` を出して usable の初回確認を行う

## 2026-03-24 初回実データ結果
- 8社を `build-company-master` に投入
- usable は 8社
- `local_focus=1` `network_affinity=1` `contactability=1` を初期入力
- 全8社が `priority_score=45` `priority_rank=B`
- `score_reason` は `Local focus / Community network signal / Reachable contact path`

## 次にやること
1. `industry_fit` を入れられる企業を選ぶ
2. `contact_form_url` を取れる企業があれば補完する

## 2026-03-24 ルール適用の試行結果
- `有限会社アイズブライト`
- `株式会社ＯＷＬＡＲＴＳ`
- `株式会社あおば`
  の3社について、`industry_fit=0.5` を試行入力
- 3社のスコアは `45 / B` から `62 / A` に上昇
- `score_reason` は `Industry fit / Local focus / Community network signal / Reachable contact path` に変化
