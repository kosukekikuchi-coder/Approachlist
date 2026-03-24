# 重複統合 最小実装方針

## 目的
[重複統合 受け入れテストケース](/C:/Users/fln_user/Documents/作業用フォルダー/docs/duplicate-integration-test-cases.md) の `DIT-001` から `DIT-003` を通すための最小実装方針を整理する。

## 現状
現行の [approachlist.ps1](/C:/Users/fln_user/Documents/作業用フォルダー/scripts/approachlist.ps1) は、`build-company-master` 内で次の前提で動いている。

- `member_companies.csv` を1行ずつ処理する
- `company_details.csv` から `company_name + municipality` の完全一致を探す
- 一致した1件をそのまま `company_master.csv` に出す
- 重複統合はまだ持っていない

このため、同一企業が複数ソースに出た場合は、そのまま複数行で残る前提になっている。

## 最小実装の考え方
初回は、`build-company-master` の後段で **重複候補を束ねる処理を1段追加する** のが最小。

流れは次のイメージ。

1. いままでどおり `member_companies.csv` と `company_details.csv` を突合する
2. 一度、候補レコードをすべてメモリ上に作る
3. その後で、重複統合ルールに従って1件に束ねる
4. 最後に `company_master.csv` に出力する

## 初回の統合ルール
初回は、かなり保守的にする。

### 統合してよい条件
次のどちらかを満たすときだけ、同一企業候補として扱う。

1. `municipality` が同じ かつ `company_name` 正規化後が一致し、`phone` が一致する
2. `municipality` が同じ かつ `company_name` 正規化後が一致し、`address` が一致する

### 統合しない条件
- `company_name` が似ているだけ
- `municipality` が違う
- `phone` も `address` も一致しない
- 情報が弱く、同一企業と断定しきれない

## 正規化の最小ルール
初回は、次だけ除いて比較する。

- `株式会社`
- `有限会社`
- `合同会社`
- `（株）`
- `㈱`
- 空白
- 括弧

これ以上の強い正規化は初回ではやらない。

## 統合後の採用ルール
### 1. 代表レコード
- 公式サイトや詳細情報が埋まっているレコードを優先する
- 情報量が同じなら、最初に見つかったレコードを代表にする

### 2. 項目ごとの採用
- `address`
  - 空欄でない方を優先
- `phone`
  - 空欄でない方を優先
- `website`
  - 空欄でない方を優先
- `contact_form_url`
  - 公式サイト起点で確認済みのものだけ採用
- `detail_source_url`
  - 代表レコードのものを残す

### 3. ソース情報
初回は複数保持までやらず、まずは次の2列を追加するのが現実的。

- `source_org`
  - 代表ソース
- `source_url`
  - 代表ソース

ただし、将来のために次の列追加を候補として残す。

- `source_count`
- `source_summary`

## テストケースとの対応
### DIT-001 同一企業の統合
- `company_name` 正規化
- `municipality` 一致
- `phone` または `address` 一致

で1件に束ねる

### DIT-002 強いソースの優先
- `website`
- `detail_source_url`
- `contact_form_url`

の有無を見て、情報の強いレコードを代表にする

### DIT-003 誤統合防止
- `company_name` 近似だけでは統合しない
- `phone` / `address` が一致しない限り別件のままにする

## コード変更の最小単位
初回は [approachlist.ps1](/C:/Users/fln_user/Documents/作業用フォルダー/scripts/approachlist.ps1) に次の関数を足すだけでよい。

1. `Normalize-CompanyName`
2. `Test-DuplicateCandidate`
3. `Merge-CompanyRows`

そして、`Invoke-BuildCompanyMaster` の最後で `outputRows` を統合関数に通してから CSV 出力する。

## 今回やらないこと
- 複数ソースの完全保持
- 高度な住所正規化
- AI判定による重複統合
- 地域をまたいだ統合
- 類似名のあいまい統合

## 現時点のおすすめ
初回実装は、**秋田市の `株式会社くまがい印刷` を1件に束ねられる最小実装** に絞るのが最短。

## 次にやるべきこと
1. この方針で問題ないかを確認する
2. 問題なければ `approachlist.ps1` に最小関数を追加する
3. `DIT-001` から `DIT-003` を小さく回す
