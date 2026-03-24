# 実データ受け入れ 総括サマリー

## 概要
実データを使った受け入れ確認を、以下の5地域で実施した。

- 岡崎市
- 津山市
- 高山市
- 成田市
- 長浜市

## 参照レポート
- [岡崎市 実データ受け入れ結果](/C:/Users/fln_user/Documents/作業用フォルダー/docs/okazaki-real-data-acceptance-result.md)
- [津山市 実データ受け入れ結果](/C:/Users/fln_user/Documents/作業用フォルダー/docs/tsuyama-real-data-acceptance-result.md)
- [高山市 実データ受け入れ結果](/C:/Users/fln_user/Documents/作業用フォルダー/docs/takayama-real-data-acceptance-result.md)
- [成田市 着手メモ](/C:/Users/fln_user/Documents/作業用フォルダー/docs/narita-real-data-start.md)
- [長浜市 着手メモ](/C:/Users/fln_user/Documents/作業用フォルダー/docs/nagahama-real-data-start.md)
- [シグナルルール](/C:/Users/fln_user/Documents/作業用フォルダー/docs/signal-rules.md)
- [重複・同名企業衝突 確認メモ](/C:/Users/fln_user/Documents/作業用フォルダー/docs/duplicate-name-collision-check.md)

## 結果一覧
| 地域 | 対象企業数 | usable | usable未達 | 最新スコア状況 | 補足 |
|---|---:|---:|---:|---|---|
| 岡崎市 | 8 | 7 | 1 | 7社が `62 / A`、1社が `0 / C` | `株式会社中日図書` は人的確認でも根拠不足のため保留 |
| 津山市 | 8 | 8 | 0 | 全件 `62 / A` | `industry_fit=0.5` を全件に反映 |
| 高山市 | 8 | 8 | 0 | 全件 `62 / A` | `industry_fit=0.5` を全件に反映 |
| 成田市 | 8 | 6 | 2 | 4社が `45 / B`、4社が `0 / C` | `株式会社ＴＥＩ` と `株式会社サンリツ` は未達のまま保留 |
| 長浜市 | 8 | 8 | 0 | 3社が `62 / A`、5社が `45 / B` | `industry_fit=0.5` を3社で試行反映 |

## 集計
- 対象地域数: 5
- 対象企業数: 40
- usable: 37
- usable未達: 3

## 今回確認できたこと
- 5地域とも、実データを使って `company_master` 出力まで進められた
- NGエリア除外と地域選定の流れを、実データでも小さく確認できた
- 40社中37社を usable と判定できた
- usable 未達でも除外せず、`detail_source_url` を持ったまま確認可能な形で出力できた
- 津山市、高山市、長浜市では、`industry_fit` を入れると `score_reason` が自然に変化することを確認できた
- 岡崎市でも、保留1社を除く7社で `industry_fit` 反映後のスコア変化を確認できた

## 実務上の評価
### 1. 誤情報回避を優先した運用ができている
- 岡崎市の `株式会社中日図書` は、人的確認でも確度高い公開情報を確認できなかったため空欄のままにした
- 成田市の `株式会社ＴＥＩ` と `株式会社サンリツ` も、スピード優先の方針の中で未達のまま保留した
- いずれも、無理に埋めない判断ができている

### 2. usable 判定は実データでも機能している
- 岡崎市、津山市、高山市、長浜市では高い割合で usable を確保できた
- 成田市も `6/8` まで到達しており、横展開の型としては成立している

### 3. スコアリングは説明可能な形で動いている
- `local_focus`
- `network_affinity`
- `contactability`
- `industry_fit`

の反映で、`priority_score` と `score_reason` が意図どおり変化することを複数地域で確認できた

## ルール適用後の見え方
- `contact_form_url`
  - 公式サイト起点で安全に確認できるものだけ入力し、見つからない場合は空欄にする運用で問題なく進められた
- `industry_fit`
  - `0.5` の適用で、`45 / B` から `62 / A` へ上がるパターンを複数地域で確認できた
  - `industry_fit=1` の厳しめ基準は [シグナルルール](/C:/Users/fln_user/Documents/作業用フォルダー/docs/signal-rules.md) に明文化済み

## 残課題
- 岡崎市の `株式会社中日図書` は引き続き保留
- 成田市の `株式会社ＴＥＩ` と `株式会社サンリツ` は未達のまま
- `contact_form_url` は地域によって取得できる件数に差がある
- `industry_fit=1` を付ける企業の実地確認はまだ本格着手していない
- 重複統合、同名企業衝突、別タイプのソース耐性は次フェーズでの確認が必要

## 現時点の判断
現時点では、**「実データで地域をまたいで一定割合の usable 判定ができ、誤情報を避けつつ、根拠つきでスコアと説明を出せる」** ところまでは確認できた。

特に、次の条件は満たせている。

- usable 判定が実データで機能する
- 根拠ソースを追える
- `industry_fit` ルールでスコアが説明可能に変わる
- 情報が弱い企業は無理に埋めない

## 次にやるべきこと
1. `contact_form_url` のルール適用を、広い件数で安定させる
2. `industry_fit=1` 候補を少数だけ実地確認する
3. 5地域より少し広い件数で実データ確認を増やす
4. 重複統合、同名企業誤紐づけ、別ソース耐性の確認に進む
