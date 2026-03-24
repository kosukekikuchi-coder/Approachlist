# 成田市 実データ着手メモ

## 対象地域
- 成田市
- 圏域人口: 333,710

参照:
- [areas_real.csv](/C:/Users/fln_user/Documents/作業用フォルダー/config/areas_real.csv)

## まず埋めるファイル
- 企業一覧: [narita_member_companies.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/narita_member_companies.csv)
- 企業詳細: [narita_company_details.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/narita_company_details.csv)

## 初期ソース候補
- 一次候補: [成田商工会議所 会員企業リンク](https://naritacci.or.jp/?page_id=173961)
- 補助候補: [成田商工会議所 会員事業所案内](https://naritacci.or.jp/?page_id=109)
- 入口ページ: [成田商工会議所](https://naritacci.or.jp/)

## このソースを使う理由
- 成田市に紐づく会員企業の公開導線がある
- 会員事業所リンクと案内ページがあり、企業一覧を作りやすい
- 今の小規模受け入れ確認の流れをそのまま適用しやすい

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
- 成田市の企業を 5〜10社入れる
- 少なくとも以下を含める
  - usable達成企業 1社以上
  - `detail_source_url` が追える企業
  - スコア理由が出せる企業

## 次の実作業
1. 成田商工会議所の会員企業リンクから最初の候補企業を 5〜10社選ぶ
2. `narita_member_companies.csv` に企業一覧を入れる
3. 企業公式サイトまたは公開情報から `narita_company_details.csv` を埋める
4. 現行CLIに読ませて `company_master` を出力する

## 2026-03-24 候補企業の初期選定
- 成田商工会議所の会員事業所案内キャッシュから、最初の候補企業を 8社選定
- 使用した公開導線
  - [会員事業所案内（運輸通信）](https://naritacci.or.jp/?page_id=103)
  - [会員事業所案内（工業）](https://naritacci.or.jp/?page_id=96)
  - [会員事業所案内（建設）](https://naritacci.or.jp/?page_id=98)
- 先に入れた企業
  - 株式会社ＴＥＩ
  - 成田ケーブルテレビ株式会社
  - 株式会社サンリツ
  - 株式会社テラコン
  - 株式会社ナリコー
  - 有限会社石屋石材
  - 株式会社小野瀬工務店
  - 平山建設株式会社
- 次は、この8社について住所・電話・公式サイト導線を `narita_company_details.csv` に埋める

## 2026-03-24 初回実データ結果
- 8社を `build-company-master` に投入
- usable は初回 4社
  - 成田ケーブルテレビ株式会社
  - 株式会社テラコン
  - 株式会社ナリコー
  - 平山建設株式会社
- 上記4社は `priority_score=45` `priority_rank=B`
- `score_reason` は `Local focus / Community network signal / Reachable contact path`
- 未達 4社
  - 株式会社ＴＥＩ
  - 株式会社サンリツ
  - 有限会社石屋石材
  - 株式会社小野瀬工務店
- 未達理由は、現時点では `company detail not found`

## 2026-03-24 追加補完後
- `有限会社石屋石材`
- `株式会社小野瀬工務店`
  の2社について、住所・電話番号・一部Web導線を補完
- 最新の usable は 6社
- 現在の未達 2社
  - 株式会社ＴＥＩ
  - 株式会社サンリツ

## 次に埋める優先企業
1. 株式会社小野瀬工務店
2. 有限会社石屋石材
3. 株式会社ＴＥＩ
4. 株式会社サンリツ
