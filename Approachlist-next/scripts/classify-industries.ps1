param(
    [Parameter(Mandatory = $true)]
    [string]$InputCsv,

    [Parameter(Mandatory = $true)]
    [string]$OutputCsv,

    [Parameter(Mandatory = $true)]
    [string]$EvidenceCsv
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http

function New-IndustryHttpClient {
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $true
    $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate

    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(20)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36')
    $client.DefaultRequestHeaders.Accept.ParseAdd('text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8')
    $client.DefaultRequestHeaders.AcceptLanguage.ParseAdd('ja,en-US;q=0.9,en;q=0.8')
    $client.DefaultRequestHeaders.TryAddWithoutValidation('Upgrade-Insecure-Requests', '1') | Out-Null

    return $client
}

function Get-FirstAvailableHeaderName {
    param(
        [string[]]$HeaderNames,
        [string[]]$Candidates
    )

    foreach ($candidate in $Candidates) {
        if ($HeaderNames -contains $candidate) {
            return $candidate
        }
    }

    return $null
}

function Normalize-Text {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    return ([regex]::Replace(($Text -replace [char]0x3000, ' '), '\s+', ' ')).Trim()
}

function Decode-HtmlText {
    param([byte[]]$Bytes, [string]$ContentType)

    $encodings = New-Object System.Collections.Generic.List[string]
    if ($ContentType -match 'charset=([\w-]+)') {
        $encodings.Add($matches[1])
    }

    foreach ($encodingName in @('utf-8', 'shift_jis', 'cp932', 'euc-jp', 'iso-8859-1')) {
        if (-not $encodings.Contains($encodingName)) {
            $encodings.Add($encodingName)
        }
    }

    foreach ($encodingName in $encodings) {
        try {
            $encoding = [Text.Encoding]::GetEncoding($encodingName)
            return $encoding.GetString($Bytes)
        }
        catch {
            continue
        }
    }

    return [Text.Encoding]::UTF8.GetString($Bytes)
}

function Get-RootException {
    param([System.Exception]$Exception)

    $current = $Exception
    while ($current -and $current.InnerException) {
        $current = $current.InnerException
    }

    return $current
}

function Get-ShortErrorLabel {
    param([System.Exception]$Exception)

    if (-not $Exception) {
        return 'unknown'
    }

    $root = Get-RootException -Exception $Exception
    $statusCode = $null
    if ($root -and $root.PSObject.Properties['StatusCode']) {
        $statusCode = $root.StatusCode
    }
    elseif ($Exception.InnerException -and $Exception.InnerException.PSObject.Properties['StatusCode']) {
        $statusCode = $Exception.InnerException.StatusCode
    }

    if ($statusCode) {
        return ('http_' + [int]$statusCode)
    }

    $messageParts = New-Object System.Collections.Generic.List[string]
    $current = $Exception
    while ($current) {
        if (-not [string]::IsNullOrWhiteSpace($current.Message)) {
            $messageParts.Add($current.Message)
        }
        if (-not [string]::IsNullOrWhiteSpace($current.GetType().FullName)) {
            $messageParts.Add($current.GetType().FullName)
        }
        $current = $current.InnerException
    }

    $text = (($messageParts -join ' ')).ToLowerInvariant()
    if ($text -match 'timed out|timeout|taskcanceledexception|operationcanceledexception') {
        return 'timeout'
    }
    if ($text -match 'name or service not known|no such host|dns') {
        return 'dns'
    }
    if ($text -match 'ssl|tls|secure channel|certificate') {
        return 'tls'
    }
    if ($text -match 'forbidden|403') {
        return 'http_403'
    }
    if ($text -match '404') {
        return 'http_404'
    }
    if ($text -match '429|too many requests') {
        return 'http_429'
    }
    if ($text -match 'actively refused|connection refused') {
        return 'connection_refused'
    }
    if ($text -match 'socket|connect') {
        return 'connection'
    }

    return ($Exception.GetType().Name -replace '[^A-Za-z0-9]+', '_').ToLowerInvariant()
}

function Get-FetchFailureEvidence {
    param([System.Exception]$Exception)

    $label = Get-ShortErrorLabel -Exception $Exception
    $root = Get-RootException -Exception $Exception
    $message = ''
    if ($root) {
        $message = Normalize-Text ($root.Message)
    }
    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = Normalize-Text ($Exception.Message)
    }
    if ([string]::IsNullOrWhiteSpace($message)) {
        return ('fetch_failed:' + $label)
    }

    $safe = ($message -replace '[;,\r\n]+', ' ')
    if ($safe.Length -gt 80) {
        $safe = $safe.Substring(0, 80).TrimEnd()
    }

    return ('fetch_failed:' + $label + ':' + $safe)
}

