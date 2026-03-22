# 実データ企業受け入れテスト準備リスト

## 目的
3件に絞った実データ地域
- 岡崎市
- 津山市
- 高山市

を対象に、企業データ側でも受け入れテストを進めるための準備事項を整理する。

## 現行CLIが前提としている入力
### 1. 企業一覧入力
現行の `build-company-master` は、以下の列を前提に企業一覧を読む。

- `company_name`
- `municipality`
- `source_org`
- `source_url`

参照:
- [member_companies.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/fixtures/member_companies.csv)

### 2. 企業詳細入力
現行の `build-company-master` は、以下の列を前提に企業詳細を読む。

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

参照:
- [company_details.csv](/C:/Users/fln_user/Documents/作業用フォルダー/data/fixtures/company_details.csv)

## 実データ受け入れで最初に必要なもの
### 1. 3地域分の企業一覧
まず必要なのは、以下の3地域に対する企業一覧データ。

- 岡崎市
- 津山市
- 高山市

最低限、以下の列を持っていれば受け入れ確認に使える。

- `company_name`
- `municipality`
- `source_org`
- `source_url`

### 2. 3地域分の企業詳細
次に必要なのは、企業ごとの詳細データ。

最低限、以下がほしい。

- `company_name`
- `municipality`
- `address`
- `phone`
- `website`
- `contact_form_url`
- `detail_source_url`

### 3. スコア判定用の暫定値
現行CLIではスコア列を出すために以下が必要。

- `industry_fit`
- `local_focus`
- `network_affinity`
- `contactability`

最初の実データ受け入れでは、精度より流れ確認が目的なので、暫定的な手入力でもよい。

## どこまで揃えば実データ受け入れを開始できるか
### 最小開始条件
- 3地域のうち、まず1地域だけでも企業一覧がある
- その企業一覧のうち数社分の詳細がある
- `detail_source_url` が追跡できる
- 少なくとも1社は usable 達成、1社は usable 未達になる
- 少なくとも1社は `contact_form_url` の有無を確認できる

## 初回におすすめの粒度
最初から大量件数を集めず、以下のような小ささが安全。

- 1地域
- 5〜10社
- 団体ソースは1〜2種類

この粒度なら、以下を見やすい。

- 誤企業情報の付与がないか
- usable 判定が妥当か
- `detail_source_url` が追えるか
- `contact_form_url` の扱いが妥当か
- スコア理由が読めるか

## 事前に決めるべきこと
### 企業一覧の入手元
- 実際の団体HP由来でいくか
- 手元で先に表を作るか

### 企業詳細の入手方法
- 手動で少量整えるか
- 先にクローリング導線を実装するか

### スコア暫定値の付け方
- 手入力でよいか
- 一律初期値でよいか

## おすすめの進め方
1. 3地域のうち1地域を先に選ぶ
2. その地域の企業一覧を5〜10社だけ作る
3. 詳細データを手動で埋める
4. 現行CLIで `company_master.csv` を生成する
5. usable / ソース / 問い合わせ先 / スコア理由を確認する

## 次の実作業
1. 岡崎市・津山市・高山市のうち、最初に着手する1地域を決める
2. その地域の企業一覧CSVを作る
3. その地域の企業詳細CSVを作る
4. 現行CLIで読み込めるように fixture 形式へ合わせる
