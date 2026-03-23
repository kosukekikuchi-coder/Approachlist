# 岡崎市 実データ着手メモ

## 対象地域
- 岡崎市
- 圏域人口: 391,374

参照:
- [areas_real_small.csv](/C:/Users/fln_user/Documents/作業用フォルダー/config/areas_real_small.csv)

## まず埋めるファイル
- 企業一覧: [okazaki_member_companies.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/okazaki_member_companies.csv)
- 企業詳細: [okazaki_company_details.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/okazaki_company_details.csv)
- 初期ソースページ: [岡崎南ロータリークラブ 会員リスト](https://www.okazakiminamirc.com/voice)

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
- 岡崎市の企業を 5〜10社入れる
- 少なくとも以下を含める
  - usable達成企業 1社以上
  - usable未達企業 1社以上
  - `contact_form_url` がある企業 1社以上
- `detail_source_url` が追える企業

## 現在の投入状況
- 岡崎南ロータリークラブの会員リストページを元に 8社を投入済み
- 企業詳細テンプレートには、ページ上でリンクが確認できた会社サイトURLを初期入力済み
- 以下は公式サイトベースで住所・電話番号・問い合わせフォームURLまで確認済み
  - 有限会社磯貝彫刻
  - 合資会社旭軒元直
  - 太田油脂株式会社
  - ブラザー印刷株式会社
  - 株式会社岡崎グリーン
  - 清水電機株式会社
- スコア用シグナルは未入力

## 次の実作業
1. 岡崎市の団体ソースを1〜2種類決める
2. `okazaki_member_companies.csv` に企業一覧を入れる
3. `okazaki_company_details.csv` に詳細を入れる
4. 現行CLIに読ませるための実行方法を決める

## 2026-03-22 実データ実行結果
- `areas_real_small.csv` と `contracted_real.csv` を使った `resolve-areas` で、岡崎市は `selected=true` を確認
- `okazaki_member_companies.csv` と `okazaki_company_details.csv` を使った `build-company-master` で 8社を出力
- usable 判定は初回 8社中 6社が `true`
- その後、`株式会社犬塚石材本店` は公式会社案内ページから住所と電話番号を補完済み
- 最新の再実行では 8社中 7社が `true`
- 現在の未達候補は `株式会社中日図書`
  - 今の確認範囲では、誤紐づけせずに使える公開住所・電話番号を確認できていない
- `detail_source_url` は全8社で確認可能
- `contact_form_url` は 6社で確認可能
- 現時点ではスコア信号列が未入力のため、`priority_score=0` `priority_rank=C` `score_reason=Insufficient supporting data` で出力される

## 次に埋めると効果が高い項目
- `株式会社中日図書` の住所、電話番号、問い合わせ導線
- `industry_fit`
- `local_focus`
- `network_affinity`
- `contactability`

## 2026-03-23 ルール適用の展開
- `株式会社中日図書` を除く 7社について、`industry_fit=0.5` を反映
- あわせて、`local_focus=1` `network_affinity=1` `contactability=1` を反映
- 根拠は、岡崎市所在地、岡崎南ロータリークラブ掲載、電話または問い合わせ導線の確認
- 7社は再計算後、`priority_score=62` `priority_rank=A` に更新
- `score_reason` は `Industry fit / Local focus / Community network signal / Reachable contact path`
- `株式会社中日図書` は引き続き公開根拠不足のため `0 / C` のまま