function Get-PageData {
    param([string]$Url)

    $lastException = $null
    foreach ($attempt in 1..2) {
        try {
            $response = $script:IndustryHttpClient.GetAsync($Url).GetAwaiter().GetResult()
            try {
                if (-not $response.IsSuccessStatusCode) {
                    throw [System.Net.Http.HttpRequestException]::new(("HTTP status " + [int]$response.StatusCode))
                }

                $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
                $contentType = ''
                if ($response.Content.Headers.ContentType) {
                    $contentType = $response.Content.Headers.ContentType.ToString()
                }
                $html = Decode-HtmlText -Bytes $bytes -ContentType $contentType
                $finalUrl = $response.RequestMessage.RequestUri.AbsoluteUri

                $title = ''
                $titleMatch = [regex]::Match($html, '<title[^>]*>(.*?)</title>', 'IgnoreCase,Singleline')
                if ($titleMatch.Success) {
                    $title = Normalize-Text ([System.Net.WebUtility]::HtmlDecode(([regex]::Replace($titleMatch.Groups[1].Value, '<[^>]+>', ' '))))
                }

                $text = [regex]::Replace($html, '<script[\s\S]*?</script>', ' ', 'IgnoreCase')
                $text = [regex]::Replace($text, '<style[\s\S]*?</style>', ' ', 'IgnoreCase')
                $text = [regex]::Replace($text, '<[^>]+>', ' ')
                $text = Normalize-Text ([System.Net.WebUtility]::HtmlDecode($text))

                $links = New-Object System.Collections.Generic.List[object]
                $matches = [regex]::Matches($html, '<a[^>]*href=["''](?<href>[^"'']+)["''][^>]*>(?<text>.*?)</a>', 'IgnoreCase,Singleline')
                foreach ($match in $matches) {
                    $href = $match.Groups['href'].Value
                    $label = Normalize-Text ([System.Net.WebUtility]::HtmlDecode(([regex]::Replace($match.Groups['text'].Value, '<[^>]+>', ' '))))
                    $links.Add([pscustomobject]@{
                        href = $href
                        text = $label
                    })
                }

                return [pscustomobject]@{
                    Url = $finalUrl
                    Title = $title
                    Text = $text
                    Links = $links
                }
            }
            finally {
                if ($response) {
                    $response.Dispose()
                }
            }
        }
        catch {
            $lastException = $_.Exception
            $label = Get-ShortErrorLabel -Exception $lastException
            if (($label -notin @('timeout', 'connection', 'connection_refused', 'dns')) -or $attempt -eq 2) {
                throw
            }
            Start-Sleep -Milliseconds 500
        }
    }

    throw $lastException
}

function Test-IndustryHttpAccess {
    param([string[]]$Urls)

    $candidateUrls = @($Urls | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique -First 3)
    if ($candidateUrls.Count -eq 0) {
        return
    }

    $networkFailureCount = 0
    $lastEvidence = ''
    foreach ($candidateUrl in $candidateUrls) {
        try {
            $null = Get-PageData -Url $candidateUrl
            return
        }
        catch {
            $label = Get-ShortErrorLabel -Exception $_.Exception
            $lastEvidence = Get-FetchFailureEvidence -Exception $_.Exception
            if ($label -in @('timeout', 'dns', 'tls', 'connection', 'connection_refused')) {
                $networkFailureCount += 1
            }
        }
    }

    if ($networkFailureCount -eq $candidateUrls.Count) {
        throw ("Industry classification could not access external websites. Re-run in a network-enabled environment. Sample failure: " + $lastEvidence)
    }
}

