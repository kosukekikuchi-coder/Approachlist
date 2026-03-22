# 津山市 実データ受け入れ結果

## 対象
- 地域: 津山市
- ソース組織: 津山商工会議所
- 一次ソース: [企業PR情報「ミシュランガイド京都・大阪+岡山2021」に掲載された会員事業所のご紹介](https://tsuyamacci-info.com/companypr/jigyousyo-pr/%E3%80%8C%E3%83%9F%E3%82%B7%E3%83%A5%E3%83%A9%E3%83%B3%E3%82%AC%E3%82%A4%E3%83%89%E4%BA%AC%E9%83%BD%E3%83%BB%E5%A4%A7%E9%98%AA%E5%B2%A1%E5%B1%B12021%E3%80%8D%E3%81%AB%E6%8E%B2%E8%BC%89%E3%81%95)

## 使用ファイル
- 地域入力: [areas_real_small.csv](/C:/Users/fln_user/Documents/作業用フォルダー/config/areas_real_small.csv)
- NG地域入力: [contracted_real.csv](/C:/Users/fln_user/Documents/作業用フォルダー/config/contracted_real.csv)
- 企業一覧: [tsuyama_member_companies.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/tsuyama_member_companies.csv)
- 企業詳細: [tsuyama_company_details.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/tsuyama_company_details.csv)
- 出力結果: [tsuyama_company_master.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/out/tsuyama_company_master.csv)
- 件数レポート: [tsuyama_progress_report.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/out/tsuyama_progress_report.csv)

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
  - 津山市所在地として掲載されている
- `network_affinity=1`
  - 津山商工会議所の会員事業所記事に掲載されている
- `contactability=1`
  - 電話番号が確認できている

`industry_fit` はまだ未入力とし、根拠が明確になってから追加する。

## 判定
津山市については、現時点で **「実データで営業利用可能なレコードを安定出力でき、説明可能なスコア理由も付けられる」** と判断できる。

今回は `contact_form_url` を埋め切っていないが、usable 条件は全件で満たしているため、初回受け入れ上の致命的な不足ではない。

## 次の進め方
1. 津山市は `8/8 usable` の実データ結果として共有する
2. 必要なら `contact_form_url` の補完を追加で行う
3. `industry_fit` の判断基準を決めてスコア精度を上げる
4. 3地域目の高山市へ横展開する
