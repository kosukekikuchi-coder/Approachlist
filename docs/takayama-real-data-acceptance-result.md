# 高山市 実データ受け入れ結果

## 対象
- 地域: 高山市
- ソース組織: 高山ロータリークラブ
- 一次ソース: [高山ロータリークラブ 会員職業紹介 ひと言PR](https://takayama-rc.jp/pr/index.html)

## 使用ファイル
- 地域入力: [areas_real_small.csv](/C:/Users/fln_user/Documents/作業用フォルダー/config/areas_real_small.csv)
- NG地域入力: [contracted_real.csv](/C:/Users/fln_user/Documents/作業用フォルダー/config/contracted_real.csv)
- 企業一覧: [takayama_member_companies.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/takayama_member_companies.csv)
- 企業詳細: [takayama_company_details.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/takayama_company_details.csv)
- 出力結果: [takayama_company_master.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/out/takayama_company_master.csv)
- 件数レポート: [takayama_progress_report.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/out/takayama_progress_report.csv)

## 結果サマリ
- 対象企業数: 8社
- usable: 8社
- usable未達: 0社
- NG地域混入: なし
- `detail_source_url`: 全8社で確認可能
- `contact_form_url`: 未入力

## スコアリング結果
- 全8社が `priority_score=45`
- 全8社が `priority_rank=B`
- `score_reason` は `Local focus / Community network signal / Reachable contact path`

## 信号入力の考え方
今回の初回入力では、過剰な推定を避けて次だけを反映した。

- `local_focus=1`
  - 高山市所在地として掲載されている
- `network_affinity=1`
  - 高山ロータリークラブの会員職業紹介ページに掲載されている
- `contactability=1`
  - 電話番号が確認できている

`industry_fit` はまだ未入力とし、根拠が明確になってから追加する。

## 判定
高山市については、現時点で **「実データで営業利用可能なレコードを安定出力でき、説明可能なスコア理由も付けられる」** と判断できる。

今回は `contact_form_url` を埋め切っていないが、usable 条件は全件で満たしているため、初回受け入れ上の致命的な不足ではない。

## 次の進め方
1. 高山市は `8/8 usable` の実データ結果として共有する
2. 必要なら `contact_form_url` の補完を追加で行う
3. `industry_fit` の判断基準を決めてスコア精度を上げる
4. 3地域の結果を並べて実データ受け入れの到達点を整理する