function Get-CandidateLinks {
    param([pscustomobject]$Page)

    $aboutHints = @('会社概要', '会社案内', '企業情報', '会社紹介', 'about', 'company', 'profile', 'overview')
    $businessHints = @('事業内容', '業務内容', '事業案内', 'サービス', '施工', '製品', '商品', 'business', 'service', 'works', 'product')

    $baseUri = [Uri]$Page.Url
    $candidates = New-Object System.Collections.Generic.List[object]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    [void]$seen.Add($Page.Url)

    foreach ($link in $Page.Links) {
        if ([string]::IsNullOrWhiteSpace($link.href)) {
            continue
        }
        if ($link.href.StartsWith('mailto:') -or $link.href.StartsWith('tel:') -or $link.href.StartsWith('javascript:')) {
            continue
        }

        try {
            $absolute = [Uri]::new($baseUri, $link.href).AbsoluteUri.Split('#')[0]
            $absoluteUri = [Uri]$absolute
        }
        catch {
            continue
        }

        if ($absoluteUri.Host -ne $baseUri.Host) {
            continue
        }
        if ($seen.Contains($absolute)) {
            continue
        }

        $blob = ($link.text + ' ' + $absolute).ToLowerInvariant()
        $score = 0
        foreach ($hint in $aboutHints) {
            if ($blob.Contains($hint.ToLowerInvariant())) {
                $score += 10
                break
            }
        }
        foreach ($hint in $businessHints) {
            if ($blob.Contains($hint.ToLowerInvariant())) {
                $score += 8
                break
            }
        }
        if ($score -le 0) {
            continue
        }

        [void]$seen.Add($absolute)
        $candidates.Add([pscustomobject]@{
            Score = $score
            Url = $absolute
        })
    }

    return $candidates |
        Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Url'; Descending = $false } |
        Select-Object -First 4 -ExpandProperty Url
}

function Get-CategoryRules {
    return [ordered]@{
        '建設業' = @('建設', '建築', '土木', '工事', '施工', '設計', 'リフォーム', '住宅', '塗装', '設備工事', '電気工事', '防水', '解体', '内装', '外構')
        '不動産業' = @('不動産', '賃貸', '売買', '仲介', '物件', 'マンション', 'アパート', '土地', '管理', 'テナント')
        '製造業' = @('製造', '生産', '加工', '工場', '醸造', '酒造', '印刷', '製麺', '部品', '機械', '装置', '製品', '半導体', '素材')
        '情報通信業' = @('システム', 'ソフトウェア', 'アプリ', 'IT', 'ICT', 'WEB', 'クラウド', 'ネットワーク', 'DX', 'データ', '情報通信', 'デジタル')
        '宿泊業・飲食サービス業' = @('ホテル', '旅館', '宿泊', 'レストラン', '飲食', '居酒屋', '寿司', 'そば', '料理', 'ランチ', 'ディナー', 'resort')
        '卸売業・小売業' = @('販売', '卸', '小売', '商社', '店舗', 'ショップ', '取扱', '直売', '酒販', '米穀', '生花', '金物', 'ギフト')
        '金融業・保険業' = @('銀行', '信用金庫', '金融', '保険', '融資', '預金', 'ローン')
        '運輸業・郵便業' = @('バス', '運送', '物流', '貨物', '旅客', '交通', '路線', '貸切', '時刻表')
        '電気・ガス・熱供給・水道業' = @('発電', '電力', 'エネルギー', 'ガス', '熱供給', '再生可能', 'バイオマス', '水道')
        '教育・学習支援業' = @('教習所', 'スクール', '講習', '学習', '教育', '教習', '免許')
        '生活関連サービス業・娯楽業' = @('サロン', 'リラクゼーション', 'エステ', '美容', 'クリーニング', '理容', 'セラピー', '花屋')
        'サービス業' = @('コンサル', 'メンテナンス', '保守', '支援', '人材', '代行', '研究所', '検査', 'サポート')
    }
}

