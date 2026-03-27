# 低コスト版 チーム運用手順書

## 1. この手順書の目的
この手順書は、営業アプローチリスト作成ツールを、複数人がそれぞれのローカルPCで使うための手順をまとめたものです。

この運用では、Webアプリや共有サーバーは使いません。  
各自が GitHub から同じリポジトリを取得し、同じコマンドを実行して、営業に渡すCSVを出力します。

## 2. この運用でやること
各メンバーは、基本的に次の流れで作業します。

1. 最新のコードを取得する
2. 自分の担当地域を決める
3. コマンドを実行する
4. `usable.csv` を営業へ渡す
5. ソース追加やルール改善をしたら GitHub に反映する

## 3. 事前に知っておくこと
### 3-1. 営業に渡すファイル
営業に渡すのは、基本的に `*_usable.csv` です。

例:
- `web_sales_list_obihiro_usable.csv`
- `web_sales_list_miyakonojo_usable.csv`

`usable.csv` には、営業で使えると判定された企業だけが入っています。

### 3-2. ローカルで使う前提
このツールは、今はローカルPCで PowerShell を使って実行します。  
ブラウザでボタンを押して使う方式ではありません。

### 3-3. 触る主なファイル
- [approachlist.ps1](C:/Users/fln_user/Documents/作業用フォルダー/scripts/approachlist.ps1)
- [source_registry.csv](C:/Users/fln_user/Documents/作業用フォルダー/config/source_registry.csv)
- [contracted_real.csv](C:/Users/fln_user/Documents/作業用フォルダー/config/contracted_real.csv)
- [implementation-notes.md](C:/Users/fln_user/Documents/作業用フォルダー/docs/implementation-notes.md)

## 4. 最初の準備
### 4-1. リポジトリを取得する
初めて使う人は、PowerShell を開いて次を実行します。

```powershell
git clone https://github.com/kosukekikuchi-coder/Approachlist.git
```

すでにフォルダがある人は、作業フォルダに移動して次を実行します。

```powershell
git pull
```

### 4-2. 作業フォルダを開く
PowerShell で、リポジトリのフォルダに移動します。

```powershell
cd C:\Users\fln_user\Documents\作業用フォルダー
```

## 5. 毎回の基本手順
### 5-1. 作業前に最新化する
必ず最初に次を実行します。

```powershell
git pull
```

これをしないと、他のメンバーの改善や新しい地域設定が反映されません。

### 5-2. 自分の担当地域を確認する
同じ地域を複数人で同時に触らないようにします。

例:
- Aさん: 帯広市
- Bさん: 都城市
- Cさん: 成田市

## 6. 登録済み地域でリストを出す手順
### 6-1. 登録済み地域とは
`source_registry.csv` に、その地域向けの一次ソースが登録されている地域です。

### 6-2. 実行コマンド
登録済み地域の出力は、基本的に次のコマンドで行います。

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\approachlist.ps1 run-web-pipeline
```

### 6-3. 出力を見る
出力は `data/out/` にできます。  
営業に渡すのは `*_usable.csv` です。

主な出力:
- 全件一覧: `web_sales_list_*.csv`
- 営業向け: `web_sales_list_*_usable.csv`
- 件数レポート: `web_sales_list_*_report.csv`

### 6-4. どれを営業に渡すか
営業には、`*_usable.csv` を渡します。

例:
- [web_sales_list_obihiro_usable.csv](C:/Users/fln_user/Documents/作業用フォルダー/data/out/web_sales_list_obihiro_usable.csv)

## 7. 未登録地域でリストを出す手順
### 7-1. 未登録地域とは
`source_registry.csv` に、その地域のソースがまだ入っていない地域です。

### 7-2. 実行コマンド
未登録地域は `bootstrap-web-pipeline` を使います。

例: 帯広市

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\approachlist.ps1 bootstrap-web-pipeline -MunicipalityName 帯広市 -AreasPath config/areas_real.csv -ContractedPath config/contracted_real.csv
```

### 7-3. このコマンドで内部的にやっていること
このコマンドは、内部で次をまとめて実行します。

1. ソース候補を探す
2. ソースを仮登録する
3. 地域抽出をする
4. Web収集をする
5. 企業情報を整形する
6. usable リストを出す

