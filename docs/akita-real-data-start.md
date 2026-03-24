# 秋田市 実データ着手メモ

## 対象地域
- 秋田市
- 圏域人口: 374,655

参照:
- [areas_real.csv](/C:/Users/fln_user/Documents/作業用フォルダー/config/areas_real.csv)

## まず埋めるファイル
- 企業一覧: [akita_member_companies.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/akita_member_companies.csv)
- 企業詳細: [akita_company_details.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/akita_company_details.csv)

## 初期ソース候補
- 一次候補: [秋田市社会福祉協議会 企業・法人の団体会員](https://www.akita-city-shakyo.jp/pages/302/)
- 追加候補: [秋田観光コンベンション協会 会員名簿](https://www.acvb.or.jp/member/list.html)
- 追加候補: [秋田市 企業情報データベース](https://www.city.akita.akita.jp/wp/database/)

## このソースを使う理由
- 商工会議所やロータリークラブとは異なる団体ソースである
- 企業名、住所、電話番号、企業サイト導線がまとまっており、人的確認しやすい
- 別ソース耐性と横断時の衝突候補確認に使いやすい

## 今回の位置づけ
- usable 完成よりも、ソース種類を増やすことを優先する
- 重複統合、同名企業誤紐づけの実データ母数を増やすための着手

## 重複統合確認に使う企業
- `株式会社くまがい印刷`
  - 社会福祉協議会
  - 秋田観光コンベンション協会
  - 公式サイト
- `秋田印刷製本株式会社`
  - 社会福祉協議会
  - 秋田観光コンベンション協会
  - 秋田市企業情報データベース
- `株式会社フロム・エー`
  - 社会福祉協議会
  - 秋田市企業情報データベース
  - 表記ゆれと電話差分があり、誤統合防止確認に使える

## 重複統合の実行結果
- 入力企業数: 11
- 出力企業数: 9
- usable: 9

参照:
- [秋田市 実データ重複統合結果](/C:/Users/fln_user/Documents/作業用フォルダー/docs/akita-real-data-duplicate-integration-result.md)