function Get-ManualOverrides {
    return @{
        '株式会社新井コロナ' = @('製造業', 'なし', 'manual_override')
        '株式会社第四北越銀行新井支店' = @('金融業・保険業', 'なし', 'manual_override')
        '株式会社八十二長野銀行新井支店' = @('金融業・保険業', 'なし', 'manual_override')
        '新井信用金庫' = @('金融業・保険業', 'なし', 'manual_override')
        '株式会社LOTTE Hotel Arai' = @('宿泊業・飲食サービス業', 'なし', 'manual_override')
        '頸南バス株式会社' = @('運輸業・郵便業', 'なし', 'manual_override')
        '株式会社新井自動車教習所' = @('教育・学習支援業', 'なし', 'manual_override')
        '株式会社ダイセル新井工場' = @('製造業', 'なし', 'manual_override')
        'タワー・パートナーズセミコンダクター株式会社 新井地区' = @('製造業', 'なし', 'manual_override')
        '君の井酒造 株式会社' = @('製造業', 'なし', 'manual_override')
        '鮎正宗酒造株式会社' = @('製造業', 'なし', 'manual_override')
        '千代の光酒造株式会社' = @('製造業', 'なし', 'manual_override')
        '有限会社かんずり' = @('製造業', 'なし', 'manual_override')
        '有限会社嶺村製麺所' = @('製造業', 'なし', 'manual_override')
        '株式会社 樗沢組' = @('建設業', 'なし', 'manual_override')
        '株式会社樗沢組' = @('建設業', 'なし', 'manual_override')
        '株式会社平和堂' = @('製造業', 'なし', 'manual_override')
        '合名会社和田商店' = @('製造業', 'なし', 'manual_override')
        '寿し芳' = @('宿泊業・飲食サービス業', 'なし', 'manual_override')
        '株式会社ひだなん' = @('卸売業・小売業', '宿泊業・飲食サービス業', 'manual_override')
        'マルニ西脇株式会社' = @('製造業', 'なし', 'manual_override')
        '株式会社古川商会' = @('卸売業・小売業', 'サービス業', 'manual_override')
        '株式会社三ツ和' = @('卸売業・小売業', 'サービス業', 'manual_override')
        '株式会社矢崎商会' = @('サービス業', '卸売業・小売業', 'manual_override')
        '株式会社アルゴス' = @('サービス業', 'なし', 'manual_override')
        '株式会社 アイケーテック' = @('建設業', 'なし', 'manual_override')
        '株式会社 ケーナール' = @('製造業', 'なし', 'manual_override')
        '有限会社上越設備' = @('建設業', 'なし', 'manual_override')
        'サクラ印刷株式会社' = @('製造業', '情報通信業', 'manual_override')
    }
}