### 7-4. 出力を見る
未登録地域も、営業に渡すのは `*_usable.csv` です。

例:
- [web_sales_list_bootstrap_obihiro_usable.csv](C:/Users/fln_user/Documents/作業用フォルダー/data/out/web_sales_list_bootstrap_obihiro_usable.csv)

## 8. 都城市のように地域名を指定して出したいとき
たとえば「都城市で出したい」ときは、まず bootstrap を使います。

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\approachlist.ps1 bootstrap-web-pipeline -MunicipalityName 都城市 -AreasPath config/areas_real.csv -ContractedPath config/contracted_real.csv
```

出力確認先の例:
- [web_sales_list_miyakonojo.csv](C:/Users/fln_user/Documents/作業用フォルダー/data/out/web_sales_list_miyakonojo.csv)
- [web_sales_list_miyakonojo_usable.csv](C:/Users/fln_user/Documents/作業用フォルダー/data/out/web_sales_list_miyakonojo_usable.csv)
- [web_sales_list_miyakonojo_report.csv](C:/Users/fln_user/Documents/作業用フォルダー/data/out/web_sales_list_miyakonojo_report.csv)

## 9. 途中で内容を確認したいとき
段階ごとに確認したい場合は、次の順に個別実行できます。

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\approachlist.ps1 build-source-workset
powershell -ExecutionPolicy Bypass -File .\scripts\approachlist.ps1 extract-member-candidates
powershell -ExecutionPolicy Bypass -File .\scripts\approachlist.ps1 normalize-member-candidates
powershell -ExecutionPolicy Bypass -File .\scripts\approachlist.ps1 extract-company-details
powershell -ExecutionPolicy Bypass -File .\scripts\approachlist.ps1 run-web-pipeline
```

## 10. 作業後に GitHub へ反映する手順
### 10-1. どんなときに反映するか
次のような変更をしたときは GitHub に反映します。

- `source_registry.csv` を更新した
- ノイズ除去ルールを改善した
- 新しい地域のソースを追加した
- 手順書やメモを更新した

### 10-2. 反映手順
```powershell
git add .
git commit -m "Update source registry for Miyakonojo"
git push
```

### 10-3. 他のメンバーがやること
他のメンバーは、その後 `git pull` を実行します。

```powershell
git pull
```

## 11. 困ったときの確認先
### 11-1. まず見るファイル
- [implementation-notes.md](C:/Users/fln_user/Documents/作業用フォルダー/docs/implementation-notes.md)
- [web-pipeline-progress.md](C:/Users/fln_user/Documents/作業用フォルダー/docs/web-pipeline-progress.md)

### 11-2. ログを見る
`logs/` に実行ログが出ます。

例:
- [run-web-pipeline.log](C:/Users/fln_user/Documents/作業用フォルダー/logs/run-web-pipeline.log)
- `bootstrap-web-pipeline-<city>.log`

### 11-3. まず確認すること
うまく出ないときは、次を見ます。

1. `git pull` をしたか
2. 地域名が正しいか
3. `source_registry.csv` にその地域があるか
4. `data/out/` に `*_usable.csv` ができているか
5. `logs/` にエラーが出ていないか

## 12. チーム運用ルール
最低限、次のルールで運用します。

1. 作業前に必ず `git pull`
2. 同じ地域を複数人で同時に触らない
3. 営業に渡すのは基本 `*_usable.csv`
4. `source_registry.csv` を変えたら `git push`
5. ツール改善をしたら、他メンバーが `git pull` できる状態にする

## 13. いちばん簡単な使い方
迷ったら、次の考え方で大丈夫です。

### パターンA: 登録済み地域
1. `git pull`
2. `run-web-pipeline`
3. `*_usable.csv` を営業へ渡す

### パターンB: 未登録地域
1. `git pull`
2. `bootstrap-web-pipeline -MunicipalityName ○○市`
3. `*_usable.csv` を営業へ渡す

## 14. この手順書の位置づけ
この手順書は、まずチーム全員がローカル運用で回せるようにするための最小手順です。  
Webアプリ化や共有サーバー化は、この運用が安定してから次段階で検討します。
