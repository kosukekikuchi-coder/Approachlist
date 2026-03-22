# 実データ切り出しファイル

以下の2ファイルを、本番候補CSV
[まいぷれパートナー開拓_地域貢献関心群 - 都市雇用圏（10～50万人）.csv](/C:/Users/fln_user/Documents/作業用フォルダー/まいぷれパートナー開拓_地域貢献関心群%20-%20都市雇用圏（10～50万人）.csv)
から切り出した。

## 生成ルール
- `config/areas_real.csv`
  - `エリアOK/NG = OK`
  - `圏域人口 = 100,000〜400,000`
  - `都市雇用圏名（中心都市）` を `municipality` として採用
- `config/contracted_real.csv`
  - `エリアOK/NG` が `NG*` の行を採用
  - `都市雇用圏名（中心都市）` を `municipality` として採用

## 生成ファイル
- [areas_real.csv](/C:/Users/fln_user/Documents/作業用フォルダー/config/areas_real.csv)
- [contracted_real.csv](/C:/Users/fln_user/Documents/作業用フォルダー/config/contracted_real.csv)
- [areas_real_small.csv](/C:/Users/fln_user/Documents/作業用フォルダー/config/areas_real_small.csv)

## 補足
- これは実データ受け入れテスト用の暫定切り出しであり、fixture 用の `config/areas.csv` / `config/contracted.csv` とは別物。
- 現行CLIが `municipality` 列を前提としているため、当面は `都市雇用圏名（中心都市）` をそのまま使う。
- `areas_real_small.csv` は初回実データ受け入れ向けの3件絞り込み版。
  - 岡崎市: 上限寄り
  - 津山市: 中間帯
  - 高山市: 下限寄り