function Classify-Industry {
    param(
        [string]$CompanyName,
        [string]$Url
    )

    $manual = Get-ManualOverrides
    if ($manual.ContainsKey($CompanyName)) {
        $entry = $manual[$CompanyName]
        return [pscustomobject]@{
            Industry1 = $entry[0]
            Industry2 = $entry[1]
            Evidence = $entry[2]
        }
    }

    try {
        $pages = New-Object System.Collections.Generic.List[object]
        $firstPage = Get-PageData -Url $Url
        $pages.Add($firstPage) | Out-Null
        Start-Sleep -Milliseconds 400

        foreach ($candidate in (Get-CandidateLinks -Page $firstPage)) {
            try {
                $pages.Add((Get-PageData -Url $candidate)) | Out-Null
                Start-Sleep -Milliseconds 400
            }
            catch {
                continue
            }
        }
    }
    catch {
        return [pscustomobject]@{
            Industry1 = '不明'
            Industry2 = 'なし'
            Evidence = Get-FetchFailureEvidence -Exception $_.Exception
        }
    }

    $combined = (($pages | ForEach-Object { Normalize-Text ($_.Title + ' ' + $_.Text) }) -join ' ').ToLowerInvariant()
    $rules = Get-CategoryRules
    $scores = @{}
    foreach ($category in $rules.Keys) {
        $score = 0
        foreach ($keyword in $rules[$category]) {
            $escaped = [regex]::Escape($keyword.ToLowerInvariant())
            $score += ([regex]::Matches($combined, $escaped)).Count
        }
        if ($score -gt 0) {
            $scores[$category] = $score
        }
    }

    if ($scores.Count -eq 0) {
        return [pscustomobject]@{
            Industry1 = '不明'
            Industry2 = 'なし'
            Evidence = 'no_keyword_match'
        }
    }

    $ranked = $scores.GetEnumerator() |
        Sort-Object @{ Expression = 'Value'; Descending = $true }, @{ Expression = 'Name'; Descending = $false }
    $top = $ranked | Select-Object -First 1
    if ($top.Value -lt 2) {
        return [pscustomobject]@{
            Industry1 = '不明'
            Industry2 = 'なし'
            Evidence = ('low_score:' + $top.Name + ':' + $top.Value)
        }
    }

    $industry2 = 'なし'
    $second = $ranked | Select-Object -Skip 1 -First 1
    if ($second -and $second.Name -ne $top.Name -and $second.Value -ge [Math]::Max(3, [int]([Math]::Ceiling($top.Value * 0.55)))) {
        $industry2 = $second.Name
    }

    $evidence = ($ranked | Select-Object -First 4 | ForEach-Object { $_.Name + ':' + $_.Value }) -join '; '
    return [pscustomobject]@{
        Industry1 = $top.Name
        Industry2 = $industry2
        Evidence = $evidence
    }
}

$script:IndustryHttpClient = New-IndustryHttpClient

$rows = Import-Csv -Path $InputCsv
$outputRows = New-Object System.Collections.Generic.List[object]
$evidenceRows = New-Object System.Collections.Generic.List[object]

if (-not $rows -or $rows.Count -eq 0) {
    throw "Input CSV has no rows: $InputCsv"
}

$headerNames = @($rows[0].PSObject.Properties.Name)
$companyHeader = Get-FirstAvailableHeaderName -HeaderNames $headerNames -Candidates @('企業名', 'company_name', 'company')
$urlHeader = Get-FirstAvailableHeaderName -HeaderNames $headerNames -Candidates @('公式HP', '公式サイトURL', '公式サイト', 'website', 'official_hp', 'url', 'site_url')

if (-not $companyHeader) {
    throw "Could not find company name column. Expected one of: 企業名, company_name, company"
}

if (-not $urlHeader) {
    throw "Could not find website column. Expected one of: 公式HP, 公式サイトURL, 公式サイト, website, official_hp, url, site_url"
}

Test-IndustryHttpAccess -Urls ($rows | ForEach-Object { [string]$_.$urlHeader })

foreach ($row in $rows) {
    $url = [string]$row.$urlHeader
    $company = [string]$row.$companyHeader

    if ([string]::IsNullOrWhiteSpace($url) -or $url -eq '不明' -or $url -eq 'UNKNOWN') {
        $result = [pscustomobject]@{
            Industry1 = '不明'
            Industry2 = 'なし'
            Evidence = 'no_official_hp'
        }
    }
    else {
        $result = Classify-Industry -CompanyName $company -Url $url
        Start-Sleep -Milliseconds 600
    }

    $properties = [ordered]@{}
    foreach ($property in $row.PSObject.Properties) {
        $properties[$property.Name] = $property.Value
    }
    $properties['業種1'] = $result.Industry1
    $properties['業種2'] = $result.Industry2
    $outputRows.Add([pscustomobject]$properties) | Out-Null

    $evidenceRows.Add([pscustomobject]@{
        企業名 = $company
        公式HP = $url
        業種1 = $result.Industry1
        業種2 = $result.Industry2
        判定根拠 = $result.Evidence
    }) | Out-Null
}

$outputRows | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8
$evidenceRows | Export-Csv -Path $EvidenceCsv -NoTypeInformation -Encoding UTF8

if ($script:IndustryHttpClient) {
    $script:IndustryHttpClient.Dispose()
}
