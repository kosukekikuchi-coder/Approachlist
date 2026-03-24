# 実データ受け入れ確認サマリー

## 目的
営業アプローチリスト作成ツールについて、実データを用いて次の観点を確認した結果をまとめる。

- usable 判定が現場で使える形で出力されること
- 誤情報を避けながらソース情報を保持できること
- FR-7 の優先順位スコアリングが説明可能な形で動くこと
- 重複統合を保守的に実行できること

## 参照資料
- [岡崎市 実データ受け入れ結果](/C:/Users/fln_user/Documents/作業用フォルダー/docs/okazaki-real-data-acceptance-result.md)
- [津山市 実データ受け入れ結果](/C:/Users/fln_user/Documents/作業用フォルダー/docs/tsuyama-real-data-acceptance-result.md)
- [高山市 実データ受け入れ結果](/C:/Users/fln_user/Documents/作業用フォルダー/docs/takayama-real-data-acceptance-result.md)
- [秋田市 重複統合結果](/C:/Users/fln_user/Documents/作業用フォルダー/docs/akita-real-data-duplicate-integration-result.md)
- [成田市 着手メモ](/C:/Users/fln_user/Documents/作業用フォルダー/docs/narita-real-data-start.md)
- [長浜市 着手メモ](/C:/Users/fln_user/Documents/作業用フォルダー/docs/nagahama-real-data-start.md)
- [signal-rules](/C:/Users/fln_user/Documents/作業用フォルダー/docs/signal-rules.md)
- [industry_fit=1 確認メモ](/C:/Users/fln_user/Documents/作業用フォルダー/docs/industry-fit-one-check.md)
- [同名衝突確認メモ](/C:/Users/fln_user/Documents/作業用フォルダー/docs/duplicate-name-collision-check.md)

## 地域別サマリー
| 地域 | 対象企業数 | usable | usable未達 | 最新スコア状況 | 補足 |
|---|---:|---:|---:|---|---|
| 岡崎市 | 8 | 7 | 1 | 7社が `62 / A`、1社が `0 / C` | `株式会社中日図書` は人的確認でも十分な公開根拠が得られず保留 |
| 津山市 | 8 | 8 | 0 | 全件 `62 / A` | `industry_fit=0.5` を反映済み |
| 高山市 | 8 | 8 | 0 | 全件 `62 / A` | `industry_fit=0.5` を反映済み |
| 成田市 | 8 | 6 | 2 | 4社が `45 / B`、2社が `0 / C` | `株式会社ＴＥＩ` と `株式会社サンリツ` は未補完のまま保留 |
| 長浜市 | 8 | 8 | 0 | 3社が `62 / A`、5社が `45 / B` | `industry_fit=0.5` を一部反映済み |

## 集計
- 対象地域数: 5
- 対象企業数: 40
- usable: 37
- usable未達: 3

## 実データで確認できたこと
- 5地域すべてで実データから `company_master` 相当の出力を生成できた
- NGエリア除外と地域選定は、実データ由来の地域ファイルでも破綻せず動作した
- 40社中37社を usable と判定できた
- usable 未達企業も除外せず、`detail_source_url` を保持したまま確認可能な形で出力できた
- 津山市・高山市・長浜市では、`industry_fit` を入れると `score_reason` が自然に変化することを確認できた
- 秋田市では、実データフローで重複統合を確認し、11件入力を9件出力に安全に統合できた

## end-to-end で確認できたこと
### `industry_fit=1` の end-to-end 確認
- [industry-fit-one-check.md](/C:/Users/fln_user/Documents/作業用フォルダー/docs/industry-fit-one-check.md) に基づき、`秋田印刷製本株式会社` を `industry_fit=1` 候補として確認
- [signal-rules.md](/C:/Users/fln_user/Documents/作業用フォルダー/docs/signal-rules.md) の厳しめ基準に照らして、`1` を付与してよい理由を整理
- 入力側の [akita_company_details.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/akita_company_details.csv) に `industry_fit=1` を反映
- 出力側の [akita_company_master.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/out/akita_company_master.csv) で、`priority_score=80`、`priority_rank=A`、`score_reason=Industry fit / Local focus / Community network signal / Reachable contact path` への変化を確認
- [approachlist.ps1](/C:/Users/fln_user/Documents/作業用フォルダー/scripts/approachlist.ps1) では raw signal 列
  - `industry_fit`
  - `local_focus`
  - `network_affinity`
  - `contactability`
  を `company_master.csv` に出力するよう更新済み

### 重複統合の end-to-end 確認
- fixture ベースでは `DIT-001` から `DIT-003` まで合格
- 秋田市の実データフローでも、同一企業の複数掲載を1件に統合できた
- `source_count` と `source_summary` により、統合後もソース追跡が可能
- 近似社名だけでは統合せず、誤統合防止を優先できた

## ルール運用後の見え方
### `contact_form_url`
- 公式サイト起点で確認できたもののみ採用し、見つからない場合は空欄とするルールで運用
- 現時点の確認件数
  - 秋田市: `3/9`
  - 長浜市: `4/8`
  - 高山市: `2/8`

### `industry_fit`
- `industry_fit=0.5` の適用では、`45 / B` から `62 / A` に上がるパターンを複数地域で確認済み
- `industry_fit=1` では、秋田印刷製本株式会社で `80 / A` への反映を確認済み
- `industry_fit=1` は厳しめ運用とし、少しでも迷う場合は `0.5` 以下に留める

## 残課題
- 岡崎市の `株式会社中日図書` は引き続き保留
- 成田市の `株式会社ＴＥＩ` と `株式会社サンリツ` は未補完のまま
- `contact_form_url` は地域によって確認件数に差がある
- `industry_fit=1` の実地確認はまだ少数例であり、次フェーズでの追加確認余地がある
- 自然発生する同名衝突はまだ少なく、重複統合は今後も継続検証が必要

## 現時点の判定
現時点では、**実データで地域をまたいだ一定量の usable 判定ができ、誤情報を避けつつ、ソース付きでスコアと説明を出せる** ことまでは確認できた。

特に次の点は確認済みである。
- usable 判定が実データで機能する
- `detail_source_url` を保持できる
- `industry_fit` ルールによりスコアと説明が変化する
- `industry_fit=1` が evidence から score 出力まで end-to-end で反映される
- 重複統合が fixture と実データの双方で保守的に動作する

## 次にやるべきこと
1. `contact_form_url` の適用を、広い件数で引き続き安定させる
2. `industry_fit=1` の実地確認を、あと1〜2社だけ増やす
3. 成田市の未補完2社を、必要になった段階で追加確認する
4. 重複統合は、別地域・別ソースでも継続的に確認する
