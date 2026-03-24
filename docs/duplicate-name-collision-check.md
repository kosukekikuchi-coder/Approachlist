# 重複・同名企業衝突 確認メモ

## 目的
実データ確認で、重複統合や同名企業誤紐づけのリスクがどの程度見えているかを整理する。

## 確認対象
- [岡崎市 企業一覧](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/okazaki_member_companies.csv)
- [津山市 企業一覧](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/tsuyama_member_companies.csv)
- [高山市 企業一覧](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/takayama_member_companies.csv)
- [成田市 企業一覧](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/narita_member_companies.csv)
- [長浜市 企業一覧](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/nagahama_member_companies.csv)
- [秋田市 企業一覧](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/akita_member_companies.csv)
- [上田市 企業一覧](/C:/Users/fln_user/Documents/作業用フォルダー/data/real/ueda_member_companies.csv)

## 確認方法
### 1. 完全一致の同名確認
- `company_name` の完全一致で横断チェック

### 2. 近似名の確認
- `株式会社`
- `有限会社`
- `合同会社`
- `（株）`
- `㈱`
- 空白
- 括弧

を除いた正規化名で横断チェック

## 結果
- 対象地域数: 7
- 対象企業数: 56
- 完全一致の同名企業: 0件
- 正規化後の近似同名候補: 0件

## 現時点の評価
- 今回の7地域56社では、重複統合や同名企業誤紐づけの衝突ケースは確認できなかった
- したがって、現時点では **「衝突が起きなかった」ことは確認できた** が、**「衝突時にも安全に扱える」ことまでは未確認** である
- 秋田市と上田市は、usable 完成よりも **衝突確認の母数拡大** を優先して追加した地域である

## 含意
- 今の実データサンプルは、usable 判定やスコア説明の確認には十分役立っている
- 一方で、同名企業誤紐づけという高リスク観点については、7地域に広げてもなお実データで十分に踏めていない
- ただし、同一企業が別ソースに重複掲載されるケースは別途確認できている
- 参照: [複数ソース重複確認メモ](/C:/Users/fln_user/Documents/作業用フォルダー/docs/multi-source-overlap-check.md)

## 次にやるべきこと
1. 地域数または件数を広げて、自然発生する衝突候補を探す
2. 別ソースを混ぜて、同一企業の複数出現を確認する
3. 必要なら、同名企業ケースだけはターゲットを決めて小さく実データ検証する

## 判断
スピード優先の現時点では、**本観点は「未検出」ではなく「未十分確認」** として扱うのが妥当。
