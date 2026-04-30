param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("resolve-areas", "build-company-master", "report-status", "build-real-sales-list", "run-real-pipeline", "build-source-workset", "extract-member-candidates", "normalize-member-candidates", "resolve-company-websites", "extract-company-details", "run-web-pipeline", "discover-source-candidates", "register-source-candidates", "bootstrap-web-pipeline")]
    [string]$Command,

    [int]$MinPopulation = 100000,
    [int]$MaxPopulation = 400000,
    [string]$AreasPath = "config/areas.csv",
    [string]$ContractedPath = "config/contracted.csv",
    [string]$ResolvedAreasPath = "data/out/resolved_areas.csv",
    [string]$MemberCompaniesPath = "data/fixtures/member_companies.csv",
    [string]$CompanyDetailsPath = "data/fixtures/company_details.csv",
    [string]$ScoringPath = "config/scoring.yaml",
    [string]$CompanyMasterPath = "data/out/company_master.csv",
    [string]$ProgressReportPath = "data/out/progress_report.csv",
    [string]$LogPath = "logs/run.log",
    [string]$RealDataDirectory = "data/real",
    [string]$RealResolvedAreasPath = "data/out/real_resolved_areas.csv",
    [string]$RealSalesListPath = "data/out/real_sales_list.csv",
    [string]$RealSalesUsablePath = "data/out/real_sales_list_usable.csv",
    [string]$RealSalesReportPath = "data/out/real_sales_list_report.csv",
    [string]$SourceRegistryPath = "config/source_registry.csv",
    [string]$SourceWorksetPath = "data/out/source_workset.csv",
    [string]$ExtractedMemberCandidatesPath = "data/out/extracted_member_candidates.csv",
    [string]$NormalizedMemberCompaniesPath = "data/out/normalized_member_companies.csv",
    [string]$ResolvedMemberCompaniesPath = "data/out/resolved_member_companies.csv",
    [string]$WebsiteResolutionCandidatesPath = "data/out/website_resolution_candidates.csv",
    [string]$ExtractedCompanyDetailsPath = "data/out/extracted_company_details.csv",
    [string]$WebSalesListPath = "data/out/web_sales_list.csv",
    [string]$WebSalesUsablePath = "data/out/web_sales_list_usable.csv",
    [string]$WebSalesReportPath = "data/out/web_sales_list_report.csv",
    [string]$MunicipalityName = "",
    [string]$SourceDiscoveryPath = "data/out/source_candidates.csv",
    [int]$TopSourceCandidates = 3,
    [int]$TopWebsiteCandidates = 5,
    [string]$BootstrapAreaPath = "data/out/bootstrap_area.csv"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-RepoPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    $repoRoot = Split-Path -Parent $PSScriptRoot
    return Join-Path $repoRoot $Path
}

function Ensure-ParentDirectory {
    param([string]$Path)

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }
}

function Write-LogEntry {
    param(
        [string]$Level,
        [string]$Message,
        [string]$Path
    )

    Ensure-ParentDirectory -Path $Path
    $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level.ToUpperInvariant(), $Message
    Add-Content -Path $Path -Value $line -Encoding UTF8
}

function Test-UnnormalizedCompanyDisplayName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }

    return ($Name -match '㈱|㈲|㍿|（株）|\(株\)|（有）|\(有\)|（同）|\(同\)|（資）|\(資\)|（名）|\(名\)|（合）|\(合\)')
}

function Convert-OutputRowsForCsv {
    param(
        [object[]]$Rows,
        [string]$Path
    )

    $convertedRows = New-Object System.Collections.Generic.List[object]
    $normalizedCount = 0
    $residualCount = 0
    $normalizedSamples = New-Object System.Collections.Generic.List[string]
    $residualSamples = New-Object System.Collections.Generic.List[string]

    foreach ($row in $Rows) {
        if ($null -eq $row) {
            continue
        }

        $hasCompanyName = $false
        $props = [ordered]@{}

        foreach ($prop in $row.PSObject.Properties) {
            $value = $prop.Value

            if ($prop.Name -eq 'company_name') {
                $hasCompanyName = $true
                $originalName = [string]$value
                $canonicalName = Convert-ToCanonicalCompanyDisplayName -Name (Get-SearchCompanyName -Name $originalName)

                if (-not [string]::IsNullOrWhiteSpace($originalName) -and $canonicalName -ne $originalName) {
                    $normalizedCount += 1
                    if ($normalizedSamples.Count -lt 5) {
                        $normalizedSamples.Add(("{0} -> {1}" -f $originalName, $canonicalName)) | Out-Null
                    }
                }

                if (Test-UnnormalizedCompanyDisplayName -Name $canonicalName) {
                    $residualCount += 1
                    if ($residualSamples.Count -lt 5) {
                        $residualSamples.Add($canonicalName) | Out-Null
                    }
                }

                $value = $canonicalName
            }

            $props[$prop.Name] = $value
        }

        if ($hasCompanyName) {
            $convertedRows.Add([pscustomobject]$props) | Out-Null
        }
        else {
            $convertedRows.Add($row) | Out-Null
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($script:CsvNormalizationLogPath)) {
        if ($normalizedCount -gt 0) {
            $message = "csv output normalization applied: path=$Path normalized_company_names=$normalizedCount"
            if ($normalizedSamples.Count -gt 0) {
                $message = "{0} samples=[{1}]" -f $message, ($normalizedSamples -join '; ')
            }
            Write-LogEntry -Level "info" -Message $message -Path $script:CsvNormalizationLogPath
        }

        if ($residualCount -gt 0) {
            $message = "csv output contains company_name values that still look unnormalized: path=$Path residual_company_names=$residualCount"
            if ($residualSamples.Count -gt 0) {
                $message = "{0} samples=[{1}]" -f $message, ($residualSamples -join '; ')
            }
            Write-LogEntry -Level "warning" -Message $message -Path $script:CsvNormalizationLogPath
        }
    }

    return $convertedRows.ToArray()
}

function Write-CsvBom {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Rows,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Ensure-ParentDirectory -Path $Path

    $rowArray = @()
    if ($Rows -is [System.Collections.IEnumerable] -and -not ($Rows -is [string])) {
        foreach ($row in $Rows) {
            $rowArray += $row
        }
    }
    else {
        $rowArray = @($Rows)
    }

    $rowArray = @(Convert-OutputRowsForCsv -Rows $rowArray -Path $Path)

    $csv = @($rowArray | ConvertTo-Csv -NoTypeInformation)
    $encoding = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllLines($Path, $csv, $encoding)
}

function Get-LastGoodCachePath {
    param([string]$Path)

    return "{0}.lastgood.csv" -f $Path
}

function Save-LastGoodCsvCache {
    param(
        [string]$SourcePath
    )

    if (-not (Test-Path $SourcePath)) {
        return
    }

    $cachePath = Get-LastGoodCachePath -Path $SourcePath
    Ensure-ParentDirectory -Path $cachePath
    Copy-Item -Path $SourcePath -Destination $cachePath -Force
}

function Restore-LastGoodCsvCache {
    param(
        [string]$TargetPath
    )

    $cachePath = Get-LastGoodCachePath -Path $TargetPath
    if (-not (Test-Path $cachePath)) {
        return $false
    }

    if ((Get-Item $cachePath).Length -le 3) {
        return $false
    }

    Ensure-ParentDirectory -Path $TargetPath
    Copy-Item -Path $cachePath -Destination $TargetPath -Force
    return $true
}

function Read-SimpleYaml {
    param([string]$Path)

    $content = Get-Content -Path $Path
    $result = @{}
    $section = $null

    foreach ($rawLine in $content) {
        $line = $rawLine.TrimEnd()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith("#")) {
            continue
        }

        if ($line -match '^([A-Za-z_][A-Za-z0-9_]*):\s*$') {
            $section = $matches[1]
            $result[$section] = @{}
            continue
        }

        if ($line -match '^\s{2}([A-Za-z_][A-Za-z0-9_]*):\s*(.+)\s*$') {
            if ($null -eq $section) {
                throw "YAML section is missing before key: $line"
            }

            $key = $matches[1]
            $valueText = $matches[2]
            $numericValue = 0.0
            if ([double]::TryParse($valueText, [ref]$numericValue)) {
                $result[$section][$key] = [double]$numericValue
            }
            else {
                $result[$section][$key] = $valueText.Trim("'", '"')
            }
            continue
        }

        throw "Unsupported YAML line: $line"
    }

    return $result
}

function Get-Rank {
    param(
        [double]$Score,
        [hashtable]$RankThresholds
    )

    $sorted = $RankThresholds.GetEnumerator() | Sort-Object -Property Value -Descending
    foreach ($entry in $sorted) {
        if ($Score -ge [double]$entry.Value) {
            return [string]$entry.Key
        }
    }

    return "C"
}

function Get-ConfidenceLabel {
    param([double]$Confidence)

    if ($Confidence -ge 0.75) { return "High" }
    if ($Confidence -ge 0.45) { return "Medium" }
    return "Low"
}

function Join-ReasonParts {
    param([string[]]$Values)

    $filtered = @($Values | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($filtered.Count -eq 0) {
        return ""
    }

    return ($filtered -join " / ")
}

function Normalize-CompanyName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return ""
    }

    $normalized = $Name.Trim()
    $normalized = $normalized -replace '(\u682A\u5F0F\u4F1A\u793E|\u6709\u9650\u4F1A\u793E|\u5408\u540C\u4F1A\u793E|\u5408\u8CC7\u4F1A\u793E|\u5408\u540D\u4F1A\u793E|\uFF08\u682A\uFF09|\u3231)', ''
    $normalized = $normalized -replace '[\s\u3000\(\)\uFF08\uFF09]', ''
    return $normalized
}

function New-UnicodeString {
    param([int[]]$CodePoints)

    return (-join ($CodePoints | ForEach-Object { [char]$_ }))
}

function Convert-ToCanonicalCompanyDisplayName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return ""
    }

    $kabushiki = New-UnicodeString @(0x682A, 0x5F0F, 0x4F1A, 0x793E)
    $yugen = New-UnicodeString @(0x6709, 0x9650, 0x4F1A, 0x793E)
    $godo = New-UnicodeString @(0x5408, 0x540C, 0x4F1A, 0x793E)
    $goshi = New-UnicodeString @(0x5408, 0x8CC7, 0x4F1A, 0x793E)
    $gomei = New-UnicodeString @(0x5408, 0x540D, 0x4F1A, 0x793E)
    $openParen = '('
    $closeParen = ')'
    $fwOpenParen = New-UnicodeString @(0xFF08)
    $fwCloseParen = New-UnicodeString @(0xFF09)
    $kabbrev = New-UnicodeString @(0x3231)
    $ybrev = New-UnicodeString @(0x3232)

    $normalized = [System.Net.WebUtility]::HtmlDecode($Name)
    $normalized = $normalized.Normalize([Text.NormalizationForm]::FormKC)
    $normalized = $normalized -replace '[\u3000\s]+', ' '
    $normalized = $normalized.Trim()

    $normalized = $normalized.Replace($openParen + [char]0x682A + $closeParen, $kabushiki)
    $normalized = $normalized.Replace($fwOpenParen + [char]0x682A + $fwCloseParen, $kabushiki)
    $normalized = $normalized.Replace($kabbrev, $kabushiki)

    $normalized = $normalized.Replace($openParen + [char]0x6709 + $closeParen, $yugen)
    $normalized = $normalized.Replace($fwOpenParen + [char]0x6709 + $fwCloseParen, $yugen)
    $normalized = $normalized.Replace($ybrev, $yugen)

    $normalized = $normalized.Replace($openParen + [char]0x540C + $closeParen, $godo)
    $normalized = $normalized.Replace($fwOpenParen + [char]0x540C + $fwCloseParen, $godo)
    $normalized = $normalized.Replace($openParen + [char]0x5408 + $closeParen, $godo)
    $normalized = $normalized.Replace($fwOpenParen + [char]0x5408 + $fwCloseParen, $godo)

    $normalized = $normalized.Replace($openParen + [char]0x8CC7 + $closeParen, $goshi)
    $normalized = $normalized.Replace($fwOpenParen + [char]0x8CC7 + $fwCloseParen, $goshi)
    $normalized = $normalized.Replace($openParen + [char]0x540D + $closeParen, $gomei)
    $normalized = $normalized.Replace($fwOpenParen + [char]0x540D + $fwCloseParen, $gomei)

    $normalized = $normalized -replace '\(\s*株\s*\)', $kabushiki
    $normalized = $normalized -replace '\(\s*有\s*\)', $yugen
    $normalized = $normalized -replace '\(\s*同\s*\)', $godo
    $normalized = $normalized -replace '\(\s*資\s*\)', $goshi
    $normalized = $normalized -replace '\(\s*名\s*\)', $gomei

    $normalized = $normalized -replace '\s+', ' '
    return $normalized.Trim()
}

function Get-MunicipalityFromAddress {
    param(
        [string]$Address,
        [string]$FallbackMunicipality = ""
    )

    if (-not [string]::IsNullOrWhiteSpace($Address)) {
        $normalized = [System.Net.WebUtility]::HtmlDecode($Address)
        $normalized = ($normalized -replace '\s+', ' ').Trim()
        $match = [regex]::Match($normalized, '(?:北海道|東京都|京都府|大阪府|.{2,4}県)?(?<municipality>[^0-9\s,、]{1,20}?(?:市|区|町|村))')
        if ($match.Success) {
            return $match.Groups['municipality'].Value.Trim()
        }
    }

    return ([string]$FallbackMunicipality).Trim()
}

function Split-IndustryText {
    param([string]$IndustryText)

    $industry1 = ""
    $industry2 = ""

    if ([string]::IsNullOrWhiteSpace($IndustryText)) {
        return [pscustomobject]@{
            industry1 = ""
            industry2 = ""
        }
    }

    $normalized = [System.Net.WebUtility]::HtmlDecode($IndustryText)
    $normalized = ($normalized -replace '\s+', ' ').Trim()
    $parts = @(
        $normalized -split '\s*(?:／|/|、|，|,|・|及び| and )\s*'
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    if ($parts.Count -ge 1) {
        $industry1 = $parts[0].Trim()
    }
    if ($parts.Count -ge 2) {
        $industry2 = $parts[1].Trim()
    }

    return [pscustomobject]@{
        industry1 = $industry1
        industry2 = $industry2
    }
}

function Get-SearchCompanyName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return ""
    }

    $normalized = $Name.Trim()
    $normalized = $normalized -replace '（株）|\(株\)|㈱|㍿', '株式会社'
    $normalized = $normalized -replace '（有）|\(有\)|㈲', '有限会社'
    $normalized = $normalized -replace '（同）|\(同\)', '合同会社'
    $normalized = $normalized -replace '（資）|\(資\)', '合資会社'
    $normalized = $normalized -replace '（名）|\(名\)', '合名会社'
    $normalized = $normalized -replace '（合）|\(合\)', '合同会社'
    $normalized = $normalized -replace '\s+', ' '
    return $normalized.Trim()
}

function Get-DefaultHttpHeaders {
    return @{
        "User-Agent"      = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36"
        "Accept-Language" = "ja,en-US;q=0.9,en;q=0.8"
        "Cache-Control"   = "no-cache"
    }
}

function Get-CompanySearchNameVariants {
    param([string]$Name)

    $baseName = Get-SearchCompanyName -Name $Name
    if ([string]::IsNullOrWhiteSpace($baseName)) {
        return @()
    }

    $variants = New-Object System.Collections.Generic.List[string]
    $variants.Add($baseName)

    $forms = @("株式会社", "有限会社", "合同会社", "合資会社", "合名会社")
    foreach ($form in $forms) {
        if ($baseName -match ("^{0}(.+)$" -f [regex]::Escape($form))) {
            $body = $matches[1].Trim()
            if (-not [string]::IsNullOrWhiteSpace($body)) {
                $variants.Add(("{0}{1}" -f $body, $form).Trim())
            }
        }
        elseif ($baseName -match ("^(.+?){0}$" -f [regex]::Escape($form))) {
            $body = $matches[1].Trim()
            if (-not [string]::IsNullOrWhiteSpace($body)) {
                $variants.Add(("{0}{1}" -f $form, $body).Trim())
            }
        }
    }

    $seen = @{}
    $results = New-Object System.Collections.Generic.List[string]
    foreach ($variant in $variants) {
        $key = Normalize-CompanyName -Name $variant
        if ([string]::IsNullOrWhiteSpace($key) -or $seen.ContainsKey($key)) {
            continue
        }

        $seen[$key] = $true
        $results.Add($variant)
    }

    return $results.ToArray()
}

function Get-WebsiteSearchQueries {
    param(
        [string]$CompanyName,
        [string]$Municipality,
        [string]$PersonName
    )

    $queries = New-Object System.Collections.Generic.List[string]
    foreach ($variant in @(Get-CompanySearchNameVariants -Name $CompanyName)) {
        if ([string]::IsNullOrWhiteSpace($Municipality)) {
            $queries.Add(('"{0}"' -f $variant))
            $queries.Add($variant)
            if (-not [string]::IsNullOrWhiteSpace($PersonName)) {
                $queries.Add(('"{0}" "{1}"' -f $variant, $PersonName))
            }
            continue
        }

        $queries.Add(('"{0}" {1}' -f $variant, $Municipality))
        $queries.Add(('{0} {1}' -f $variant, $Municipality))
        if (-not [string]::IsNullOrWhiteSpace($PersonName)) {
            $queries.Add(('"{0}" "{1}" {2}' -f $variant, $PersonName, $Municipality))
        }
    }

    $seen = @{}
    $results = New-Object System.Collections.Generic.List[string]
    foreach ($query in $queries) {
        $key = ($query -replace '\s+', ' ').Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($key) -or $seen.ContainsKey($key)) {
            continue
        }

        $seen[$key] = $true
        $results.Add(($query -replace '\s+', ' ').Trim())
    }

    return ($results | Select-Object -First 3)
}

function Test-DuplicateCandidate {
    param(
        [pscustomobject]$Left,
        [pscustomobject]$Right
    )

    if ($null -eq $Left -or $null -eq $Right) {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($Left.municipality) -or [string]::IsNullOrWhiteSpace($Right.municipality)) {
        return $false
    }

    if ($Left.municipality.Trim() -ne $Right.municipality.Trim()) {
        return $false
    }

    $leftName = Normalize-CompanyName -Name $Left.company_name
    $rightName = Normalize-CompanyName -Name $Right.company_name
    if ([string]::IsNullOrWhiteSpace($leftName) -or $leftName -ne $rightName) {
        return $false
    }

    $phoneMatch = -not [string]::IsNullOrWhiteSpace($Left.phone) -and -not [string]::IsNullOrWhiteSpace($Right.phone) -and $Left.phone.Trim() -eq $Right.phone.Trim()
    $addressMatch = -not [string]::IsNullOrWhiteSpace($Left.address) -and -not [string]::IsNullOrWhiteSpace($Right.address) -and $Left.address.Trim() -eq $Right.address.Trim()

    return ($phoneMatch -or $addressMatch)
}

function Get-CandidateStrength {
    param([pscustomobject]$Row)

    $score = 0
    foreach ($field in @("address", "phone", "website", "contact_form_url", "detail_source_url")) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Row.$field)) {
            $score += 1
        }
    }

    if ([double]$Row.industry_fit -gt 0) { $score += 1 }
    if ([double]$Row.local_focus -gt 0) { $score += 1 }
    if ([double]$Row.network_affinity -gt 0) { $score += 1 }
    if ([double]$Row.contactability -gt 0) { $score += 1 }
    if ([string]$Row.match_status -eq "exact") { $score += 2 }

    return $score
}

function Get-PreferredCandidate {
    param(
        [pscustomobject]$Left,
        [pscustomobject]$Right
    )

    if ($null -eq $Left) { return $Right }
    if ($null -eq $Right) { return $Left }

    $leftStrength = Get-CandidateStrength -Row $Left
    $rightStrength = Get-CandidateStrength -Row $Right

    if ($rightStrength -gt $leftStrength) {
        return $Right
    }

    return $Left
}

function Merge-UniqueSummary {
    param(
        [string]$Existing,
        [string]$Additional
    )

    $values = New-Object System.Collections.Generic.List[string]
    foreach ($raw in @($Existing, $Additional)) {
        if ([string]::IsNullOrWhiteSpace($raw)) {
            continue
        }

        foreach ($part in ($raw -split "\s\|\s")) {
            $trimmed = $part.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmed) -and -not $values.Contains($trimmed)) {
                $values.Add($trimmed)
            }
        }
    }

    return ($values -join " | ")
}

function Merge-CandidatePair {
    param(
        [pscustomobject]$Primary,
        [pscustomobject]$Secondary
    )

    $representative = Get-PreferredCandidate -Left $Primary -Right $Secondary
    $other = $Primary
    if ($representative -eq $Primary) {
        $other = $Secondary
    }
    else {
        $other = $Primary
    }

    $mergedIndustryFit = [math]::Max([double]$Primary.industry_fit, [double]$Secondary.industry_fit)
    $mergedLocalFocus = [math]::Max([double]$Primary.local_focus, [double]$Secondary.local_focus)
    $mergedNetworkAffinity = [math]::Max([double]$Primary.network_affinity, [double]$Secondary.network_affinity)
    $mergedContactability = [math]::Max([double]$Primary.contactability, [double]$Secondary.contactability)

    [pscustomobject]@{
        company_name      = $representative.company_name
        municipality      = $representative.municipality
        address           = $(if (-not [string]::IsNullOrWhiteSpace($representative.address)) { $representative.address } else { $other.address })
        phone             = $(if (-not [string]::IsNullOrWhiteSpace($representative.phone)) { $representative.phone } else { $other.phone })
        website           = $(if (-not [string]::IsNullOrWhiteSpace($representative.website)) { $representative.website } else { $other.website })
        contact_form_url  = $(if (-not [string]::IsNullOrWhiteSpace($representative.contact_form_url)) { $representative.contact_form_url } else { $other.contact_form_url })
        source_org        = $representative.source_org
        source_url        = $representative.source_url
        detail_source_url = $(if (-not [string]::IsNullOrWhiteSpace($representative.detail_source_url)) { $representative.detail_source_url } else { $other.detail_source_url })
        industry_fit      = $mergedIndustryFit
        local_focus       = $mergedLocalFocus
        network_affinity  = $mergedNetworkAffinity
        contactability    = $mergedContactability
        match_status      = $(if ($Primary.match_status -eq "exact" -or $Secondary.match_status -eq "exact") { "exact" } elseif ($Primary.match_status -eq "ambiguous" -or $Secondary.match_status -eq "ambiguous") { "ambiguous" } else { "missing" })
        source_count      = ([int]$Primary.source_count + [int]$Secondary.source_count)
        source_summary    = $(Merge-UniqueSummary -Existing $Primary.source_summary -Additional $Secondary.source_summary)
    }
}

function Merge-CandidateRows {
    param([System.Collections.IEnumerable]$Rows)

    $mergedRows = New-Object System.Collections.Generic.List[object]

    foreach ($row in $Rows) {
        $matchedIndex = -1
        for ($i = 0; $i -lt $mergedRows.Count; $i++) {
            if (Test-DuplicateCandidate -Left $mergedRows[$i] -Right $row) {
                $matchedIndex = $i
                break
            }
        }

        if ($matchedIndex -ge 0) {
            $mergedRows[$matchedIndex] = Merge-CandidatePair -Primary $mergedRows[$matchedIndex] -Secondary $row
        }
        else {
            $mergedRows.Add($row)
        }
    }

    return $mergedRows
}

function Merge-DetailRows {
    param([System.Collections.IEnumerable]$Rows)

    $rowList = @($Rows)
    if ($rowList.Count -eq 0) {
        return $null
    }

    $getDetailStrength = {
        param([pscustomobject]$Row)
        $score = 0
        foreach ($field in @("address", "phone", "website", "contact_form_url", "detail_source_url")) {
            if (-not [string]::IsNullOrWhiteSpace([string]$Row.$field)) {
                $score += 1
            }
        }
        return $score
    }

    $merged = $rowList[0]
    for ($i = 1; $i -lt $rowList.Count; $i++) {
        $current = $rowList[$i]
        if (-not (Test-DuplicateCandidate -Left $merged -Right $current)) {
            return $null
        }

        $preferred = $merged
        $other = $current
        if ((& $getDetailStrength $current) -gt (& $getDetailStrength $merged)) {
            $preferred = $current
            $other = $merged
        }

        $merged = [pscustomobject]@{
            company_name      = $preferred.company_name
            municipality      = $preferred.municipality
            address           = $(if (-not [string]::IsNullOrWhiteSpace($preferred.address)) { $preferred.address } else { $other.address })
            phone             = $(if (-not [string]::IsNullOrWhiteSpace($preferred.phone)) { $preferred.phone } else { $other.phone })
            website           = $(if (-not [string]::IsNullOrWhiteSpace($preferred.website)) { $preferred.website } else { $other.website })
            contact_form_url  = $(if (-not [string]::IsNullOrWhiteSpace($preferred.contact_form_url)) { $preferred.contact_form_url } else { $other.contact_form_url })
            detail_source_url = $(if (-not [string]::IsNullOrWhiteSpace($preferred.detail_source_url)) { $preferred.detail_source_url } else { $other.detail_source_url })
            industry_fit      = [math]::Max([double]$merged.industry_fit, [double]$current.industry_fit)
            local_focus       = [math]::Max([double]$merged.local_focus, [double]$current.local_focus)
            network_affinity  = [math]::Max([double]$merged.network_affinity, [double]$current.network_affinity)
            contactability    = [math]::Max([double]$merged.contactability, [double]$current.contactability)
        }
    }

    return $merged
}

function Invoke-ResolveAreas {
    param(
        [string]$AreasFile,
        [string]$ContractedFile,
        [string]$OutputFile,
        [int]$MinimumPopulation,
        [int]$MaximumPopulation,
        [string]$LogFile
    )

    $areas = Import-Csv -Path $AreasFile
    $contracted = Import-Csv -Path $ContractedFile
    $contractedSet = @{}
    foreach ($row in $contracted) {
        $contractedSet[$row.municipality] = $true
    }

    $results = @(foreach ($area in $areas) {
        $population = [int]$area.population
        $selected = $true
        $reason = ""

        if ($population -lt $MinimumPopulation -or $population -gt $MaximumPopulation) {
            $selected = $false
            $reason = "population_out_of_range"
        }
        elseif ($contractedSet.ContainsKey($area.municipality)) {
            $selected = $false
            $reason = "contracted_area"
        }

        [pscustomobject]@{
            municipality    = $area.municipality
            population      = $population
            selected        = $selected.ToString().ToLowerInvariant()
            excluded_reason = $reason
        }
    })

    Write-CsvBom -Rows $results -Path $OutputFile
    $selectedCount = @($results | Where-Object { $_.selected -eq "true" }).Count
    Write-LogEntry -Level "info" -Message "resolve-areas completed: selected=$selectedCount total=$($results.Count)" -Path $LogFile
}

function Get-UsableStatus {
    param(
        [string]$CompanyName,
        [string]$Address,
        [string]$Phone,
        [string]$Website,
        [string]$MatchStatus
    )

    $reasons = New-Object System.Collections.Generic.List[string]

    if ([string]::IsNullOrWhiteSpace($CompanyName)) {
        $reasons.Add("missing company_name")
    }
    if ([string]::IsNullOrWhiteSpace($Address)) {
        $reasons.Add("missing address")
    }
    if ([string]::IsNullOrWhiteSpace($Phone) -and [string]::IsNullOrWhiteSpace($Website)) {
        $reasons.Add("missing phone_or_website")
    }
    if ($MatchStatus -eq "ambiguous") {
        $reasons.Add("ambiguous company match")
    }
    elseif ($MatchStatus -eq "missing") {
        $reasons.Add("detail not found")
    }

    if ($reasons.Count -eq 0) {
        return @{
            IsUsable = "true"
            Reason   = "usable criteria met"
        }
    }

    return @{
        IsUsable = "false"
        Reason   = ($reasons -join "; ")
    }
}

function Get-ScoreResult {
    param(
        [pscustomobject]$Detail,
        [string]$MatchStatus,
        [hashtable]$ScoringConfig
    )

    $weights = $ScoringConfig["weights"]
    $confidenceConfig = $ScoringConfig["confidence"]
    $rankConfig = $ScoringConfig["ranks"]

    if ($MatchStatus -eq "ambiguous") {
        return @{
            Score      = 0
            Rank       = "C"
            Reason     = "Ambiguous company match"
            Confidence = "Low"
        }
    }

    if ($null -eq $Detail) {
        return @{
            Score      = 0
            Rank       = "C"
            Reason     = "Insufficient supporting data"
            Confidence = "Low"
        }
    }

    $score = 0.0
    $reasonParts = New-Object System.Collections.Generic.List[string]
    $confidence = [double]$confidenceConfig["base"]

    foreach ($signalKey in @("industry_fit", "local_focus", "network_affinity", "contactability")) {
        $signalValue = 0.0
        if (-not [string]::IsNullOrWhiteSpace($Detail.$signalKey)) {
            $signalValue = [double]$Detail.$signalKey
        }
        $score += $signalValue * [double]$weights[$signalKey]
    }

    if ([double]$Detail.industry_fit -gt 0) { $reasonParts.Add("Industry fit") }
    if ([double]$Detail.local_focus -gt 0) { $reasonParts.Add("Local focus") }
    if ([double]$Detail.network_affinity -gt 0) { $reasonParts.Add("Community network signal") }
    if ([double]$Detail.contactability -gt 0) { $reasonParts.Add("Reachable contact path") }

    if ([string]::IsNullOrWhiteSpace($Detail.address)) {
        $confidence -= [double]$confidenceConfig["missing_address_penalty"]
    }
    if ([string]::IsNullOrWhiteSpace($Detail.phone) -and [string]::IsNullOrWhiteSpace($Detail.website)) {
        $confidence -= [double]$confidenceConfig["missing_contact_penalty"]
    }

    if ($confidence -lt 0) {
        $confidence = 0
    }

    $finalScore = [math]::Round($score, 0)
    $rank = Get-Rank -Score $finalScore -RankThresholds $rankConfig
    $reason = Join-ReasonParts -Values $reasonParts.ToArray()
    if ([string]::IsNullOrWhiteSpace($reason)) {
        $reason = "Insufficient supporting data"
    }

    return @{
        Score      = $finalScore
        Rank       = $rank
        Reason     = $reason
        Confidence = Get-ConfidenceLabel -Confidence $confidence
    }
}

function Invoke-BuildCompanyMaster {
    param(
        [System.Collections.IEnumerable]$MemberRows,
        [System.Collections.IEnumerable]$DetailRows,
        [hashtable]$ScoringConfig,
        [string]$LogFile
    )

    $candidateRows = New-Object System.Collections.Generic.List[object]

    foreach ($member in $MemberRows) {
        $exactMatches = @($DetailRows | Where-Object {
            $_.company_name -eq $member.company_name -and $_.municipality -eq $member.municipality
        })
        $sameNameMatches = @($DetailRows | Where-Object { $_.company_name -eq $member.company_name })

        $matchStatus = "missing"
        $detail = $null

        if ($exactMatches.Count -eq 1) {
            $detail = $exactMatches[0]
            $matchStatus = "exact"
        }
        elseif ($exactMatches.Count -gt 1) {
            $mergedDetail = Merge-DetailRows -Rows $exactMatches
            if ($null -ne $mergedDetail) {
                $detail = $mergedDetail
                $matchStatus = "exact"
            }
            else {
                $matchStatus = "ambiguous"
                Write-LogEntry -Level "warning" -Message "Conflicting duplicate detail rows: $($member.company_name) in $($member.municipality)" -Path $LogFile
            }
        }
        elseif ($sameNameMatches.Count -gt 1) {
            $matchStatus = "ambiguous"
            Write-LogEntry -Level "warning" -Message "Ambiguous company match: $($member.company_name) in $($member.municipality)" -Path $LogFile
        }
        elseif ($sameNameMatches.Count -eq 1) {
            Write-LogEntry -Level "warning" -Message "Exact municipality match not found: $($member.company_name) in $($member.municipality)" -Path $LogFile
        }
        else {
            Write-LogEntry -Level "warning" -Message "Company detail not found: $($member.company_name) in $($member.municipality)" -Path $LogFile
        }

        $address = ""
        $phone = ""
        $website = ""
        $contactFormUrl = ""
        $detailSource = ""

        if ($matchStatus -eq "exact" -and $null -ne $detail) {
            $address = [string]$detail.address
            $phone = [string]$detail.phone
            $website = [string]$detail.website
            $contactFormUrl = [string]$detail.contact_form_url
            $detailSource = [string]$detail.detail_source_url
        }

        $sourceSummary = $member.source_org
        if (-not [string]::IsNullOrWhiteSpace($member.source_url)) {
            $sourceSummary = '{0} <{1}>' -f $member.source_org, $member.source_url
        }

        $candidateRows.Add([pscustomobject]@{
            company_name      = $member.company_name
            municipality      = $member.municipality
            address           = $address
            phone             = $phone
            website           = $website
            contact_form_url  = $contactFormUrl
            source_org        = $member.source_org
            source_url        = $member.source_url
            detail_source_url = $detailSource
            industry_fit      = $(if ($null -ne $detail) { [double]$detail.industry_fit } else { 0 })
            local_focus       = $(if ($null -ne $detail) { [double]$detail.local_focus } else { 0 })
            network_affinity  = $(if ($null -ne $detail) { [double]$detail.network_affinity } else { 0 })
            contactability    = $(if ($null -ne $detail) { [double]$detail.contactability } else { 0 })
            match_status      = $matchStatus
            source_count      = 1
            source_summary    = $sourceSummary
        })
    }

    $mergedCandidates = Merge-CandidateRows -Rows $candidateRows
    $outputRows = New-Object System.Collections.Generic.List[object]

    foreach ($candidate in $mergedCandidates) {
        $usable = Get-UsableStatus -CompanyName $candidate.company_name -Address $candidate.address -Phone $candidate.phone -Website $candidate.website -MatchStatus $candidate.match_status
        $score = Get-ScoreResult -Detail $candidate -MatchStatus $candidate.match_status -ScoringConfig $ScoringConfig

        $outputRows.Add([pscustomobject]@{
            company_name      = $candidate.company_name
            municipality      = $candidate.municipality
            address           = $candidate.address
            phone             = $candidate.phone
            website           = $candidate.website
            contact_form_url  = $candidate.contact_form_url
            source_org        = $candidate.source_org
            source_url        = $candidate.source_url
            source_count      = $candidate.source_count
            source_summary    = $candidate.source_summary
            detail_source_url = $candidate.detail_source_url
            industry_fit      = $candidate.industry_fit
            local_focus       = $candidate.local_focus
            network_affinity  = $candidate.network_affinity
            contactability    = $candidate.contactability
            is_usable         = $usable.IsUsable
            usable_reason     = $usable.Reason
            priority_score    = $score.Score
            priority_rank     = $score.Rank
            score_reason      = $score.Reason
            score_confidence  = $score.Confidence
        })
    }

    return $outputRows
}

function Invoke-BuildCompanyMasterCommand {
    param(
        [string]$ResolvedFile,
        [string]$MembersFile,
        [string]$DetailsFile,
        [string]$ScoringFile,
        [string]$OutputFile,
        [string]$LogFile
    )

    $resolved = Import-Csv -Path $ResolvedFile
    $selectedAreas = @($resolved | Where-Object { $_.selected -eq "true" } | ForEach-Object { $_.municipality })
    $selectedMap = @{}
    foreach ($municipality in $selectedAreas) {
        $selectedMap[$municipality] = $true
    }

    $members = @()
    if ((Test-Path $MembersFile) -and ((Get-Item $MembersFile).Length -gt 3)) {
        $members = @(Import-Csv -Path $MembersFile | Where-Object { $selectedMap.ContainsKey($_.municipality) })
    }

    $details = @()
    if ((Test-Path $DetailsFile) -and ((Get-Item $DetailsFile).Length -gt 3)) {
        $details = @(Import-Csv -Path $DetailsFile)
    }

    $scoring = Read-SimpleYaml -Path $ScoringFile

    $outputRows = @(Invoke-BuildCompanyMaster -MemberRows $members -DetailRows $details -ScoringConfig $scoring -LogFile $LogFile)
    Write-CsvBom -Rows $outputRows -Path $OutputFile
    Write-LogEntry -Level "info" -Message "build-company-master completed: output=$($outputRows.Count)" -Path $LogFile
}

function Get-RealDataPairs {
    param([string]$Directory)

    $memberFiles = Get-ChildItem -Path $Directory -Filter "*_member_companies.csv" -File
    $pairs = New-Object System.Collections.Generic.List[object]

    foreach ($memberFile in $memberFiles) {
        $prefix = $memberFile.BaseName -replace '_member_companies$', ''
        $detailPath = Join-Path $Directory ("{0}_company_details.csv" -f $prefix)
        if (-not (Test-Path $detailPath)) {
            continue
        }

        $pairs.Add([pscustomobject]@{
            Prefix      = $prefix
            MemberPath  = $memberFile.FullName
            DetailPath  = $detailPath
        })
    }

    return $pairs
}

function Get-SelectedMunicipalityMap {
    param([string]$ResolvedFile)

    if ([string]::IsNullOrWhiteSpace($ResolvedFile) -or -not (Test-Path $ResolvedFile)) {
        return $null
    }

    $resolvedRows = @(Import-Csv -Path $ResolvedFile)
    $selectedMap = @{}
    foreach ($row in $resolvedRows | Where-Object { $_.selected -eq "true" }) {
        $selectedMap[$row.municipality] = $true
    }

    return $selectedMap
}

function Invoke-BuildRealSalesList {
    param(
        [string]$RealDirectory,
        [string]$ResolvedFilterFile,
        [string]$ScoringFile,
        [string]$AllOutputFile,
        [string]$UsableOutputFile,
        [string]$ReportOutputFile,
        [string]$LogFile
    )

    $pairs = @(Get-RealDataPairs -Directory $RealDirectory)
    if ($pairs.Count -eq 0) {
        throw "No real-data file pairs were found under: $RealDirectory"
    }

    $selectedMunicipalities = Get-SelectedMunicipalityMap -ResolvedFile $ResolvedFilterFile
    $allMembers = New-Object System.Collections.Generic.List[object]
    $allDetails = New-Object System.Collections.Generic.List[object]

    foreach ($pair in $pairs) {
        foreach ($memberRow in @(Import-Csv -Path $pair.MemberPath)) {
            if ($null -ne $selectedMunicipalities -and -not $selectedMunicipalities.ContainsKey($memberRow.municipality)) {
                continue
            }
            $allMembers.Add($memberRow)
        }
        foreach ($detailRow in @(Import-Csv -Path $pair.DetailPath)) {
            if ($null -ne $selectedMunicipalities -and -not $selectedMunicipalities.ContainsKey($detailRow.municipality)) {
                continue
            }
            $allDetails.Add($detailRow)
        }
    }

    $scoring = Read-SimpleYaml -Path $ScoringFile
    $allRows = @(Invoke-BuildCompanyMaster -MemberRows $allMembers -DetailRows $allDetails -ScoringConfig $scoring -LogFile $LogFile |
        Sort-Object -Property @{ Expression = { [int]$_.priority_score }; Descending = $true }, municipality, company_name)

    $usableRows = @($allRows | Where-Object { $_.is_usable -eq "true" } | ForEach-Object {
            [pscustomobject]@{
                priority_rank     = $_.priority_rank
                priority_score    = $_.priority_score
                company_name      = $_.company_name
                municipality      = $_.municipality
                phone             = $_.phone
                website           = $_.website
                contact_form_url  = $_.contact_form_url
                address           = $_.address
                source_org        = $_.source_org
                score_reason      = $_.score_reason
                score_confidence  = $_.score_confidence
                detail_source_url = $_.detail_source_url
                source_count      = $_.source_count
                source_summary    = $_.source_summary
                industry_fit      = $_.industry_fit
                local_focus       = $_.local_focus
                network_affinity  = $_.network_affinity
                contactability    = $_.contactability
            }
        })
    $reportRows = @(
        foreach ($group in ($allRows | Group-Object municipality | Sort-Object Name)) {
            $rows = @($group.Group)
            [pscustomobject]@{
                municipality  = $group.Name
                total_count   = $rows.Count
                usable_count  = @($rows | Where-Object { $_.is_usable -eq "true" }).Count
                top_rank_count = @($rows | Where-Object { $_.priority_rank -eq "A" }).Count
                contact_form_count = @($rows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.contact_form_url) }).Count
            }
        }
    )

    Write-CsvBom -Rows $allRows -Path $AllOutputFile
    Write-CsvBom -Rows $usableRows -Path $UsableOutputFile
    Write-CsvBom -Rows $reportRows -Path $ReportOutputFile

    Write-LogEntry -Level "info" -Message "build-real-sales-list completed: total=$($allRows.Count) usable=$($usableRows.Count) municipalities=$($reportRows.Count)" -Path $LogFile
}

function Test-AddressMatchesMunicipality {
    param(
        [string]$Municipality,
        [string]$Address
    )

    if ([string]::IsNullOrWhiteSpace($Municipality) -or [string]::IsNullOrWhiteSpace($Address)) {
        return $false
    }

    return $Address.Contains($Municipality)
}

function Test-WebUsableCompanyNameQuality {
    param([string]$CompanyName)

    if ([string]::IsNullOrWhiteSpace($CompanyName)) {
        return $false
    }

    foreach ($pattern in @(
            '^TOP$',
            '^株式会社$',
            '^不動産$',
            '^【株式会社',
            '^Orico$',
            '^ロータリーの友$',
            '^中部電力パワーグリッドWebサイト$',
            '^通信・ICTサービス・ソリューション$',
            '^マネー信用の蔵！.*',
            '^アメニティーな社会の創造に役立つ$',
            '^成田ケーブル$',
            '銀行$',
            '^損保ジャパン$',
            '^明治安田$',
            '^公益財団法人',
            '神社$',
            '寺$',
            '観光協会$',
            'グループ$',
            '^道の駅$'
        )) {
        if ($CompanyName -match $pattern) {
            return $false
        }
    }

    return $true
}

function Test-WebUsableAddressQuality {
    param([string]$Address)

    if ([string]::IsNullOrWhiteSpace($Address)) {
        return $false
    }

    foreach ($pattern in @(
            'HOME',
            'CONTACT',
            'Instagram',
            'さらに読み込む',
            'ページの先頭',
            '愛知県全域',
            '信託契約代理業',
            '黒龍芝公園ビル',
            'フリーダイヤル',
            '代表$',
            '〒.*〒',
            '^\D?[\/ー・]\s*',
            '\[$',
            '^>\s*',
            '^可\s+',
            'ご相談ください',
            'の建設工事会社',
            'のコーティングなら',
            '会社.*会社',
            'お待ちしております'
        )) {
        if ($Address -match $pattern) {
            return $false
        }
    }

    return $true
}

function Invoke-BuildSalesListFromCompanyMaster {
    param(
        [string]$CompanyMasterFile,
        [string]$AllOutputFile,
        [string]$UsableOutputFile,
        [string]$ReportOutputFile,
        [string]$LogFile
    )

    $allRows = @(Import-Csv -Path $CompanyMasterFile | Sort-Object -Property @{ Expression = { [int]$_.priority_score }; Descending = $true }, municipality, company_name)
    $usableRows = @($allRows | Where-Object {
            $_.is_usable -eq "true" -and
            (Test-AddressMatchesMunicipality -Municipality $_.municipality -Address $_.address) -and
            (Test-WebUsableCompanyNameQuality -CompanyName $_.company_name) -and
            (Test-WebUsableAddressQuality -Address $_.address)
        } | ForEach-Object {
            [pscustomobject]@{
                priority_rank     = $_.priority_rank
                priority_score    = $_.priority_score
                company_name      = $_.company_name
                municipality      = $_.municipality
                phone             = $_.phone
                website           = $_.website
                contact_form_url  = $_.contact_form_url
                address           = $_.address
                source_org        = $_.source_org
                score_reason      = $_.score_reason
                score_confidence  = $_.score_confidence
                detail_source_url = $_.detail_source_url
                source_count      = $_.source_count
                source_summary    = $_.source_summary
                industry_fit      = $_.industry_fit
                local_focus       = $_.local_focus
                network_affinity  = $_.network_affinity
                contactability    = $_.contactability
                municipality_match = "true"
            }
        })
    $reportRows = @(
        foreach ($group in ($allRows | Group-Object municipality | Sort-Object Name)) {
            $rows = @($group.Group)
            $usableRowsForMunicipality = @($rows | Where-Object {
                    $_.is_usable -eq "true" -and
                    (Test-AddressMatchesMunicipality -Municipality $_.municipality -Address $_.address) -and
                    (Test-WebUsableCompanyNameQuality -CompanyName $_.company_name) -and
                    (Test-WebUsableAddressQuality -Address $_.address)
                })
            [pscustomobject]@{
                municipality      = $group.Name
                total_count       = $rows.Count
                usable_count      = $usableRowsForMunicipality.Count
                top_rank_count    = @($rows | Where-Object { $_.priority_rank -eq "A" }).Count
                contact_form_count = @($rows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.contact_form_url) }).Count
            }
        }
    )

    Write-CsvBom -Rows $allRows -Path $AllOutputFile
    Write-CsvBom -Rows $usableRows -Path $UsableOutputFile
    Write-CsvBom -Rows $reportRows -Path $ReportOutputFile

    Write-LogEntry -Level "info" -Message "build-sales-list-from-company-master completed: total=$($allRows.Count) usable=$($usableRows.Count) municipalities=$($reportRows.Count)" -Path $LogFile
}

function Invoke-RunRealPipeline {
    param(
        [string]$AreasFile,
        [string]$ContractedFile,
        [string]$ResolvedFile,
        [string]$RealDirectory,
        [string]$ScoringFile,
        [string]$AllOutputFile,
        [string]$UsableOutputFile,
        [string]$ReportOutputFile,
        [int]$MinimumPopulation,
        [int]$MaximumPopulation,
        [string]$LogFile
    )

    Invoke-ResolveAreas -AreasFile $AreasFile -ContractedFile $ContractedFile -OutputFile $ResolvedFile -MinimumPopulation $MinimumPopulation -MaximumPopulation $MaximumPopulation -LogFile $LogFile
    Invoke-BuildRealSalesList -RealDirectory $RealDirectory -ResolvedFilterFile $ResolvedFile -ScoringFile $ScoringFile -AllOutputFile $AllOutputFile -UsableOutputFile $UsableOutputFile -ReportOutputFile $ReportOutputFile -LogFile $LogFile
    Write-LogEntry -Level "info" -Message "run-real-pipeline completed" -Path $LogFile
}

function Invoke-BuildSourceWorkset {
    param(
        [string]$ResolvedFile,
        [string]$RegistryFile,
        [string]$OutputFile,
        [string]$LogFile
    )

    $selectedMunicipalities = Get-SelectedMunicipalityMap -ResolvedFile $ResolvedFile
    if ($null -eq $selectedMunicipalities -or $selectedMunicipalities.Count -eq 0) {
        throw "No selected municipalities were found in: $ResolvedFile"
    }

    $registryRows = @(Import-Csv -Path $RegistryFile)
    $outputRows = @(
        foreach ($row in $registryRows) {
            if ($selectedMunicipalities.ContainsKey($row.municipality)) {
                [pscustomobject]@{
                    municipality = $row.municipality
                    source_org   = $row.source_org
                    source_type  = $row.source_type
                    source_url   = $row.source_url
                    notes        = $row.notes
                }
            }
        }
    )

    Write-CsvBom -Rows $outputRows -Path $OutputFile
    Write-LogEntry -Level "info" -Message "build-source-workset completed: sources=$($outputRows.Count)" -Path $LogFile
}

function Resolve-AbsoluteUrl {
    param(
        [string]$BaseUrl,
        [string]$Href
    )

    if ([string]::IsNullOrWhiteSpace($Href)) {
        return ""
    }

    if ($Href.StartsWith("http://") -or $Href.StartsWith("https://")) {
        return $Href
    }

    if ($Href.StartsWith("//")) {
        $baseUri = [System.Uri]$BaseUrl
        return "{0}:{1}" -f $baseUri.Scheme, $Href
    }

    try {
        $absoluteUri = [System.Uri]::new([System.Uri]$BaseUrl, $Href)
        return $absoluteUri.AbsoluteUri
    }
    catch {
        return ""
    }
}

function Get-SourceTypeCandidate {
    param(
        [string]$Title,
        [string]$Url
    )

    $combined = ("{0} {1}" -f $Title, $Url)
    if ($combined -match 'ロータリー|rotary') {
        return "rotary_member_voice"
    }
    if ($combined -match '商工会議所青年部|yeg') {
        return "chamber_member_directory"
    }
    if ($combined -match '青年会議所|jc') {
        return "jc_member_list"
    }
    if ($combined -match 'ライオンズクラブ|lions') {
        return "lions_member_list"
    }
    if ($combined -match '倫理法人会') {
        return "ethics_member_list"
    }
    if ($combined -match '観光協会|観光コンベンション協会|物産協会') {
        return "tourism_member_list"
    }
    if ($combined -match '団体会員|協賛企業|賛助会員') {
        return "corporate_supporter_list"
    }
    if ($combined -match '商工会議所') {
        return "chamber_member_directory"
    }
    return "association_member_list"
}

function Get-SourceOrgCandidate {
    param([string]$Title)

    if ([string]::IsNullOrWhiteSpace($Title)) {
        return ""
    }

    foreach ($pattern in @(
            '(一般社団法人[^|｜\-–—»＞]+青年会議所)',
            '([^|｜\-–—»＞]+商工会議所青年部)',
            '([^|｜\-–—»＞]+青年会議所)',
            '([^|｜\-–—»＞]+商工会議所)',
            '([^|｜\-–—»＞]+ロータリークラブ)',
            '([^|｜\-–—»＞]+ライオンズクラブ)',
            '([^|｜\-–—»＞]+倫理法人会)',
            '([^|｜\-–—»＞]+物産協会)',
            '([^|｜\-–—»＞]+観光コンベンション協会)',
            '([^|｜\-–—»＞]+観光協会)'
        )) {
        $match = [regex]::Match($Title, $pattern)
        if ($match.Success) {
            return ($match.Groups[1].Value -replace '\s+', ' ').Trim()
        }
    }

    $value = $Title
    foreach ($separator in @('|', '｜', ' - ', ' – ', ' — ')) {
        if ($value.Contains($separator)) {
            $value = $value.Split($separator)[0]
            break
        }
    }

    $value = ($value -replace '\s+', ' ').Trim()
    return $value
}

function Get-SourceRegistrationPriority {
    param([pscustomobject]$Candidate)

    $priority = 0
    $url = [string]$Candidate.source_url
    $name = [string]$Candidate.source_org_candidate
    $query = [string]$Candidate.search_query

    if ($url -match '/members?/|/members?$|/member$|/member/|page_id=\d+') {
        $priority += 4
    }
    if ($url -match '/links?/|groupmembers|supporter|supporters') {
        $priority += 3
    }
    if ($url -match 'page_id=17|page_id=2219|page_id=2882') {
        $priority += 1
    }
    if ($name -match '会員一覧|会員紹介|役員表') {
        $priority -= 2
    }
    if ($name -match 'ロータリークラブ|商工会議所|青年会議所|商工会議所青年部|ライオンズクラブ|倫理法人会|観光協会|観光コンベンション協会') {
        $priority += 2
    }
    if ($query -match '観光協会|観光コンベンション協会' -and $url -match 'miyakonojo|miyakonojyo') {
        $priority += 2
    }
    if ($url -match 'mapion|houjin\.info|alarmbox|city\.miyakonojo|pref\.miyazaki|kanko-miyazaki\.jp') {
        $priority -= 6
    }

    return $priority
}

function Test-RegistryReadySourceCandidate {
    param([pscustomobject]$Candidate)

    $url = [string]$Candidate.source_url
    $name = [string]$Candidate.source_org_candidate

    if ([string]::IsNullOrWhiteSpace($url)) {
        return $false
    }

    foreach ($pattern in @(
            'mapion',
            'houjin\.info',
            'alarmbox',
            'city\.miyakonojo',
            'pref\.miyazaki',
            'kanko-miyazaki\.jp'
        )) {
        if ($url -match $pattern) {
            return $false
        }
    }

    foreach ($blockedName in @(
            'NPO法人を紹介',
            '協同組合を紹介',
            '賛助会員',
            '会員一覧',
            '会員紹介'
        )) {
        if ($name -like "*$blockedName*") {
            return $false
        }
    }

    return $true
}

function Get-SourceCandidateScore {
    param(
        [string]$Municipality,
        [string]$Title,
        [string]$Url,
        [string]$Snippet
    )

    $combined = ("{0} {1} {2}" -f $Title, $Url, $Snippet)
    $score = 0
    $reasons = New-Object System.Collections.Generic.List[string]

    if ($combined -match [regex]::Escape($Municipality)) {
        $score += 5
        $reasons.Add("municipality match")
    }
    if ($combined -match '商工会議所青年部|yeg') {
        $score += 5
        $reasons.Add("yeg/chamber youth")
    }
    elseif ($combined -match '商工会議所') {
        $score += 4
        $reasons.Add("chamber")
    }
    if ($combined -match '青年会議所|jc') {
        $score += 4
        $reasons.Add("jc")
    }
    if ($combined -match 'ロータリー|rotary') {
        $score += 4
        $reasons.Add("rotary")
    }
    if ($combined -match 'ライオンズクラブ|lions') {
        $score += 4
        $reasons.Add("lions")
    }
    if ($combined -match '倫理法人会') {
        $score += 4
        $reasons.Add("ethics")
    }
    if ($combined -match '観光協会|観光コンベンション協会|物産協会') {
        $score += 4
        $reasons.Add("tourism association")
    }
    if ($combined -match '会員|member|members|名簿|紹介|voice|profile|メンバー') {
        $score += 4
        $reasons.Add("member page signal")
    }
    if ($combined -match '会員事業者|団体会員|協賛企業|賛助会員|会員企業') {
        $score += 4
        $reasons.Add("corporate listing signal")
    }
    if ($Url -match '/members?/|/members?$|page_id=|/kaiin|/meibo') {
        $score += 3
        $reasons.Add("member url pattern")
    }
    if ($combined -match '会員紹介|会員一覧|役員表') {
        $score += 2
        $reasons.Add("explicit member listing")
    }
    if ($combined -match '大会|議員|退会|コード一覧|方法を解説|シニア・クラブ') {
        $score -= 5
        $reasons.Add("non-registry context")
    }
    if ($Url -match 'yeg\.jp|jcci\.or\.jp|kachimai\.jp|/entry/ct/|article/index') {
        $score -= 4
        $reasons.Add("noisy or national/article source")
    }
    if ($Url -match '/entry/p-\d+|/entry/ct/') {
        $score -= 2
        $reasons.Add("entry page fragment")
    }

    return [pscustomobject]@{
        Score  = $score
        Reason = ($reasons -join ", ")
    }
}

function Resolve-SearchResultUrl {
    param([string]$Href)

    if ([string]::IsNullOrWhiteSpace($Href)) {
        return ""
    }

    $value = $Href
    if ($value.StartsWith("//")) {
        $value = "https:$value"
    }

    if ($value -match 'uddg=([^&]+)') {
        return [System.Uri]::UnescapeDataString($matches[1])
    }

    $decodedHref = [System.Net.WebUtility]::HtmlDecode($value)
    if ($decodedHref -match 'google\.[^/]+/url\?.*?[?&]q=([^&]+)') {
        return [System.Uri]::UnescapeDataString($matches[1])
    }

    if ($decodedHref -match 'bing\.com/ck/a' -and $decodedHref -match '[?&]u=([^&]+)') {
        $bingValue = [System.Uri]::UnescapeDataString($matches[1])
        if ($bingValue.StartsWith('a1')) {
            $base64 = $bingValue.Substring(2)
            $padding = (4 - ($base64.Length % 4)) % 4
            if ($padding -gt 0) {
                $base64 = $base64 + ('=' * $padding)
            }
            try {
                $bytes = [System.Convert]::FromBase64String($base64)
                $resolved = [System.Text.Encoding]::UTF8.GetString($bytes)
                if ($resolved.StartsWith("http://") -or $resolved.StartsWith("https://")) {
                    return $resolved
                }
            }
            catch {
            }
        }
    }

    if ($decodedHref -match 'bing\.com/ck/a|duckduckgo\.com|bing\.com/(search|travel|images|videos|news|maps)|google\.[^/]+/(search|imgres)') {
        return ""
    }

    if ($value.StartsWith("http://") -or $value.StartsWith("https://")) {
        return $value
    }

    return ""
}

function Get-SearchResultCandidateLinks {
    param([object]$Response)

    $results = @()
    $seen = @{}

    foreach ($link in @($Response.Links)) {
        $hrefProperty = $link.PSObject.Properties["href"]
        if ($null -eq $hrefProperty) {
            continue
        }

        $href = [string]$hrefProperty.Value
        if ([string]::IsNullOrWhiteSpace($href) -or $seen.ContainsKey($href)) {
            continue
        }

        $seen[$href] = $true
        $text = ""
        $innerTextProperty = $link.PSObject.Properties["innerText"]
        if ($null -ne $innerTextProperty) {
            $text = [string]$innerTextProperty.Value
        }

        $results += [pscustomobject]@{
            href = $href
            text = $text
        }
    }

    $content = [string]$Response.Content
    if (-not [string]::IsNullOrWhiteSpace($content)) {
        $patterns = @(
            'https://www\.bing\.com/ck/a\?[^"''<\s]+',
            '(?:https?://[^"''<\s]+)?/l/\?kh=-1&amp;uddg=[^"''<\s]+',
            '(?:https?://[^"''<\s]+)?/l/\?uddg=[^"''<\s]+'
        )

        foreach ($pattern in $patterns) {
            foreach ($match in [regex]::Matches($content, $pattern)) {
                $href = [System.Net.WebUtility]::HtmlDecode($match.Value)
                if ([string]::IsNullOrWhiteSpace($href) -or $seen.ContainsKey($href)) {
                    continue
                }
                $seen[$href] = $true
                $results += [pscustomobject]@{
                    href = $href
                    text = ""
                }
            }
        }
    }

    return $results
}

function Get-BingOrganicSearchResults {
    param([string]$Html)

    if ([string]::IsNullOrWhiteSpace($Html)) {
        return @()
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($match in [regex]::Matches($Html, '(?is)<li[^>]*class="[^"]*\bb_algo\b[^"]*"[^>]*>(.*?)</li>')) {
        $block = [string]$match.Groups[1].Value
        $anchorMatch = [regex]::Match($block, '(?is)<h2[^>]*>\s*<a[^>]+href="([^"]+)"[^>]*>(.*?)</a>')
        if (-not $anchorMatch.Success) {
            continue
        }

        $href = [System.Net.WebUtility]::HtmlDecode($anchorMatch.Groups[1].Value)
        $title = [System.Net.WebUtility]::HtmlDecode(($anchorMatch.Groups[2].Value -replace '<[^>]+>', ' '))
        $snippet = ""
        $snippetMatch = [regex]::Match($block, '(?is)<p[^>]*>(.*?)</p>')
        if ($snippetMatch.Success) {
            $snippet = [System.Net.WebUtility]::HtmlDecode(($snippetMatch.Groups[1].Value -replace '<[^>]+>', ' '))
        }

        $results.Add([pscustomobject]@{
            href    = ($href -replace '\s+', ' ').Trim()
            title   = ($title -replace '\s+', ' ').Trim()
            snippet = ($snippet -replace '\s+', ' ').Trim()
        })
    }

    return $results.ToArray()
}

function Get-DuckDuckGoOrganicSearchResults {
    param([string]$Html)

    if ([string]::IsNullOrWhiteSpace($Html)) {
        return @()
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($anchorMatch in [regex]::Matches($Html, '(?is)<a[^>]*class="[^"]*\bresult__a\b[^"]*"[^>]*href="([^"]+)"[^>]*>(.*?)</a>')) {
        $href = [System.Net.WebUtility]::HtmlDecode($anchorMatch.Groups[1].Value)
        $title = [System.Net.WebUtility]::HtmlDecode(($anchorMatch.Groups[2].Value -replace '<[^>]+>', ' '))
        $snippet = ""

        $snippetSourceHtml = ""
        $remainingLength = [Math]::Min(2500, $Html.Length - $anchorMatch.Index)
        if ($remainingLength -gt 0) {
            $remainingHtml = $Html.Substring($anchorMatch.Index, $remainingLength)
            $snippetMatch = [regex]::Match($remainingHtml, '(?is)<a[^>]*class="[^"]*\bresult__snippet\b[^"]*"[^>]*>(.*?)</a>|<div[^>]*class="[^"]*\bresult__snippet\b[^"]*"[^>]*>(.*?)</div>')
            if ($snippetMatch.Success) {
                $snippetSourceHtml = if ($snippetMatch.Groups[1].Success) { $snippetMatch.Groups[1].Value } else { $snippetMatch.Groups[2].Value }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($snippetSourceHtml)) {
            $snippet = [System.Net.WebUtility]::HtmlDecode(($snippetSourceHtml -replace '<[^>]+>', ' '))
        }

        $results.Add([pscustomobject]@{
            href    = ($href -replace '\s+', ' ').Trim()
            title   = ($title -replace '\s+', ' ').Trim()
            snippet = ($snippet -replace '\s+', ' ').Trim()
        })
    }

    return $results.ToArray()
}

function Get-YahooJapanOrganicSearchResults {
    param([string]$Html)

    if ([string]::IsNullOrWhiteSpace($Html)) {
        return @()
    }

    $sectionMatch = [regex]::Match($Html, '(?is)<div[^>]*id="web"[^>]*>.*?<ol>(.*?)</ol>')
    if (-not $sectionMatch.Success) {
        return @()
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($match in [regex]::Matches($sectionMatch.Groups[1].Value, '(?is)<li>\s*<a[^>]+href="([^"]+)"[^>]*>(.*?)</a>\s*<div>(.*?)</div>\s*<em>(.*?)</em>')) {
        $href = [System.Net.WebUtility]::HtmlDecode($match.Groups[1].Value)
        $title = [System.Net.WebUtility]::HtmlDecode(($match.Groups[2].Value -replace '<[^>]+>', ' '))
        $snippet = [System.Net.WebUtility]::HtmlDecode(($match.Groups[3].Value -replace '<[^>]+>', ' '))

        $results.Add([pscustomobject]@{
            href    = ($href -replace '\s+', ' ').Trim()
            title   = ($title -replace '\s+', ' ').Trim()
            snippet = ($snippet -replace '\s+', ' ').Trim()
        })
    }

    return $results.ToArray()
}

function Invoke-SearchResultFetch {
    param(
        [string]$Engine,
        [string]$Query,
        [string]$LogFile
    )

    $searchUrl = ""
    switch ($Engine) {
        "yahoojapan" { $searchUrl = "https://search.yahoo.co.jp/search?p={0}" -f [System.Uri]::EscapeDataString($Query) }
        "bing" { $searchUrl = "https://www.bing.com/search?q={0}" -f [System.Uri]::EscapeDataString($Query) }
        "duckduckgo" { $searchUrl = "https://html.duckduckgo.com/html/?q={0}" -f [System.Uri]::EscapeDataString($Query) }
        default { throw "Unsupported search engine: $Engine" }
    }

    try {
        $response = Invoke-WebRequest -Uri $searchUrl -UseBasicParsing -TimeoutSec 8
    }
    catch {
        Write-LogEntry -Level "warning" -Message "Failed to search website candidates: engine=$Engine query=$Query" -Path $LogFile
        return @()
    }

    $results = switch ($Engine) {
        "yahoojapan" { @(Get-YahooJapanOrganicSearchResults -Html ([string]$response.Content)) }
        "bing" { @(Get-BingOrganicSearchResults -Html ([string]$response.Content)) }
        "duckduckgo" { @(Get-DuckDuckGoOrganicSearchResults -Html ([string]$response.Content)) }
    }

    foreach ($result in $results) {
        $result | Add-Member -NotePropertyName "engine" -NotePropertyValue $Engine -Force
        $result | Add-Member -NotePropertyName "search_query" -NotePropertyValue $Query -Force
    }

    return $results
}

function Invoke-DiscoverSourceCandidates {
    param(
        [string]$Municipality,
        [string]$OutputFile,
        [string]$LogFile
    )

    if ([string]::IsNullOrWhiteSpace($Municipality)) {
        throw "MunicipalityName is required for discover-source-candidates."
    }

    $queries = @(
        "$Municipality 商工会議所 会員",
        "$Municipality 商工会議所青年部 会員",
        "$Municipality 青年会議所 会員",
        "$Municipality ロータリークラブ 会員",
        "$Municipality ライオンズクラブ 会員",
        "$Municipality 倫理法人会 会員",
        "$Municipality 観光協会 会員事業者",
        "$Municipality 観光コンベンション協会 会員",
        "$Municipality 団体会員",
        "$Municipality 協賛企業"
    )

    $candidateRows = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    foreach ($query in $queries) {
        $searchUrls = @(
            "https://www.bing.com/search?q={0}" -f [System.Uri]::EscapeDataString($query),
            "https://html.duckduckgo.com/html/?q={0}" -f [System.Uri]::EscapeDataString($query)
        )

        foreach ($searchUrl in $searchUrls) {
            try {
                $response = Invoke-WebRequest -Uri $searchUrl -UseBasicParsing -TimeoutSec 8
            }
            catch {
                Write-LogEntry -Level "warning" -Message "Failed to discover sources for query: $query url=$searchUrl" -Path $LogFile
                continue
            }

            foreach ($link in @(Get-SearchResultCandidateLinks -Response $response)) {
                $url = Resolve-SearchResultUrl -Href ([string]$link.href)
                if ([string]::IsNullOrWhiteSpace($url)) {
                    continue
                }

                if ($url -match 'facebook|instagram|wikipedia|tripadvisor|jalan|rakuten|newt\.net|hankyu-travel|asahi\.co\.jp|yeg\.jp|jcci\.or\.jp|kachimai\.jp/article|ameblo\.jp|city\.obihiro\.hokkaido\.jp|ideco-ipo-nisa\.com|jc-seniorclub\.jp|jcb\.co\.jp|bing\.com/(images|videos|news|maps|travel)|duckduckgo\.com') {
                    continue
                }

                $title = Get-WebPageTitle -Url $url -LogFile $LogFile
                $snippet = [string]$link.text

                $scoreResult = Get-SourceCandidateScore -Municipality $Municipality -Title $title -Url $url -Snippet $snippet
                if ($scoreResult.Score -lt 8) {
                    continue
                }

                if ($seen.ContainsKey($url)) {
                    continue
                }
                $seen[$url] = $true

                $candidateRows.Add([pscustomobject]@{
                    municipality          = $Municipality
                    source_org_candidate  = Get-SourceOrgCandidate -Title $title
                    source_type_candidate = Get-SourceTypeCandidate -Title $title -Url $url
                    source_url            = $url
                    search_query          = $query
                    score                 = $scoreResult.Score
                    reason                = $scoreResult.Reason
                })
            }
        }
    }

    $outputRows = @($candidateRows | Sort-Object -Property @{ Expression = { [int]$_.score }; Descending = $true }, source_org_candidate, source_url)
    if ($outputRows.Count -eq 0) {
        if ((Test-Path $OutputFile) -and ((Get-Item $OutputFile).Length -gt 3)) {
            Write-LogEntry -Level "warning" -Message "discover-source-candidates found 0 candidates and preserved existing file: $OutputFile" -Path $LogFile
            return
        }
    }
    Write-CsvBom -Rows $outputRows -Path $OutputFile
    Write-LogEntry -Level "info" -Message "discover-source-candidates completed: municipality=$Municipality candidates=$($outputRows.Count)" -Path $LogFile
}

function Invoke-BuildBootstrapAreaInput {
    param(
        [string]$AreasFile,
        [string]$Municipality,
        [string]$OutputFile
    )

    if (-not (Test-Path $AreasFile)) {
        throw "Areas file was not found: $AreasFile"
    }

    $areas = @(Import-Csv -Path $AreasFile | Where-Object { $_.municipality -eq $Municipality })
    if ($areas.Count -eq 0) {
        throw "Municipality was not found in areas file: $Municipality"
    }

    $row = $areas[0]
    Write-CsvBom -Rows @([pscustomobject]@{
            municipality = $row.municipality
            population   = $row.population
        }) -Path $OutputFile
}

function Invoke-RegisterSourceCandidates {
    param(
        [string]$CandidatesFile,
        [string]$RegistryFile,
        [string]$Municipality,
        [int]$TopCount,
        [string]$LogFile
    )

    if (-not (Test-Path $CandidatesFile)) {
        throw "Candidates file was not found: $CandidatesFile"
    }

    $candidateRows = @(Import-Csv -Path $CandidatesFile)
    if (-not [string]::IsNullOrWhiteSpace($Municipality)) {
        $candidateRows = @($candidateRows | Where-Object { $_.municipality -eq $Municipality })
    }

    $existingRows = @()
    if (Test-Path $RegistryFile) {
        $existingRows = @(Import-Csv -Path $RegistryFile)
    }

    $existingUrls = @{}
    $existingHosts = @{}
    foreach ($row in $existingRows) {
        $existingUrls[$row.source_url] = $true
        try {
            $existingHosts[([System.Uri]$row.source_url).Host.ToLowerInvariant()] = $true
        }
        catch {
        }
    }

    $rowsToAdd = New-Object System.Collections.Generic.List[object]
    $selectedHosts = @{}
    foreach ($candidate in @($candidateRows | Sort-Object -Property @{ Expression = { [int]$_.score }; Descending = $true }, @{ Expression = { Get-SourceRegistrationPriority -Candidate $_ }; Descending = $true }, source_url)) {
        if ($rowsToAdd.Count -ge $TopCount) {
            break
        }

        if (-not (Test-RegistryReadySourceCandidate -Candidate $candidate)) {
            continue
        }

        if ($existingUrls.ContainsKey($candidate.source_url)) {
            continue
        }

        $sourceHostName = ""
        try {
            $sourceHostName = ([System.Uri]$candidate.source_url).Host.ToLowerInvariant()
        }
        catch {
            $sourceHostName = ""
        }

        if (-not [string]::IsNullOrWhiteSpace($sourceHostName)) {
            if ($existingHosts.ContainsKey($sourceHostName) -or $selectedHosts.ContainsKey($sourceHostName)) {
                continue
            }
        }

        $existingUrls[$candidate.source_url] = $true
        if (-not [string]::IsNullOrWhiteSpace($sourceHostName)) {
            $selectedHosts[$sourceHostName] = $true
        }
        $rowsToAdd.Add([pscustomobject]@{
            municipality = $candidate.municipality
            source_org   = $candidate.source_org_candidate
            source_type  = $candidate.source_type_candidate
            source_url   = $candidate.source_url
            notes        = "auto-registered from discover-source-candidates"
        })
    }

    $combinedRows = @($existingRows + $rowsToAdd | Sort-Object municipality, source_org, source_url)
    Write-CsvBom -Rows $combinedRows -Path $RegistryFile
    Write-LogEntry -Level "info" -Message "register-source-candidates completed: added=$($rowsToAdd.Count) registry=$RegistryFile" -Path $LogFile
}

function Invoke-BootstrapWebPipeline {
    param(
        [string]$Municipality,
        [string]$AreasFile,
        [string]$BootstrapAreaFile,
        [string]$ContractedFile,
        [string]$CandidatesFile,
        [string]$RegistryFile,
        [int]$TopCount,
        [string]$ResolvedFile,
        [string]$WorksetFile,
        [string]$ExtractedCandidatesFile,
        [string]$NormalizedMembersFile,
        [string]$ResolvedMembersFile,
        [string]$WebsiteResolutionCandidatesFile,
        [string]$DetailsFile,
        [string]$CompanyMasterFile,
        [string]$AllOutputFile,
        [string]$UsableOutputFile,
        [string]$ReportOutputFile,
        [int]$TopWebsiteCandidateCount,
        [string]$LogFile
    )

    if ([string]::IsNullOrWhiteSpace($Municipality)) {
        throw "MunicipalityName is required for bootstrap-web-pipeline."
    }

    Invoke-BuildBootstrapAreaInput -AreasFile $AreasFile -Municipality $Municipality -OutputFile $BootstrapAreaFile
    Invoke-DiscoverSourceCandidates -Municipality $Municipality -OutputFile $CandidatesFile -LogFile $LogFile
    $discoveredRows = @()
    if (Test-Path $CandidatesFile) {
        $discoveredRows = @(Import-Csv -Path $CandidatesFile)
    }
    if ($discoveredRows.Count -eq 0) {
        $existingRegistryRows = @()
        if (Test-Path $RegistryFile) {
            $existingRegistryRows = @(Import-Csv -Path $RegistryFile | Where-Object { $_.municipality -eq $Municipality })
        }

        if ($existingRegistryRows.Count -eq 0) {
            throw "No source candidates were found for bootstrap municipality: $Municipality"
        }

        Write-LogEntry -Level "warning" -Message "bootstrap-web-pipeline reused existing registry rows for municipality=$Municipality because discovery returned 0 candidates" -Path $LogFile
    }
    else {
        Invoke-RegisterSourceCandidates -CandidatesFile $CandidatesFile -RegistryFile $RegistryFile -Municipality $Municipality -TopCount $TopCount -LogFile $LogFile
    }
    Invoke-ResolveAreas -AreasFile $BootstrapAreaFile -ContractedFile $ContractedFile -OutputFile $ResolvedFile -MinimumPopulation $MinPopulation -MaximumPopulation $MaxPopulation -LogFile $LogFile
    Invoke-RunWebPipeline -ResolvedFile $ResolvedFile -RegistryFile $RegistryFile -WorksetFile $WorksetFile -CandidatesFile $ExtractedCandidatesFile -NormalizedMembersFile $NormalizedMembersFile -ResolvedMembersFile $ResolvedMembersFile -WebsiteResolutionCandidatesFile $WebsiteResolutionCandidatesFile -DetailsFile $DetailsFile -CompanyMasterFile $CompanyMasterFile -AllOutputFile $AllOutputFile -UsableOutputFile $UsableOutputFile -ReportOutputFile $ReportOutputFile -TopWebsiteCandidateCount $TopWebsiteCandidateCount -LogFile $LogFile
    Write-LogEntry -Level "info" -Message "bootstrap-web-pipeline completed: municipality=$Municipality" -Path $LogFile
}

function Test-IgnoredCandidateUrl {
    param(
        [string]$SourceUrl,
        [string]$CandidateUrl
    )

    if ([string]::IsNullOrWhiteSpace($CandidateUrl)) {
        return $true
    }

    foreach ($prefix in @("tel:", "mailto:", "#", "javascript:")) {
        if ($CandidateUrl.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    foreach ($pattern in @('/wp-login', '/login')) {
        if ($CandidateUrl -match [regex]::Escape($pattern)) {
            return $true
        }
    }

    $sourceHost = ([System.Uri]$SourceUrl).Host.ToLowerInvariant()
    $candidateHost = ([System.Uri]$CandidateUrl).Host.ToLowerInvariant()
    $sameHost = $sourceHost -eq $candidateHost

    foreach ($ignoredHost in @(
            "instagram.com",
            "www.instagram.com",
            "facebook.com",
            "www.facebook.com",
            "goo.gl",
            "maps.google.com",
            "www.google.com",
            "google.co.jp",
            "www.google.co.jp",
            "google.com",
            "go.microsoft.com",
            "support.microsoft.com",
            "mozilla.org",
            "www.mozilla.org",
            "linkedin.com",
            "www.linkedin.com",
            "youtube.com",
            "www.youtube.com",
            "youtu.be",
            "zhihu.com",
            "www.zhihu.com",
            "baidu.com",
            "www.baidu.com",
            "myoji.namedic.jp",
            "minkan.co.jp",
            "kyujin.hellowork.mhlw.go.jp",
            "wordpress.org",
            "ja.wordpress.org",
            "walkerplus.com",
            "www.walkerplus.com",
            "tabiiro.jp",
            "www.tabiiro.jp",
            "homes.co.jp",
            "www.homes.co.jp",
            "athome.co.jp",
            "www.athome.co.jp",
            "ekiten.jp",
            "www.ekiten.jp",
            "kensetumap.com",
            "www.kensetumap.com",
            "info.gbiz.go.jp",
        "houjin.info",
        "www.houjin.info",
        "bankdb.jp",
        "www.bankdb.jp",
        "rakuten.co.jp",
        "travel.rakuten.co.jp",
        "jalan.net",
        "www.jalan.net",
        "nta.co.jp",
        "search.nta.co.jp",
        "estate.sesh.jp",
        "prtimes.jp",
        "www.prtimes.jp",
            "atpress.ne.jp",
            "www.atpress.ne.jp",
            "b-mall.ne.jp",
            "www.b-mall.ne.jp",
            "chiba-hatarakikata.com",
            "www.chiba-hatarakikata.com",
            "chiba-saiyoryoku.jp",
            "www.chiba-saiyoryoku.jp",
            "esod-neo.com",
            "www.esod-neo.com",
            "jcci.or.jp",
            "www.jcci.or.jp",
            "narita-yeg.org",
            "www.narita-yeg.org",
            "nta.go.jp",
            "www.nta.go.jp",
            "rotary.org",
            "www.rotary.org",
            "my.rotary.org",
            "clubmichelin.jp",
            "www.rid2630.jp",
            "rid2630.jp",
            "www.rotary-yoneyama.or.jp",
            "rotary-yoneyama.or.jp",
            "www.rotary-bunko.gr.jp",
            "rotary-bunko.gr.jp",
            "www.endpolio.org",
            "endpolio.org"
        )) {
        if ($candidateHost -eq $ignoredHost -or $candidateHost.EndsWith(".$ignoredHost")) {
            return $true
        }
    }

    if ($sameHost) {
        return $true
    }

    return $false
}

function Get-WebPageTitle {
    param(
        [string]$Url,
        [string]$LogFile
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 20 -Headers (Get-DefaultHttpHeaders)
        $byteStream = New-Object System.IO.MemoryStream
        $response.RawContentStream.Position = 0
        $response.RawContentStream.CopyTo($byteStream)
        $bytes = $byteStream.ToArray()

        $charset = ""
        $contentType = [string]$response.Headers["Content-Type"]
        if ($contentType -match 'charset=([A-Za-z0-9\-_]+)') {
            $charset = $matches[1]
        }

        $asciiPreview = [System.Text.Encoding]::ASCII.GetString($bytes)
        if ([string]::IsNullOrWhiteSpace($charset) -and $asciiPreview -match 'charset=["'']?([A-Za-z0-9\-_]+)') {
            $charset = $matches[1]
        }

        if ([string]::IsNullOrWhiteSpace($charset)) {
            $charset = "utf-8"
        }

        $encodingName = switch -Regex ($charset.ToLowerInvariant()) {
            '^(shift_jis|shift-jis|sjis|x-sjis)$' { "shift_jis"; break }
            '^(euc-jp)$' { "euc-jp"; break }
            default { $charset }
        }

        $encoding = [System.Text.Encoding]::GetEncoding($encodingName)
        $html = $encoding.GetString($bytes)
        $titleMatch = [regex]::Match($html, '<title[^>]*>(.*?)</title>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($titleMatch.Success) {
            $title = [System.Net.WebUtility]::HtmlDecode($titleMatch.Groups[1].Value)
            return ($title -replace '\s+', ' ').Trim()
        }
    }
    catch {
        Write-LogEntry -Level "warning" -Message "Failed to fetch candidate title: $Url" -Path $LogFile
    }

    return ""
}

function Get-DecodedWebPage {
    param(
        [string]$Url,
        [string]$LogFile
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 20 -Headers (Get-DefaultHttpHeaders)
        $byteStream = New-Object System.IO.MemoryStream
        $response.RawContentStream.Position = 0
        $response.RawContentStream.CopyTo($byteStream)
        $bytes = $byteStream.ToArray()

        $charset = ""
        $contentType = [string]$response.Headers["Content-Type"]
        if ($contentType -match 'charset=([A-Za-z0-9\-_]+)') {
            $charset = $matches[1]
        }

        $asciiPreview = [System.Text.Encoding]::ASCII.GetString($bytes)
        if ([string]::IsNullOrWhiteSpace($charset) -and $asciiPreview -match 'charset=["'']?([A-Za-z0-9\-_]+)') {
            $charset = $matches[1]
        }

        if ([string]::IsNullOrWhiteSpace($charset)) {
            $charset = "utf-8"
        }

        $encodingName = switch -Regex ($charset.ToLowerInvariant()) {
            '^(shift_jis|shift-jis|sjis|x-sjis)$' { "shift_jis"; break }
            '^(euc-jp)$' { "euc-jp"; break }
            default { $charset }
        }

        $encoding = [System.Text.Encoding]::GetEncoding($encodingName)
        $html = $encoding.GetString($bytes)
        $text = $html -replace '(?is)<script.*?</script>', ' '
        $text = $text -replace '(?is)<style.*?</style>', ' '
        $text = $text -replace '(?is)<[^>]+>', ' '
        $text = [System.Net.WebUtility]::HtmlDecode($text)
        $text = ($text -replace '\s+', ' ').Trim()

        return [pscustomobject]@{
            Response = $response
            Html     = $html
            Text     = $text
        }
    }
    catch {
        Write-LogEntry -Level "warning" -Message "Failed to fetch detail page: $Url" -Path $LogFile
        return $null
    }
}

function Find-PhoneNumber {
    param([string]$Text)

    $match = [regex]::Match($Text, '(0\d{1,4}-\d{1,4}-\d{3,4})')
    if ($match.Success) {
        return $match.Groups[1].Value
    }

    return ""
}

function Normalize-PostalAddress {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    $normalized = $Value
    $normalized = ($normalized -replace '<[^>]+>', ' ')
    $normalized = [System.Net.WebUtility]::HtmlDecode($normalized)
    $normalized = ($normalized -replace '\s+', ' ').Trim()
    $postalMatch = [regex]::Match($normalized, '〒\d{3}-\d{4}')
    if ($postalMatch.Success) {
        $normalized = $normalized.Substring($postalMatch.Index)
    }
    else {
        $prefectureMatch = [regex]::Match($normalized, '(北海道|東京都|(?:京都|大阪)府|.{2,4}県)')
        if ($prefectureMatch.Success -and $prefectureMatch.Index -gt 0) {
            $normalized = $normalized.Substring($prefectureMatch.Index)
        }
    }
    $normalized = ($normalized -replace '^[0-9０-９]+\s+', '').Trim()
    $normalized = ($normalized -replace '^(所|社)\s+', '').Trim()
    $normalized = ($normalized -replace '^[A-Z]\s+', '').Trim()
    $normalized = ($normalized -replace '^(所在地|住所)\s*[:：]?\s*', '').Trim()
    $normalized = ($normalized -replace '(Tel|TEL|電話|FAX|営業時間|営業日|定休日|受付時間|メール|Mail|E-mail|Copyright|©).*$','').Trim()
    $normalized = ($normalized -replace '(HOME ABOUT SERVICE COMPANY CONTACT|GROUP HO.*|グループコーポレートサイト.*|Instagram.*|さらに読み込む.*|でフォロー.*|NEWS.*|MENU.*|TAKE OUT.*|店舗情報.*|代表者.*|昨日、.*|アクセス.*|℡.*|フリーダイヤル.*|ページの先頭.*)$','').Trim()
    $normalized = ($normalized -replace '【.*$','').Trim()
    $normalized = ($normalized -replace 'お問い合わせをお待ちしております.*$','').Trim()
    $normalized = ($normalized -replace '代表直通番号.*$','').Trim()
    $normalized = ($normalized -replace '事務所番号.*$','').Trim()
    $normalized = ($normalized -replace '建材部／.*$','').Trim()
    $normalized = ($normalized -replace 'お問合せはこちら.*$','').Trim()
    $normalized = ($normalized -replace 'top of page.*$','').Trim()
    $normalized = ($normalized -replace '^様\s+', '').Trim()
    $normalized = ($normalized -replace '^[>可社タ]\s*[｜|]\s*', '').Trim()
    $normalized = ($normalized -replace '/\s*$', '').Trim()
    $normalized = ($normalized -replace '\[$', '').Trim()
    $normalized = ($normalized -replace '\s+[（(]$', '').Trim()
    return $normalized
}

function Find-PostalAddress {
    param(
        [string]$Text,
        [string]$Html
    )

    if (-not [string]::IsNullOrWhiteSpace($Html)) {
        $addressTagMatch = [regex]::Match($Html, '(?is)<address[^>]*>(.*?)</address>')
        if ($addressTagMatch.Success) {
            $value = Normalize-PostalAddress -Value $addressTagMatch.Groups[1].Value
            if (-not [string]::IsNullOrWhiteSpace($value) -and $value -match '(〒\d{3}-\d{4}|北海道|東京都|(?:京都|大阪)府|.{2,4}県)') {
                return $value
            }
        }

        $streetMatch = [regex]::Match($Html, '"streetAddress"\s*:\s*"([^"]+)"')
        if ($streetMatch.Success) {
            $postalCode = ""
            $region = ""
            $locality = ""

            $postalMatch = [regex]::Match($Html, '"postalCode"\s*:\s*"([^"]+)"')
            if ($postalMatch.Success) {
                $postalCode = $postalMatch.Groups[1].Value
            }

            $regionMatch = [regex]::Match($Html, '"addressRegion"\s*:\s*"([^"]+)"')
            if ($regionMatch.Success) {
                $region = $regionMatch.Groups[1].Value
            }

            $localityMatch = [regex]::Match($Html, '"addressLocality"\s*:\s*"([^"]+)"')
            if ($localityMatch.Success) {
                $locality = $localityMatch.Groups[1].Value
            }

            $value = Normalize-PostalAddress -Value ("{0} {1}{2}{3}" -f $postalCode, $region, $locality, $streetMatch.Groups[1].Value)
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                return $value
            }
        }

        $addressObjectMatch = [regex]::Match($Html, '"address"\s*:\s*"([^"]+)"')
        if ($addressObjectMatch.Success) {
            $value = Normalize-PostalAddress -Value $addressObjectMatch.Groups[1].Value
            if (-not [string]::IsNullOrWhiteSpace($value) -and $value -match '(〒\d{3}-\d{4}|北海道|東京都|(?:京都|大阪)府|.{2,4}県|.{1,10}(市|区|町|村))') {
                return $value
            }
        }

        $itempropStreetMatch = [regex]::Match($Html, '(?is)itemprop\s*=\s*["'']streetAddress["''][^>]*>(.*?)<')
        if ($itempropStreetMatch.Success) {
            $value = Normalize-PostalAddress -Value $itempropStreetMatch.Groups[1].Value
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                return $value
            }
        }
    }

    $patterns = @(
        '(所在地|住所)\s*[:：]?\s*(〒\d{3}-\d{4}\s*)?(北海道|東京都|(?:京都|大阪)府|.{2,4}県).{5,100}?((TEL|電話|FAX|営業時間|営業日|定休日|受付時間|メール|Mail|E-mail|Copyright|©)|$)',
        '(所在地|住所)\s*[:：]?\s*(〒\d{3}-\d{4}\s*)?[^ ]{0,12}(市|区|町|村).{5,100}?((TEL|電話|FAX|営業時間|営業日|定休日|受付時間|メール|Mail|E-mail|Copyright|©)|$)',
        '(〒\d{3}-\d{4}\s*(北海道|東京都|(?:京都|大阪)府|.{2,4}県).{5,100}?)(?=(TEL|電話|FAX|営業時間|営業日|定休日|受付時間|メール|Mail|E-mail|Copyright|©|$))',
        '(〒\d{3}-\d{4}\s*[^ ]{0,12}(市|区|町|村).{5,100}?)(?=(TEL|電話|FAX|営業時間|営業日|定休日|受付時間|メール|Mail|E-mail|Copyright|©|$))',
        '((北海道|東京都|(?:京都|大阪)府|.{2,4}県).{8,100}?)(?=(TEL|電話|FAX|営業時間|営業日|定休日|受付時間|メール|Mail|E-mail|Copyright|©|$))'
    )

    foreach ($pattern in $patterns) {
        $match = [regex]::Match($Text, $pattern)
        if ($match.Success) {
            $value = Normalize-PostalAddress -Value $match.Groups[0].Value
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                return $value
            }
        }
    }

    $match = [regex]::Match($Text, '(〒\d{3}-\d{4}\s*[^0-9]{0,4}.{5,80}?)((TEL|電話|FAX|営業時間|Copyright|©)|$)')
    if ($match.Success) {
        $value = Normalize-PostalAddress -Value $match.Groups[1].Value
        return $value
    }

    return ""
}

function Find-ContactFormUrl {
    param(
        [string]$BaseUrl,
        [object]$Response
    )

    foreach ($link in @($Response.Links)) {
        $hrefProperty = $link.PSObject.Properties["href"]
        if ($null -eq $hrefProperty) {
            continue
        }

        $candidateUrl = Resolve-AbsoluteUrl -BaseUrl $BaseUrl -Href ([string]$hrefProperty.Value)
        if ([string]::IsNullOrWhiteSpace($candidateUrl)) {
            continue
        }

        $sameHost = $false
        try {
            $sameHost = ([System.Uri]$candidateUrl).Host -eq ([System.Uri]$BaseUrl).Host
        }
        catch {
            $sameHost = $false
        }

        $innerText = ""
        $textProperty = $link.PSObject.Properties["innerText"]
        if ($null -ne $textProperty) {
            $innerText = [string]$textProperty.Value
        }

        if ($sameHost -and (
                $candidateUrl -match '(contact|inquiry|contact-form|toiawase)' -or
                $innerText -match '(問い合わせ|お問合せ|お問い合わせ|CONTACT|Contact)'
            )) {
            return $candidateUrl
        }
    }

    return ""
}

function Find-CorporateEntityInText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    foreach ($pattern in @(
            '([^|｜│\-－/／*＊]+株式会社)',
            '([^|｜│\-－/／*＊]+有限会社)',
            '([^|｜│\-－/／*＊]+合同会社)',
            '(株式会社[^|｜│\-－/／*＊]+)',
            '(有限会社[^|｜│\-－/／*＊]+)',
            '(合資会社[^|｜│\-－/／*＊]+)',
            '(合名会社[^|｜│\-－/／*＊]+)',
            '(合同会社[^|｜│\-－/／*＊]+)',
            '(司法書士法人[^|｜│\-－/／*＊]+)',
            '(医療法人[^|｜│\-－/／*＊]+)',
            '(学校法人[^|｜│\-－/／*＊]+)'
        )) {
        $match = [regex]::Match($Text, $pattern)
        if ($match.Success) {
            return ($match.Groups[1].Value -replace '\s+', ' ').Trim()
        }
    }

    return ""
}

function Test-CorporateOnlyName {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    return ($Value.Trim() -match '^(株式会社|有限会社|合同会社|合資会社|合名会社|医療法人|学校法人)$')
}

function Test-GenericPromotionalName {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $trimmed = $Value.Trim()
    foreach ($pattern in @(
            '^快適オフィスを創造する$',
            '^ログハウスに住もう.*$',
            '^オリジナルマグカップが.*$',
            '^信頼される安心を、社会へ。$',
            '^こだわりの園芸用土は.*$',
            '^十勝、帯広の人材派遣・求人情報なら.*$',
            '^十勝帯広で新築・注文住宅を建てるなら.*$',
            '^帯広・旭川の不動産.*$',
            '^帯広のホテルなら.*$',
            '^帯広の賃貸や.*$',
            '^帯広の美容室なら.*$',
            '^北海道帯広市の就労継続支援B型事業所なら.*$',
            '^十勝・帯広.*',
            '^帯広・十勝.*',
            '^(北海道|十勝|帯広|岡崎|津山|高山|成田|長浜)(の|で|なら).+',
            '.*公式ホームページ$',
            '.*ホームページ$'
        )) {
        if ($trimmed -match $pattern) {
            return $true
        }
    }

    return $false
}

function Get-TitleDisplayNameCandidate {
    param([string]$TitleSnapshot)

    if ([string]::IsNullOrWhiteSpace($TitleSnapshot)) {
        return ""
    }

    $firstSegment = (([string]$TitleSnapshot -split '[|｜]')[0] -replace '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($firstSegment)) {
        return ""
    }

    $bracketMatch = [regex]::Match($firstSegment, '【([^】]{2,40})】')
    if ($bracketMatch.Success) {
        $value = ($bracketMatch.Groups[1].Value -replace '\s+', ' ').Trim()
        if ($value -notmatch '^(公式|ホーム|TOP|トップ)$') {
            return $value
        }
    }

    $quoteMatch = [regex]::Match($firstSegment, '[「『]([^」』]{2,40})[」』]')
    if ($quoteMatch.Success) {
        return ($quoteMatch.Groups[1].Value -replace '\s+', ' ').Trim()
    }

    $narraMatch = [regex]::Match($firstSegment, 'なら([A-Za-z0-9Ａ-Ｚａ-ｚぁ-んァ-ヶ一-龠・ー\s]{2,40})$')
    if ($narraMatch.Success) {
        return ($narraMatch.Groups[1].Value -replace '\s+', ' ').Trim()
    }

    foreach ($segment in @([string]$TitleSnapshot -split '[|｜]')) {
        $candidateSegment = ($segment -replace '\s+', ' ').Trim()
        if ([string]::IsNullOrWhiteSpace($candidateSegment)) {
            continue
        }

        $candidateSegment = ($candidateSegment -replace '^【公式】', '').Trim()
        if ($candidateSegment.Length -ge 2 -and $candidateSegment.Length -le 30 -and
            $candidateSegment -notmatch '^(公式|ホーム|TOP|トップ|Home)$' -and
            -not (Test-GenericPromotionalName -Value $candidateSegment) -and
            $candidateSegment -notmatch 'ホームページ|トップページ|お問い合わせ|会社概要|事業案内|サービス|採用|RECRUIT|CONTACT') {
            return $candidateSegment
        }
    }

    return ""
}

function Convert-TitleToCompanyName {
    param(
        [string]$Title,
        [string]$Url
    )

    foreach ($segment in @($Title -split '[|｜]')) {
        $corporateName = Find-CorporateEntityInText -Text $segment
        if (-not [string]::IsNullOrWhiteSpace($corporateName)) {
            return $corporateName
        }
    }

    $candidate = $Title
    foreach ($separator in @('|', '｜', ' - ', ' – ', ' — ')) {
        if ($candidate.Contains($separator)) {
            $candidate = $candidate.Split($separator)[0]
        }
    }

    $candidate = ($candidate -replace '\s+', ' ').Trim()
    $candidate = ($candidate -replace '^【公式】', '').Trim()
    $candidate = ($candidate -replace '【[^】]+】', '').Trim()
    $candidate = ($candidate -replace '^(愛知県岡崎市の|岡崎市の|愛知県岡崎の|岡崎の)', '').Trim()
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and $candidate.Length -ge 2) {
        return $candidate
    }

    try {
        $host = ([System.Uri]$Url).Host
        return $host -replace '^www\.', ''
    }
    catch {
        return ""
    }
}

function Test-IntermediaryEvidenceHost {
    param([string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $false
    }

    $hostName = ""
    try {
        $hostName = ([System.Uri]$Url).Host.ToLowerInvariant()
    }
    catch {
        return $false
    }

    $hostName = $hostName -replace '^www\.', ''
    foreach ($pattern in @(
            "athome.co.jp",
            "homes.co.jp",
            "ekiten.jp",
            "kensetumap.com",
            "info.gbiz.go.jp",
            "prtimes.jp",
            "atpress.ne.jp",
            "bankdb.jp",
            "houjin.info",
            "baseconnect.in",
            "buzip.net",
            "rakuten.co.jp",
            "jalan.net",
            "nta.co.jp",
            "estate.sesh.jp"
        )) {
        if ($hostName -eq $pattern -or $hostName.EndsWith(".$pattern")) {
            return $true
        }
    }

    return $false
}

function Get-LinkedWebsiteCandidatesFromHtml {
    param(
        [string]$Html,
        [string]$SourceUrl
    )

    if ([string]::IsNullOrWhiteSpace($Html) -or [string]::IsNullOrWhiteSpace($SourceUrl)) {
        return @()
    }

    $sourceHost = ""
    try {
        $sourceHost = ([System.Uri]$SourceUrl).Host.ToLowerInvariant()
    }
    catch {
        return @()
    }

    $results = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($match in [regex]::Matches($Html, '(?is)<a[^>]+href="([^"]+)"[^>]*>(.*?)</a>')) {
        $href = [System.Net.WebUtility]::HtmlDecode([string]$match.Groups[1].Value)
        $text = [System.Net.WebUtility]::HtmlDecode(([string]$match.Groups[2].Value -replace '<[^>]+>', ' '))
        $resolved = Resolve-SearchResultUrl -Href $href
        if ([string]::IsNullOrWhiteSpace($resolved)) {
            $resolved = $href
        }

        try {
            $uri = [System.Uri]$resolved
        }
        catch {
            continue
        }

        if (-not $uri.IsAbsoluteUri -or [string]::IsNullOrWhiteSpace($uri.Scheme) -or -not $uri.Scheme.StartsWith("http")) {
            continue
        }

        $candidateHost = $uri.Host.ToLowerInvariant()
        if ($candidateHost -eq $sourceHost) {
            continue
        }

        if (Test-IgnoredCandidateUrl -SourceUrl $SourceUrl -CandidateUrl $resolved) {
            continue
        }

        $key = $resolved.TrimEnd('/')
        if ($seen.ContainsKey($key)) {
            continue
        }

        $seen[$key] = $true
        $results.Add([pscustomobject]@{
            href = $resolved
            text = ($text -replace '\s+', ' ').Trim()
        })
    }

    return $results.ToArray()
}

function Convert-WebsiteResolutionScoreToStatus {
    param([int]$Score)

    if ($Score -ge 12) {
        return "official_confirmed"
    }
    if ($Score -ge 8) {
        return "official_probable"
    }
    if ($Score -ge 5) {
        return "weak_candidate"
    }

    return "unknown"
}

function Get-WebsiteCandidatesFromSourceResult {
    param(
        [string]$CompanyName,
        [string]$PersonName,
        [string]$Municipality,
        [string]$SearchQuery,
        [string]$SearchEngine,
        [string]$ResultUrl,
        [string]$ResultTitle,
        [string]$ResultSnippet,
        [string]$LogFile
    )

    $candidates = New-Object System.Collections.Generic.List[object]
    $page = $null
    $pageTitle = $ResultTitle
    $pageText = ""

    $score = Get-WebsiteResolutionScore -CompanyName $CompanyName -PersonName $PersonName -Municipality $Municipality -CandidateUrl $ResultUrl -SearchQuery $SearchQuery -Snippet $ResultSnippet -Title $ResultTitle -PageText ""
    $status = Convert-WebsiteResolutionScoreToStatus -Score ([int]$score.Score)
    if (($status -ne "unknown") -and -not (Test-IntermediaryEvidenceHost -Url $ResultUrl)) {
        $candidates.Add([pscustomobject]@{
            company_name  = $CompanyName
            person_name   = $PersonName
            municipality  = $Municipality
            search_query  = $SearchQuery
            search_engine = $SearchEngine
            candidate_url = $ResultUrl
            title         = $ResultTitle
            snippet       = $ResultSnippet
            score         = [int]$score.Score
            score_reason  = [string]$score.Reason
            status        = $status
            evidence_type = "search_result"
        })
    }

    $isIntermediarySource = Test-IntermediaryEvidenceHost -Url $ResultUrl
    $needsEvidencePage = $isIntermediarySource -or $status -eq "unknown"
    if ($needsEvidencePage) {
        $page = Get-DecodedWebPage -Url $ResultUrl -LogFile $LogFile
        if ($null -ne $page) {
            $pageText = [string]$page.Text
            $titleMatch = [regex]::Match([string]$page.Html, '<title[^>]*>(.*?)</title>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)
            if ($titleMatch.Success) {
                $pageTitle = ([System.Net.WebUtility]::HtmlDecode($titleMatch.Groups[1].Value) -replace '\s+', ' ').Trim()
            }

            if (-not $isIntermediarySource) {
                $pageScore = Get-WebsiteResolutionScore -CompanyName $CompanyName -PersonName $PersonName -Municipality $Municipality -CandidateUrl $ResultUrl -SearchQuery $SearchQuery -Snippet $ResultSnippet -Title $pageTitle -PageText $pageText
                $pageStatus = Convert-WebsiteResolutionScoreToStatus -Score ([int]$pageScore.Score)
                if ($pageStatus -ne "unknown" -and [string]$pageScore.Reason -notmatch 'blocked_domain_or_portal') {
                    $candidates.Add([pscustomobject]@{
                        company_name  = $CompanyName
                        person_name   = $PersonName
                        municipality  = $Municipality
                        search_query  = $SearchQuery
                        search_engine = $SearchEngine
                        candidate_url = $ResultUrl
                        title         = $pageTitle
                        snippet       = $ResultSnippet
                        score         = [int]$pageScore.Score
                        score_reason  = [string]$pageScore.Reason
                        status        = $pageStatus
                        evidence_type = "search_result_page"
                    })
                }
            }

            if ($isIntermediarySource) {
                foreach ($linked in @(Get-LinkedWebsiteCandidatesFromHtml -Html ([string]$page.Html) -SourceUrl $ResultUrl)) {
                    $linkContext = [string]$linked.text
                    if ($linkContext -notmatch '(?i)home|hp|web|website|official|site|company|corp|profile|about') {
                        continue
                    }

                    $linkedTitle = Get-WebPageTitle -Url ([string]$linked.href) -LogFile $LogFile
                    $contextSnippet = ("{0} {1} {2}" -f $ResultSnippet, $linkContext, $pageText)
                    $linkedScore = Get-WebsiteResolutionScore -CompanyName $CompanyName -PersonName $PersonName -Municipality $Municipality -CandidateUrl ([string]$linked.href) -SearchQuery $SearchQuery -Snippet $contextSnippet -Title $linkedTitle -PageText $pageText
                    $linkedStatus = Convert-WebsiteResolutionScoreToStatus -Score ([int]$linkedScore.Score)
                    if ($linkedStatus -eq "unknown" -or [string]$linkedScore.Reason -match 'blocked_domain_or_portal') {
                        continue
                    }

                    $candidates.Add([pscustomobject]@{
                        company_name  = $CompanyName
                        person_name   = $PersonName
                        municipality  = $Municipality
                        search_query  = $SearchQuery
                        search_engine = $SearchEngine
                        candidate_url = [string]$linked.href
                        title         = $linkedTitle
                        snippet       = $contextSnippet
                        score         = [int]$linkedScore.Score
                        score_reason  = [string]$linkedScore.Reason
                        status        = $linkedStatus
                        evidence_type = "linked_from_evidence_page"
                    })
                }
            }
        }
    }

    return $candidates.ToArray()
}

function Get-HtmlTitleFromHtml {
    param([string]$Html)

    if ([string]::IsNullOrWhiteSpace($Html)) {
        return ""
    }

    $titleMatch = [regex]::Match($Html, '<title[^>]*>(.*?)</title>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $titleMatch.Success) {
        return ""
    }

    $title = [System.Net.WebUtility]::HtmlDecode($titleMatch.Groups[1].Value)
    return ($title -replace '\s+', ' ').Trim()
}

function Convert-HtmlToPlainText {
    param([string]$Html)

    if ([string]::IsNullOrWhiteSpace($Html)) {
        return ""
    }

    $text = $Html -replace '(?is)<script.*?</script>', ' '
    $text = $text -replace '(?is)<style.*?</style>', ' '
    $text = $text -replace '(?is)<[^>]+>', ' '
    $text = [System.Net.WebUtility]::HtmlDecode($text)
    return ($text -replace '\s+', ' ').Trim()
}

function Get-CorporateEntityMentionCount {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return 0
    }

    $count = 0
    foreach ($pattern in @(
            '[^ \r\n\t|｜]{1,40}株式会社',
            '[^ \r\n\t|｜]{1,40}有限会社',
            '[^ \r\n\t|｜]{1,40}合同会社',
            '株式会社[^ \r\n\t|｜]{1,40}',
            '有限会社[^ \r\n\t|｜]{1,40}',
            '合同会社[^ \r\n\t|｜]{1,40}',
            '司法書士法人[^ \r\n\t|｜]{1,40}',
            '弁護士法人[^ \r\n\t|｜]{1,40}',
            '医療法人[^ \r\n\t|｜]{1,40}',
            '学校法人[^ \r\n\t|｜]{1,40}',
            '税理士法人[^ \r\n\t|｜]{1,40}'
        )) {
        $count += @([regex]::Matches($Text, $pattern)).Count
    }

    return $count
}

function Test-RecognizedMemberRosterPage {
    param(
        [string]$Html,
        [string]$Text,
        [string]$Title,
        [string]$SourceType,
        [string]$SourceUrl,
        [object[]]$StructuredRows
    )

    $structuredCount = @($StructuredRows).Count
    if ($structuredCount -gt 0) {
        return [pscustomobject]@{
            Recognized = $true
            Reason     = "structured_member_table"
        }
    }

    $combined = ("{0} {1}" -f [string]$Title, [string]$SourceUrl)
    $hasRosterCue = $combined -match '会員紹介|会員名簿|会員一覧|member/?list|memberlist|members?'
    $hasCompanyFieldCue = $Text -match '勤務先|事業所名|企業名|会社名'
    $workplaceCueCount = @([regex]::Matches($Text, '勤務先[:：]')).Count
    $corporateMentionCount = Get-CorporateEntityMentionCount -Text $Text

    switch ($SourceType) {
        "chamber_member_directory" {
            if ($hasCompanyFieldCue -and $workplaceCueCount -ge 3) {
                return [pscustomobject]@{
                    Recognized = $true
                    Reason     = "member_directory_workplace_fields"
                }
            }

            if ($hasRosterCue -and ($hasCompanyFieldCue -or $corporateMentionCount -ge 5)) {
                return [pscustomobject]@{
                    Recognized = $true
                    Reason     = "member_directory_roster_cues"
                }
            }
        }
        "jc_member_list" {
            if ($hasCompanyFieldCue -and $workplaceCueCount -ge 3) {
                return [pscustomobject]@{
                    Recognized = $true
                    Reason     = "jc_member_workplace_fields"
                }
            }

            if ($hasRosterCue -and $corporateMentionCount -ge 5) {
                return [pscustomobject]@{
                    Recognized = $true
                    Reason     = "jc_member_roster_cues"
                }
            }
        }
        default {
            if ($hasRosterCue -and ($hasCompanyFieldCue -or $corporateMentionCount -ge 5)) {
                return [pscustomobject]@{
                    Recognized = $true
                    Reason     = "roster_cues_with_company_signals"
                }
            }
        }
    }

    return [pscustomobject]@{
        Recognized = $false
        Reason     = "no_member_roster_signals"
    }
}

function Convert-HtmlToMeaningfulLines {
    param([string]$Html)

    if ([string]::IsNullOrWhiteSpace($Html)) {
        return @()
    }

    $text = $Html -replace '(?is)<script.*?</script>', ' '
    $text = $text -replace '(?is)<style.*?</style>', ' '
    $text = $text -replace '(?i)<br\s*/?>', "`n"
    $text = $text -replace '(?i)</?(div|section|article|li|ul|ol|p|h[1-6]|tr|td|th|dl|dt|dd)[^>]*>', "`n"
    $text = $text -replace '(?is)<[^>]+>', ' '
    $text = [System.Net.WebUtility]::HtmlDecode($text)

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($text -split "(`r`n|`n|`r)")) {
        $normalized = ($line -replace '\s+', ' ').Trim()
        if ([string]::IsNullOrWhiteSpace($normalized)) {
            continue
        }
        $lines.Add($normalized)
    }

    return @($lines)
}

function Test-PersonNameLike {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $trimmed = ($Value -replace '\s+', ' ').Trim()
    if ($trimmed.Length -lt 2 -or $trimmed.Length -gt 20) {
        return $false
    }

    if ($trimmed -match '^(勤務先|会社名|企業名|事業所名|業種|役職|氏名|名前|会員名|会員紹介|会員一覧|会員名簿|入会案内|お問い合わせ|総合トップページ|HOME|TOP|あ|い|う|え|お|か|き|く|け|こ|さ|し|す|せ|そ|た|ち|つ|て|と|な|に|ぬ|ね|の|は|ひ|ふ|へ|ほ|ま|み|む|め|も|や|ゆ|よ|ら|り|る|れ|ろ|わ)$') {
        return $false
    }

    if ($trimmed -match '(株式会社|有限会社|合同会社|商工会議所|青年会議所|ロータリー|ライオンズ|協議会|同友会|公式|ホームページ|http|https)') {
        return $false
    }

    return ($trimmed -match '^[一-龠々ぁ-んァ-ヶA-Za-z]+(?:\s+[一-龠々ぁ-んァ-ヶA-Za-z]+)?$')
}

function Get-LabeledMemberCompaniesFromHtml {
    param(
        [string]$Html,
        [string]$SourceType
    )

    if ([string]::IsNullOrWhiteSpace($Html)) {
        return @()
    }

    if ($SourceType -ne "chamber_member_directory" -and $SourceType -ne "jc_member_list" -and $SourceType -ne "association_member_list") {
        return @()
    }

    $lines = @(Convert-HtmlToMeaningfulLines -Html $Html)
    if ($lines.Count -eq 0) {
        return @()
    }

    $results = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = [string]$lines[$i]
        $companyName = ""

        if ($line -match '^(勤務先|会社名|企業名|事業所名)\s*[:：]\s*(.+)$') {
            $companyName = $matches[2].Trim()
        }
        elseif ($line -match '^(勤務先|会社名|企業名|事業所名)$' -and ($i + 1) -lt $lines.Count) {
            $companyName = ([string]$lines[$i + 1]).Trim()
        }

        if ([string]::IsNullOrWhiteSpace($companyName)) {
            continue
        }

        if ($companyName -match '^(勤務先|会社名|企業名|事業所名|業種|役職|氏名|名前|会員名)$') {
            continue
        }

        $personName = ""
        $address = ""
        $phone = ""
        $industryText = ""
        $websiteCandidateUrl = ""
        for ($lookback = 1; $lookback -le 4; $lookback++) {
            $candidateIndex = $i - $lookback
            if ($candidateIndex -lt 0) {
                break
            }

            $candidateLine = ([string]$lines[$candidateIndex]).Trim()
            if ([string]::IsNullOrWhiteSpace($candidateLine)) {
                continue
            }

            if ($candidateLine -match '^(氏名|名前|会員名)\s*[:：]\s*(.+)$') {
                $personName = $matches[2].Trim()
                break
            }

            if ($candidateLine -match '^(勤務先|会社名|企業名|事業所名|業種|役職)\s*[:：]') {
                continue
            }

            if (Test-PersonNameLike -Value $candidateLine) {
                $personName = $candidateLine
                break
            }
        }

        for ($lookahead = 0; $lookahead -le 6; $lookahead++) {
            $candidateIndex = $i + $lookahead
            if ($candidateIndex -ge $lines.Count) {
                break
            }

            $candidateLine = ([string]$lines[$candidateIndex]).Trim()
            if ([string]::IsNullOrWhiteSpace($candidateLine)) {
                continue
            }

            if ([string]::IsNullOrWhiteSpace($address)) {
                if ($candidateLine -match '^(所在地|住所)\s*[:：]\s*(.+)$') {
                    $address = $matches[2].Trim()
                }
                elseif ($candidateLine -match '^(所在地|住所)$' -and ($candidateIndex + 1) -lt $lines.Count) {
                    $address = ([string]$lines[$candidateIndex + 1]).Trim()
                }
            }

            if ([string]::IsNullOrWhiteSpace($phone)) {
                if ($candidateLine -match '^(電話番号|電話|TEL)\s*[:：]?\s*(.+)$') {
                    $phone = $matches[2].Trim()
                }
                elseif ($candidateLine -match '(?i)\bTEL\b[:：]?\s*(.+)$') {
                    $phone = $matches[1].Trim()
                }
            }

            if ([string]::IsNullOrWhiteSpace($industryText)) {
                if ($candidateLine -match '^(業種|事業内容)\s*[:：]\s*(.+)$') {
                    $industryText = $matches[2].Trim()
                }
                elseif ($candidateLine -match '^(業種|事業内容)$' -and ($candidateIndex + 1) -lt $lines.Count) {
                    $industryText = ([string]$lines[$candidateIndex + 1]).Trim()
                }
            }

            if ([string]::IsNullOrWhiteSpace($websiteCandidateUrl)) {
                if ($candidateLine -match '(?i)https?://[^\s]+') {
                    $websiteCandidateUrl = $matches[0].Trim()
                }
            }
        }

        $industryParts = Split-IndustryText -IndustryText $industryText

        $titleSnapshot = if ([string]::IsNullOrWhiteSpace($personName)) {
            $companyName
        }
        else {
            '{0} | {1}' -f $personName, $companyName
        }

        $dedupeKey = "{0}|{1}" -f $personName, $companyName
        if ($seen.ContainsKey($dedupeKey)) {
            continue
        }
        $seen[$dedupeKey] = $true

        $results.Add([pscustomobject]@{
            company_name          = $companyName
            person_name           = $personName
            address               = $address
            phone                 = $phone
            industry1             = $industryParts.industry1
            industry2             = $industryParts.industry2
            website_candidate_url = $websiteCandidateUrl
            title_snapshot        = $titleSnapshot
        })
    }

    return @($results | Sort-Object person_name, company_name -Unique)
}

function Get-StructuredMemberCompaniesFromHtml {
    param(
        [string]$Html,
        [string]$SourceType,
        [string]$BaseUrl
    )

    if ([string]::IsNullOrWhiteSpace($Html)) {
        return @()
    }

    if ($SourceType -ne "chamber_member_directory" -and $SourceType -ne "jc_member_list") {
        return @()
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($tableMatch in [regex]::Matches($Html, '(?is)<table[^>]*>(.*?)</table>')) {
        $tableHtml = $tableMatch.Groups[1].Value
        $rows = @([regex]::Matches($tableHtml, '(?is)<tr[^>]*>(.*?)</tr>'))
        if ($rows.Count -lt 2) {
            continue
        }

        $headerCells = @([regex]::Matches($rows[0].Groups[1].Value, '(?is)<t[hd][^>]*>(.*?)</t[hd]>') | ForEach-Object {
                ([System.Net.WebUtility]::HtmlDecode(($_.Groups[1].Value -replace '<[^>]+>', ' ')) -replace '\s+', ' ').Trim()
            })
        if ($headerCells.Count -eq 0) {
            continue
        }

        $companyIndex = -1
        for ($i = 0; $i -lt $headerCells.Count; $i++) {
            if ($headerCells[$i] -match '事業所名|企業名|会社名') {
                $companyIndex = $i
                break
            }
        }
        if ($companyIndex -lt 0) {
            continue
        }

        for ($rowIndex = 1; $rowIndex -lt $rows.Count; $rowIndex++) {
            $rowHtml = $rows[$rowIndex].Groups[1].Value
            $rawCells = @([regex]::Matches($rowHtml, '(?is)<t[hd][^>]*>(.*?)</t[hd]>') | ForEach-Object {
                    $_.Groups[1].Value
                })
            $cells = @($rawCells | ForEach-Object {
                    ([System.Net.WebUtility]::HtmlDecode(($_ -replace '<[^>]+>', ' ')) -replace '\s+', ' ').Trim()
                })
            if ($cells.Count -le $companyIndex) {
                continue
            }

            $companyName = $cells[$companyIndex]
            if ([string]::IsNullOrWhiteSpace($companyName)) {
                continue
            }

            $websiteCandidateUrl = ""
            $companyCellHtml = ""
            if ($rawCells.Count -gt $companyIndex) {
                $companyCellHtml = [string]$rawCells[$companyIndex]
            }

            $rowLinks = New-Object System.Collections.Generic.List[string]
            foreach ($linkMatch in [regex]::Matches($companyCellHtml, '(?is)<a[^>]+href=["'']([^"'']+)["''][^>]*>')) {
                $rowLinks.Add([string]$linkMatch.Groups[1].Value)
            }
            if ($rowLinks.Count -eq 0) {
                foreach ($linkMatch in [regex]::Matches($rowHtml, '(?is)<a[^>]+href=["'']([^"'']+)["''][^>]*>')) {
                    $rowLinks.Add([string]$linkMatch.Groups[1].Value)
                }
            }

            foreach ($href in $rowLinks) {
                $absoluteUrl = Resolve-AbsoluteUrl -BaseUrl $BaseUrl -Href $href
                if (Test-IgnoredCandidateUrl -SourceUrl $BaseUrl -CandidateUrl $absoluteUrl) {
                    continue
                }

                try {
                    $baseHost = ([System.Uri]$BaseUrl).Host.ToLowerInvariant()
                    $candidateHost = ([System.Uri]$absoluteUrl).Host.ToLowerInvariant()
                    if ($candidateHost -eq $baseHost) {
                        continue
                    }
                }
                catch {
                    continue
                }

                $websiteCandidateUrl = $absoluteUrl
                break
            }

            $results.Add([pscustomobject]@{
                company_name          = $companyName
                person_name           = ""
                website_candidate_url = $websiteCandidateUrl
                title_snapshot        = $companyName
            })
        }
    }

    return @($results | Sort-Object company_name, website_candidate_url -Unique)
}

function Find-WebsiteCandidateBySearch {
    param(
        [string]$CompanyName,
        [string]$Municipality,
        [string]$LogFile
    )

    if ([string]::IsNullOrWhiteSpace($CompanyName)) {
        return ""
    }

    $companyToken = $CompanyName
    $companyToken = ($companyToken -replace '（株）|㈱|株式会社|（有）|㈲|有限会社|（同）|合同会社|（弁）|弁護士法人|（医）|医療法人|（司）|（行）', '')
    $companyToken = ($companyToken -replace '\s+', '').Trim()

    $queries = @(
        ('"{0}" {1} 公式' -f $CompanyName, $Municipality),
        ('"{0}" {1}' -f $CompanyName, $Municipality),
        ('{0} {1} 公式' -f $CompanyName, $Municipality),
        ('{0} {1}' -f $CompanyName, $Municipality)
    ) | Select-Object -Unique

    foreach ($query in $queries) {
        $searchUrl = "https://www.bing.com/search?q={0}" -f [System.Uri]::EscapeDataString($query)
    try {
        Start-Sleep -Milliseconds 250
        $response = Invoke-WebRequest -Uri $searchUrl -UseBasicParsing -TimeoutSec 8 -Headers (Get-DefaultHttpHeaders)
    }
        catch {
            Write-LogEntry -Level "warning" -Message "Failed to search company website candidate: $query" -Path $LogFile
            continue
        }

        foreach ($link in @(Get-SearchResultCandidateLinks -Response $response)) {
            $url = Resolve-SearchResultUrl -Href ([string]$link.href)
            if ([string]::IsNullOrWhiteSpace($url)) {
                continue
            }

            if (Test-IgnoredCandidateUrl -SourceUrl "https://search.local/" -CandidateUrl $url) {
                continue
            }

            if ($url -match 'localhost:\d+|support\.microsoft\.com|go\.microsoft\.com|zhidao\.baidu\.com|zhihu\.com|github\.com|chiebukuro\.yahoo\.co\.jp|cmoney\.tw|genius\.com|wikipedia\.org|city\..+\.lg\.jp|pref\..+\.lg\.jp|mhlw\.go\.jp|oshiete\.goo\.ne\.jp|faq\..+\.lg\.jp|faq\.pref\..+\.jp|biz-draft-yamaguchi\.jp|bousai.*portal') {
                continue
            }

            $title = Get-WebPageTitle -Url $url -LogFile $LogFile
            if ([string]::IsNullOrWhiteSpace($title)) {
                continue
            }

            if ($title -match '商工会議所|青年会議所|ロータリー|ライオンズクラブ|倫理法人会|観光協会|Mapion|事業者の紹介|会員一覧|ビジネスドラフト|防災サイト') {
                continue
            }

            if ($companyToken.Length -ge 2 -and $title -notmatch [regex]::Escape($companyToken)) {
                continue
            }

            return $url
        }
    }

    return ""
}

function Get-NormalizedComparisonText {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    $normalized = Normalize-CompanyName -Name $Value
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        $normalized = ($Value -replace '\s+', '').Trim()
    }

    return $normalized.ToLowerInvariant()
}

function Test-TextContainsCompanyToken {
    param(
        [string]$Needle,
        [string]$Haystack
    )

    $normalizedNeedle = Get-NormalizedComparisonText -Value $Needle
    $normalizedHaystack = Get-NormalizedComparisonText -Value $Haystack

    if ([string]::IsNullOrWhiteSpace($normalizedNeedle) -or [string]::IsNullOrWhiteSpace($normalizedHaystack)) {
        return $false
    }

    return $normalizedHaystack.Contains($normalizedNeedle)
}

function Get-WebsiteResolutionScore {
    param(
        [string]$CompanyName,
        [string]$PersonName,
        [string]$Municipality,
        [string]$CandidateUrl,
        [string]$SearchQuery,
        [string]$Snippet,
        [string]$Title,
        [string]$PageText
    )

    $score = 0
    $reasons = New-Object System.Collections.Generic.List[string]
    $combined = ("{0} {1} {2} {3}" -f $Title, $Snippet, $PageText, $CandidateUrl)
    $candidateHost = ""
    $hostToken = ""
    try {
        $candidateHost = ([System.Uri]$CandidateUrl).Host.ToLowerInvariant()
        $hostToken = ($candidateHost -replace '^www\.', '' -replace '\..*$', '')
    }
    catch {
        $candidateHost = ""
        $hostToken = ""
    }

    if (Test-TextContainsCompanyToken -Needle $CompanyName -Haystack $Title) {
        $score += 6
        $reasons.Add("title_company_match")
    }

    if (Test-TextContainsCompanyToken -Needle $CompanyName -Haystack $Snippet) {
        $score += 4
        $reasons.Add("snippet_company_match")
    }

    if (Test-TextContainsCompanyToken -Needle $CompanyName -Haystack $PageText) {
        $score += 6
        $reasons.Add("page_company_match")
    }

    if (-not [string]::IsNullOrWhiteSpace($hostToken) -and (Test-TextContainsCompanyToken -Needle $CompanyName -Haystack $hostToken)) {
        $score += 5
        $reasons.Add("host_company_match")
    }

    if ([string]::IsNullOrWhiteSpace($Title)) {
        $score -= 4
        $reasons.Add("missing_title")
    }

    if (-not [string]::IsNullOrWhiteSpace($Municipality) -and $combined -match [regex]::Escape($Municipality)) {
        $score += 2
        $reasons.Add("municipality_match")
    }

    if (-not [string]::IsNullOrWhiteSpace($PersonName) -and $combined -match [regex]::Escape($PersonName)) {
        $score += 3
        $reasons.Add("person_match")
    }

    if ($combined -match '会社概要|企業情報|事業内容|アクセス|所在地|住所|お問い合わせ|Contact|PROFILE|COMPANY') {
        $score += 2
        $reasons.Add("corporate_page_signal")
    }

    if ($PageText -match '(0\d{1,4}-\d{1,4}-\d{3,4})') {
        $score += 2
        $reasons.Add("phone_present")
    }

    if ($PageText -match '(〒\d{3}-\d{4}|北海道|東京都|(?:京都|大阪)府|.{2,4}県.{1,20}(市|区|町|村))') {
        $score += 2
        $reasons.Add("address_present")
    }

    if ($SearchQuery -match '公式') {
        $score += 1
        $reasons.Add("official_query")
    }

    foreach ($pattern in @(
            'facebook|instagram|x\.com|twitter\.com|tiktok\.com|youtube\.com|line\.me',
            'mapion|maps\.google|google\.com/maps|hotpepper|ekiten|jalan|rakuten|itp\.ne\.jp|navitime|nta\.co\.jp|estate\.sesh\.jp|ikyu\.com|booking\.com|travel',
            'wantedly|green-japan|rikunabi|mynavi|en-gage|engage|求人',
            'wikipedia|note\.com|ameblo|fc2|blog|medium\.com|name-power\.net|jitenon\.jp|autoreserve\.com|16fan\.com|precious\.jp|chiebukuro\.yahoo\.co\.jp',
            'jcci\.or\.jp|yeg\.jp|rotary\.org|lionsclubs\.org|doyu\.jp|go\.microsoft\.com|support\.microsoft\.com|athome\.co\.jp|homes\.co\.jp|kensetumap\.com|houjin\.info|bankdb\.jp|info\.gbiz\.go\.jp|prtimes\.jp|atpress\.ne\.jp'
        )) {
        if ($CandidateUrl -match $pattern) {
            $score -= 8
            $reasons.Add("blocked_domain_or_portal")
            break
        }
    }

    if ($CandidateUrl -match '/news/|/columns?/|/column/|/campaign/|campaign\.|question_detail|/forum/|/category/' -or
        $combined -match 'ニュース|お知らせ|例会報告|活動報告|イベント|ブログ|記事|一覧|コラム|特集|キャンペーン') {
        $score -= 4
        $reasons.Add("article_or_listing_context")
    }

    if ($combined -match '商工会議所|青年会議所|ロータリー|ライオンズクラブ|同友会|協議会') {
        $score -= 3
        $reasons.Add("association_context")
    }

    return [pscustomobject]@{
        Score  = $score
        Reason = ($reasons -join ",")
    }
}

function Test-LikelyOfficialWebsiteResult {
    param(
        [string]$CompanyName,
        [string]$Municipality,
        [string]$CandidateUrl,
        [string]$Title,
        [string]$Snippet,
        [int]$Rank
    )

    if ([string]::IsNullOrWhiteSpace($CandidateUrl)) {
        return $null
    }

    if ($CandidateUrl -match 'zhihu\.com|baidu\.com|hellowork|namedic\.jp|minkan\.co\.jp|wantedly|green-japan|rikunabi|mynavi|en-gage|engage|go\.microsoft\.com|support\.microsoft\.com|chiebukuro\.yahoo\.co\.jp|name-power\.net|jitenon\.jp|precious\.jp|16fan\.com|autoreserve\.com|service\.ntt-east\.co\.jp/columns|finance\.yahoo\.co\.jp|map\.yahoo\.co\.jp|tabelog\.com|hotpepper\.jp|rakuten\.co\.jp|wikipedia\.org|weblio\.jp|stackoverflow\.com|/news/|campaign\.|/campaign/|question_detail|/forum/|/category/') {
        return $null
    }

    $candidateHostName = ""
    try {
        $candidateHostName = ([System.Uri]$CandidateUrl).Host.ToLowerInvariant()
    }
    catch {
        $candidateHostName = ""
    }

    $searchCompanyName = Get-SearchCompanyName -Name $CompanyName
    $hostToken = ($candidateHostName -replace '^www\.', '' -replace '\..*$', '')
    $hasTitleMatch = Test-TextContainsCompanyToken -Needle $searchCompanyName -Haystack $Title
    $hasHostMatch = Test-TextContainsCompanyToken -Needle $searchCompanyName -Haystack $hostToken
    $hasSnippetMatch = Test-TextContainsCompanyToken -Needle $searchCompanyName -Haystack $Snippet
    $hasMunicipality = -not [string]::IsNullOrWhiteSpace($Municipality) -and (("{0} {1}" -f $Title, $Snippet) -match [regex]::Escape($Municipality))
    $hasJapanDomain = $candidateHostName -match '\.jp$'

    if (-not $hasTitleMatch -and -not $hasHostMatch -and -not $hasSnippetMatch) {
        return $null
    }

    $status = "official_probable"
    $score = 8
    $reason = "ranked_search_top_result"

    if ($Rank -eq 1 -and ($hasTitleMatch -or $hasHostMatch)) {
        $status = "official_confirmed"
        $score = 12
        $reason = "rank1_title_or_host_match"
    }
    elseif ($Rank -le 3 -and ($hasTitleMatch -or $hasHostMatch) -and $hasMunicipality) {
        $status = "official_confirmed"
        $score = 11
        $reason = "top3_match_with_area"
    }
    elseif ($Rank -le 3 -and ($hasTitleMatch -or $hasHostMatch -or $hasSnippetMatch) -and ($hasMunicipality -or $hasJapanDomain)) {
        $status = "official_probable"
        $score = 8
        $reason = "top3_light_match"
    }
    else {
        return $null
    }

    return [pscustomobject]@{
        Status = $status
        Score  = $score
        Reason = $reason
    }
}

function Resolve-WebsiteByTopSearchResult {
    param(
        [string]$CompanyName,
        [string]$PersonName,
        [string]$Municipality,
        [string]$LogFile
    )

    if ([string]::IsNullOrWhiteSpace($CompanyName)) {
        return $null
    }

    $searchCompanyName = Get-SearchCompanyName -Name $CompanyName
    $candidatePool = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    foreach ($query in @(Get-WebsiteSearchQueries -CompanyName $searchCompanyName -Municipality $Municipality -PersonName $PersonName)) {
        foreach ($engine in @("yahoojapan", "bing")) {
            $rank = 0
            foreach ($link in @(Invoke-SearchResultFetch -Engine $engine -Query $query -LogFile $LogFile)) {
                $url = Resolve-SearchResultUrl -Href ([string]$link.href)
                if ([string]::IsNullOrWhiteSpace($url)) {
                    continue
                }

                $rank += 1
                if ($rank -gt 8) {
                    break
                }

                foreach ($candidate in @(Get-WebsiteCandidatesFromSourceResult -CompanyName $searchCompanyName -PersonName $PersonName -Municipality $Municipality -SearchQuery ([string]$link.search_query) -SearchEngine ([string]$link.engine) -ResultUrl $url -ResultTitle ([string]$link.title) -ResultSnippet ([string]$link.snippet) -LogFile $LogFile)) {
                    $key = ("{0}|{1}" -f ([string]$candidate.candidate_url).TrimEnd('/'), [string]$candidate.status)
                    if ($seen.ContainsKey($key)) {
                        continue
                    }

                    $seen[$key] = $true
                    $candidatePool.Add($candidate)
                }
            }
        }
    }

    $ordered = @(
        $candidatePool |
        Where-Object { $_.status -in @("official_confirmed", "official_probable") } |
        Sort-Object @{
            Expression = {
                switch ([string]$_.status) {
                    "official_confirmed" { 0; break }
                    "official_probable" { 1; break }
                    default { 2 }
                }
            }
        }, @{
            Expression = { -[int]$_.score }
        }, @{
            Expression = {
                if ([string]$_.evidence_type -eq "linked_from_evidence_page") { 0 } else { 1 }
            }
        }, candidate_url -Unique
    )

    if ($ordered.Count -gt 0) {
        return $ordered[0]
    }

    return $null
}

function Invoke-ResolveCompanyWebsites {
    param(
        [string]$MembersFile,
        [string]$CandidatesOutputFile,
        [string]$OutputFile,
        [int]$TopCount,
        [string]$LogFile
    )

    $memberRows = @()
    if ((Test-Path $MembersFile) -and ((Get-Item $MembersFile).Length -gt 3)) {
        $memberRows = @(Import-Csv -Path $MembersFile)
    }

    $candidateRows = New-Object System.Collections.Generic.List[object]
    $resolvedRows = New-Object System.Collections.Generic.List[object]

    foreach ($row in $memberRows) {
        $existingWebsite = [string]$row.website_candidate_url
        $status = "unknown"
        $resolvedWebsite = ""
        $resolutionReason = ""
        $resolutionScore = 0

        $bestCandidate = $null
        if (-not [string]::IsNullOrWhiteSpace($existingWebsite)) {
            $title = Get-WebPageTitle -Url $existingWebsite -LogFile $LogFile
            $candidateStatus = "official_probable"
            $candidateReason = "member_page_direct_link"
            $candidateScore = 8
            if (Test-TextContainsCompanyToken -Needle ([string]$row.company_name) -Haystack $title) {
                $candidateStatus = "official_confirmed"
                $candidateReason = "member_page_direct_link_title_match"
                $candidateScore = 12
            }

            $bestCandidate = [pscustomobject]@{
                company_name  = [string]$row.company_name
                person_name   = [string]$row.person_name
                municipality  = [string]$row.municipality
                search_query  = "member_page_direct_link"
                candidate_url = $existingWebsite
                title         = $title
                snippet       = ""
                score         = $candidateScore
                score_reason  = $candidateReason
                status        = $candidateStatus
            }
        }
        else {
            $bestCandidate = Resolve-WebsiteByTopSearchResult -CompanyName ([string]$row.company_name) -PersonName ([string]$row.person_name) -Municipality ([string]$row.municipality) -LogFile $LogFile
        }

        if ($null -ne $bestCandidate) {
            $status = [string]$bestCandidate.status
            $resolvedWebsite = [string]$bestCandidate.candidate_url
            $resolutionReason = [string]$bestCandidate.score_reason
            $resolutionScore = [int]$bestCandidate.score

            $candidateRows.Add([pscustomobject]@{
                company_name         = [string]$bestCandidate.company_name
                person_name          = [string]$bestCandidate.person_name
                municipality         = [string]$bestCandidate.municipality
                search_query         = [string]$bestCandidate.search_query
                search_engine        = [string]$bestCandidate.search_engine
                candidate_url        = [string]$bestCandidate.candidate_url
                title                = [string]$bestCandidate.title
                snippet              = [string]$bestCandidate.snippet
                score                = [int]$bestCandidate.score
                score_reason         = [string]$bestCandidate.score_reason
                selected_final       = "true"
                resolution_status    = $status
            })
        }

        $resolvedRows.Add([pscustomobject]@{
            company_name               = [string]$row.company_name
            person_name                = [string]$row.person_name
            municipality               = [string]$row.municipality
            source_org                 = [string]$row.source_org
            source_type                = [string]$row.source_type
            source_url                 = [string]$row.source_url
            website_candidate_url      = $resolvedWebsite
            title_snapshot             = [string]$row.title_snapshot
            website_resolution_status  = $status
            website_resolution_score   = $resolutionScore
            website_resolution_reason  = $resolutionReason
        })
    }

    Write-CsvBom -Rows @($candidateRows | Sort-Object municipality, company_name, @{ Expression = { [int]$_.score }; Descending = $true }, candidate_url) -Path $CandidatesOutputFile
    Write-CsvBom -Rows @($resolvedRows | Sort-Object municipality, company_name) -Path $OutputFile
    Write-LogEntry -Level "info" -Message "resolve-company-websites completed: members=$($resolvedRows.Count) candidates=$($candidateRows.Count)" -Path $LogFile
}

function Invoke-ExtractMemberCandidates {
    param(
        [string]$WorksetFile,
        [string]$OutputFile,
        [string]$LogFile
    )

    $worksetRows = @(Import-Csv -Path $WorksetFile)
    $candidates = New-Object System.Collections.Generic.List[object]
    $seenKeys = @{}
    $successfulSourceFetchCount = 0
    $recognizedSourceCount = 0

    foreach ($source in $worksetRows) {
        try {
            $response = Invoke-WebRequest -Uri $source.source_url -UseBasicParsing -TimeoutSec 20
            $successfulSourceFetchCount += 1
        }
        catch {
            Write-LogEntry -Level "warning" -Message "Failed to fetch source page: $($source.source_url)" -Path $LogFile
            continue
        }

        $sourceHtml = [string]$response.Content
        $structuredRows = @(Get-StructuredMemberCompaniesFromHtml -Html $sourceHtml -SourceType ([string]$source.source_type) -BaseUrl ([string]$source.source_url))
        $labeledRows = @(Get-LabeledMemberCompaniesFromHtml -Html $sourceHtml -SourceType ([string]$source.source_type))
        $memberRows = @($structuredRows + $labeledRows)
        $sourceTitle = Get-HtmlTitleFromHtml -Html $sourceHtml
        $sourceText = Convert-HtmlToPlainText -Html $sourceHtml
        $recognition = Test-RecognizedMemberRosterPage -Html $sourceHtml -Text $sourceText -Title $sourceTitle -SourceType ([string]$source.source_type) -SourceUrl ([string]$source.source_url) -StructuredRows $memberRows
        if (-not $recognition.Recognized) {
            Write-LogEntry -Level "info" -Message "Skipped non-roster source: org=$($source.source_org) type=$($source.source_type) url=$($source.source_url) reason=$($recognition.Reason)" -Path $LogFile
            continue
        }
        $recognizedSourceCount += 1

        foreach ($structuredRow in $memberRows) {
            $normalizedStructuredName = Get-NormalizedMemberCompanyName -CompanyName $structuredRow.company_name -TitleSnapshot $structuredRow.title_snapshot -CandidateUrl ([string]$structuredRow.website_candidate_url) -Municipality $source.municipality -SourceType $source.source_type
            if (-not (Test-NormalizedMemberCandidate -NormalizedName $normalizedStructuredName -TitleSnapshot $structuredRow.title_snapshot -CandidateUrl ([string]$structuredRow.website_candidate_url) -Municipality $source.municipality -SourceType $source.source_type)) {
                continue
            }

            $websiteCandidate = [string]$structuredRow.website_candidate_url

            $dedupeKey = "{0}|{1}|{2}" -f $source.municipality, $normalizedStructuredName, $websiteCandidate
            if ($seenKeys.ContainsKey($dedupeKey)) {
                continue
            }
            $seenKeys[$dedupeKey] = $true

            $candidates.Add([pscustomobject]@{
                company_name          = $normalizedStructuredName
                person_name           = [string]$structuredRow.person_name
                municipality          = $source.municipality
                source_org            = $source.source_org
                source_type           = $source.source_type
                source_url            = $source.source_url
                website_candidate_url = $websiteCandidate
                title_snapshot        = $structuredRow.title_snapshot
            })
        }

        if ($memberRows.Count -gt 0) {
            continue
        }

        foreach ($link in @($response.Links)) {
            $hrefProperty = $link.PSObject.Properties["href"]
            if ($null -eq $hrefProperty) {
                continue
            }

            $absoluteUrl = Resolve-AbsoluteUrl -BaseUrl $source.source_url -Href ([string]$hrefProperty.Value)
            if (Test-IgnoredCandidateUrl -SourceUrl $source.source_url -CandidateUrl $absoluteUrl) {
                continue
            }

            $title = Get-WebPageTitle -Url $absoluteUrl -LogFile $LogFile
            $companyName = Convert-TitleToCompanyName -Title $title -Url $absoluteUrl
            if ([string]::IsNullOrWhiteSpace($companyName)) {
                continue
            }

            $dedupeKey = "{0}|{1}|{2}" -f $source.municipality, $companyName, $absoluteUrl
            if ($seenKeys.ContainsKey($dedupeKey)) {
                continue
            }
            $seenKeys[$dedupeKey] = $true

            $candidates.Add([pscustomobject]@{
                company_name          = $companyName
                person_name           = ""
                municipality          = $source.municipality
                source_org            = $source.source_org
                source_type           = $source.source_type
                source_url            = $source.source_url
                website_candidate_url = $absoluteUrl
                title_snapshot        = $title
            })
        }
    }

    $outputRows = @($candidates | Sort-Object municipality, source_org, company_name)
    if ($outputRows.Count -eq 0 -and $successfulSourceFetchCount -eq 0) {
        if ((Test-Path $OutputFile) -and ((Get-Item $OutputFile).Length -gt 3)) {
            Save-LastGoodCsvCache -SourcePath $OutputFile
            Write-LogEntry -Level "warning" -Message "extract-member-candidates preserved existing file because all source fetches failed: $OutputFile" -Path $LogFile
            return
        }

        if (Restore-LastGoodCsvCache -TargetPath $OutputFile) {
            Write-LogEntry -Level "warning" -Message "extract-member-candidates restored last good cache because all source fetches failed: $OutputFile" -Path $LogFile
            return
        }
    }

    Write-CsvBom -Rows $outputRows -Path $OutputFile
    if ($outputRows.Count -gt 0) {
        Save-LastGoodCsvCache -SourcePath $OutputFile
    }
    Write-LogEntry -Level "info" -Message "extract-member-candidates completed: candidates=$($outputRows.Count) recognized_sources=$recognizedSourceCount fetched_sources=$successfulSourceFetchCount" -Path $LogFile
}

function Get-NormalizedMemberCompanyName {
    param(
        [string]$CompanyName,
        [string]$TitleSnapshot,
        [string]$CandidateUrl,
        [string]$Municipality,
        [string]$SourceType
    )

    $value = [string]$CompanyName
    $corporateName = Find-CorporateEntityInText -Text $value
    if (-not [string]::IsNullOrWhiteSpace($corporateName)) {
        $value = $corporateName
    }

    $value = ($value -replace '【[^】]+】', '').Trim()
    $value = ($value -replace '^(愛知県岡崎市の|岡崎市の|愛知県岡崎の|岡崎の|高山市の|津山市の)', '').Trim()
    $value = ($value -replace '^(お墓・墓・墓石専門店)$', '').Trim()
    $value = ($value -replace '^(岡崎 印刷会社)$', '').Trim()
    $value = ($value -replace '^(岡崎市)$', '').Trim()
    $value = ($value -replace '^(株式会社 公式サイト)$', '').Trim()
    $value = ($value -replace '^(株式会社の公式ホームページ)$', '').Trim()
    $value = ($value -replace '^(転送)$', '').Trim()
    $value = ($value -replace 'にお任せください$', '').Trim()
    $value = ($value -replace 'の公式ホームページ$', '').Trim()
    $value = ($value -replace '^(みなさまの健康で豊かな食生活を豆を通じて応援する「ニチレト」)$', 'ニチレト').Trim()
    $value = ($value -replace '^しゃぶしゃぶ ステーキ桂$', 'しゃぶしゃぶ ステーキ桂').Trim()
    $value = ($value -replace '^ティ・ケイスピリッツ有限会社.*$', 'ティ・ケイスピリッツ有限会社').Trim()
    $value = ($value -replace '^岡崎 和菓子・スイーツなら旭軒元直$', '旭軒元直').Trim()
    $value = ($value -replace '^磯貝彫刻$', '有限会社磯貝彫刻').Trim()
    $value = ($value -replace '^新車・軽自動車リース専門店（株）江山自動車$', '株式会社江山自動車').Trim()
    $value = ($value -replace '^注文住宅 アーツ・ラボ$', 'アーツ・ラボ').Trim()
    $value = ($value -replace '^株式会社の公式ホームページ$', '').Trim()
    $value = ($value -replace '^成田市・銚子市の看板製作・ホームページ制作・印刷$', '山本印刷').Trim()
    $value = ($value -replace '^千葉の注文住宅なら創業125年のヒラヤマホーム$', 'ヒラヤマホーム').Trim()
    $value = ($value -replace '^千葉県成田市 園芸療法 島田建設株式会社$', '島田建設株式会社').Trim()
    $value = ($value -replace '^伝統「火造り技法」の刃物鍛冶、正次郎鋏刃物工芸$', '正次郎鋏刃物工芸').Trim()
    $value = ($value -replace '^映像・音響・制御メーカのピーテック$', 'ピーテック').Trim()
    $value = ($value -replace '^国指定重要文化財 飛騨高山 料亭『洲さき』$', '料亭 洲さき').Trim()
    $value = ($value -replace '^地酒通販│飛騨酒蔵 山車$', '飛騨酒蔵 山車').Trim()
    $value = ($value -replace '^津山市で和食なら個室完備の$', 'お料理わらうかど。').Trim()
    $value = ($value -replace '^株式会社あおばは長浜市から地域の教育に貢献し続けます$', '株式会社あおば').Trim()
    $value = ($value -replace '^宮崎県都城市の注文住宅・家づくりのことなら崎田工務店$', '崎田工務店').Trim()
    $value = ($value -replace '^都城市・三股の不動産売買・賃貸専門サイト$', '小川不動産').Trim()
    $value = ($value -replace '^梅干しの通販なら徳重紅梅園.*$', '徳重紅梅園').Trim()
    $value = ($value -replace '^こだわりの園芸用土はグリーンライフ日向$', 'グリーンライフ日向').Trim()
    $value = ($value -replace '^宮崎県都城市のコーティングならカークリーンサービスヨシハラ$', 'カークリーンサービスヨシハラ').Trim()
    $value = ($value -replace '^畳の新調、襖の張り替え、障子なら$', 'たたみ・ふすまの油井').Trim()
    $value = ($value -replace '^内装工事に携わるなら都城市の株式会社$', '株式会社快誠企画').Trim()
    $value = ($value -replace '^都城市・宮崎の不動産なら新興不動産へ$', '新興不動産').Trim()
    $value = ($value -replace '^宮脇燃料 、おそうじ本舗都城大王店（エアコンクリーニング専門店）LPガス、不動産の仲介$', '宮脇燃料').Trim()
    $value = ($value -replace '^KIRISHIMA$', '霧島ファクトリーガーデン').Trim()
    $value = ($value -replace '^宮崎花ふぶき一座 / 南九州唯一のチンドン屋$', '宮崎花ふぶき一座').Trim()
    $value = ($value -replace '^楠 （クスノキ）にこだわった純国産木製家具の製造・販売$', '橋詰家具').Trim()
    $value = ($value -replace '^幼保連携型 認定こども園 あやめ原こども園│宮崎県都城市菖蒲原町の幼保連携型 認定こども園$', 'あやめ原こども園').Trim()
    $value = ($value -replace '^オンデマンド印刷・バリアブル印刷・長尺印刷の高山印刷株式会社.*$', '高山印刷株式会社').Trim()
    $value = ($value -replace '^コンクリート製品製造、薪・ペレットストーブ、融雪を取扱う岐阜県飛騨高山市『富士コンクリート工業株式会社$', '富士コンクリート工業株式会社').Trim()
    $value = ($value -replace '^ツアーコンダクター（添乗員）派遣・研修なら人材派遣の株式会社$', '株式会社TEI').Trim()
    $value = ($value -replace '^飛騨高山 株式会社$', '株式会社みの谷').Trim()
    $value = ($value -replace '^パッケージデザイン・企画・製造・販売・食品用包装資材・包装機械販売『株式会社$', '株式会社斐太パックス').Trim()
    $value = ($value -replace '^【株式会社$', '').Trim()

    $titleCorporateName = Find-CorporateEntityInText -Text ([string]$TitleSnapshot)
    $titleDisplayName = Get-TitleDisplayNameCandidate -TitleSnapshot $TitleSnapshot
    if ((Test-CorporateOnlyName -Value $value) -and -not [string]::IsNullOrWhiteSpace($titleCorporateName)) {
        $value = $titleCorporateName
    }
    elseif ((Test-GenericPromotionalName -Value $value) -and -not [string]::IsNullOrWhiteSpace($titleCorporateName)) {
        $value = $titleCorporateName
    }
    elseif ((Test-GenericPromotionalName -Value $value) -and -not [string]::IsNullOrWhiteSpace($titleDisplayName)) {
        $value = $titleDisplayName
    }
    elseif ([string]::IsNullOrWhiteSpace($value) -and -not [string]::IsNullOrWhiteSpace($titleCorporateName)) {
        $value = $titleCorporateName
    }
    elseif ([string]::IsNullOrWhiteSpace($value) -and -not [string]::IsNullOrWhiteSpace($titleDisplayName)) {
        $value = $titleDisplayName
    }
    elseif ($value -match '公式ホームページ|ホームページ' -and -not [string]::IsNullOrWhiteSpace($titleCorporateName)) {
        $value = $titleCorporateName
    }
    elseif (-not [string]::IsNullOrWhiteSpace($TitleSnapshot) -and [string]::IsNullOrWhiteSpace($corporateName) -and -not [string]::IsNullOrWhiteSpace($titleCorporateName)) {
        $value = $titleCorporateName
    }

    if (($SourceType -eq "chamber_member_directory" -or $SourceType -eq "jc_member_list" -or $SourceType -eq "rotary_member_voice") -and (Test-GenericPromotionalName -Value $value)) {
        $candidateSegments = @([string]$TitleSnapshot -split '[|｜]')
        foreach ($segment in $candidateSegments) {
            $candidateSegment = ($segment -replace '\s+', ' ').Trim()
            if ([string]::IsNullOrWhiteSpace($candidateSegment)) {
                continue
            }

            if ((Test-GenericPromotionalName -Value $candidateSegment) -or (Test-CorporateOnlyName -Value $candidateSegment)) {
                continue
            }

            if ($candidateSegment.Length -ge 2 -and $candidateSegment.Length -le 30 -and $candidateSegment -notmatch '公式|トップページ|ホームページ|お問い合わせ|会社概要|事業案内|サービス|採用|RECRUIT|CONTACT') {
                $value = $candidateSegment
                break
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($value) -and -not [string]::IsNullOrWhiteSpace($TitleSnapshot)) {
        foreach ($segment in @([string]$TitleSnapshot -split '[|｜]')) {
            $candidateSegment = ($segment -replace '\s+', ' ').Trim()
            if ($candidateSegment.Length -ge 2 -and $candidateSegment.Length -le 24 -and $candidateSegment -notmatch '公式|トップページ|ホームページ|お問い合わせ|会社概要|事業案内|サービス|採用|RECRUIT|CONTACT') {
                $value = $candidateSegment
                break
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
        return ""
    }

    $value = ($value -replace '\s+', ' ').Trim()
    $value = Get-SearchCompanyName -Name $value
    $value = Convert-ToCanonicalCompanyDisplayName -Name $value
    return $value
}

function Test-NormalizedMemberCandidate {
    param(
        [string]$NormalizedName,
        [string]$TitleSnapshot,
        [string]$CandidateUrl,
        [string]$Municipality,
        [string]$SourceType
    )

    if ([string]::IsNullOrWhiteSpace($NormalizedName)) {
        return $false
    }

    if ($NormalizedName -eq $Municipality) {
        return $false
    }

    if ($NormalizedName.Length -lt 2) {
        return $false
    }

    if ($NormalizedName -match '[�]{2,}') {
        return $false
    }

    if (Test-CorporateOnlyName -Value $NormalizedName) {
        return $false
    }

    if (Test-GenericPromotionalName -Value $NormalizedName) {
        return $false
    }

    if ($SourceType -eq "tourism_member_list" -and $NormalizedName -match 'イベント情報集約サイト|トップページ|お花見|エリア特集|観光協会') {
        return $false
    }

    if ($SourceType -eq "ethics_member_list" -and $NormalizedName -match 'Google マップ') {
        return $false
    }

    if (($SourceType -eq "tourism_member_list") -and $NormalizedName -match '道の駅|まちおこし応援団|ツーリズム$|地域振興') {
        return $false
    }

    if (($SourceType -eq "chamber_member_directory") -and $NormalizedName -match '商工会議所|商工会|企業合同就職フェア|経済センサス|ハロートレーニング|リサイクル協会|キャンペーンサイト|会員一覧$|事業者の紹介|防災サイト|ビジネスドラフト|web版') {
        return $false
    }

    if (($SourceType -eq "lions_member_list" -or $SourceType -eq "ethics_member_list" -or $SourceType -eq "rotary_member_voice") -and
        $NormalizedName -match '銀行$|^損保ジャパン$|^明治安田$|神社$|寺$|^公益財団法人|観光協会$|グループ$|ロータリークラブ|ライオンズクラブ|倫理法人会') {
        return $false
    }

    foreach ($blocked in @(
            '国際ロータリー',
            'ロータリー第',
            '商工会議所',
            '青年部',
            'ポータルサイト',
            '掃除代行',
            '賃貸・売買',
            'お墓・墓・墓石専門店',
            '岡崎 印刷会社',
            '転送',
            'ログイン',
            '公式',
            '公式サイト',
            'Home',
            '会社概要'
        )) {
        if ($NormalizedName -like "*$blocked*") {
            return $false
        }
    }

    return $true
}

function Invoke-NormalizeMemberCandidates {
    param(
        [string]$CandidatesFile,
        [string]$OutputFile,
        [string]$LogFile
    )

    $candidateRows = @(Import-Csv -Path $CandidatesFile)
    $normalizedRows = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    foreach ($row in $candidateRows) {
        $normalizedName = Get-NormalizedMemberCompanyName -CompanyName $row.company_name -TitleSnapshot $row.title_snapshot -CandidateUrl $row.website_candidate_url -Municipality $row.municipality -SourceType $row.source_type
        if (-not (Test-NormalizedMemberCandidate -NormalizedName $normalizedName -TitleSnapshot $row.title_snapshot -CandidateUrl $row.website_candidate_url -Municipality $row.municipality -SourceType $row.source_type)) {
            continue
        }

        $dedupeKey = "{0}|{1}" -f $row.municipality, $normalizedName
        if ($seen.ContainsKey($dedupeKey)) {
            continue
        }
        $seen[$dedupeKey] = $true

        $normalizedRows.Add([pscustomobject]@{
            company_name          = $normalizedName
            person_name           = [string]$row.person_name
            municipality          = $row.municipality
            source_org            = $row.source_org
            source_type           = $row.source_type
            source_url            = $row.source_url
            website_candidate_url = $row.website_candidate_url
            title_snapshot        = $row.title_snapshot
        })
    }

    $outputRows = @($normalizedRows | Sort-Object municipality, source_org, company_name)
    if ($outputRows.Count -eq 0) {
        if ((Test-Path $OutputFile) -and ((Get-Item $OutputFile).Length -gt 3)) {
            Save-LastGoodCsvCache -SourcePath $OutputFile
            Write-LogEntry -Level "warning" -Message "normalize-member-candidates preserved existing file because input normalization produced 0 rows: $OutputFile" -Path $LogFile
            return
        }

        if (Restore-LastGoodCsvCache -TargetPath $OutputFile) {
            Write-LogEntry -Level "warning" -Message "normalize-member-candidates restored last good cache because input normalization produced 0 rows: $OutputFile" -Path $LogFile
            return
        }
    }
    Write-CsvBom -Rows $outputRows -Path $OutputFile
    if ($outputRows.Count -gt 0) {
        Save-LastGoodCsvCache -SourcePath $OutputFile
    }
    Write-LogEntry -Level "info" -Message "normalize-member-candidates completed: companies=$($outputRows.Count)" -Path $LogFile
}

function Invoke-ExtractCompanyDetails {
    param(
        [string]$MembersFile,
        [string]$OutputFile,
        [string]$LogFile
    )

    $memberRows = @(Import-Csv -Path $MembersFile)
    $detailRows = New-Object System.Collections.Generic.List[object]
    $successfulDetailFetchCount = 0

    foreach ($row in $memberRows) {
        $website = [string]$row.website_candidate_url
        if ([string]::IsNullOrWhiteSpace($website)) {
            continue
        }

        $page = Get-DecodedWebPage -Url $website -LogFile $LogFile
        $address = ""
        $phone = ""
        $contactFormUrl = ""

        if ($null -ne $page) {
            $successfulDetailFetchCount += 1
            $address = Find-PostalAddress -Text $page.Text -Html $page.Html
            $phone = Find-PhoneNumber -Text $page.Text
            $contactFormUrl = Find-ContactFormUrl -BaseUrl $website -Response $page.Response
        }

        $contactability = 0
        if (-not [string]::IsNullOrWhiteSpace($phone) -or -not [string]::IsNullOrWhiteSpace($website) -or -not [string]::IsNullOrWhiteSpace($contactFormUrl)) {
            $contactability = 1
        }

        $detailRows.Add([pscustomobject]@{
            company_name      = $row.company_name
            municipality      = $row.municipality
            address           = $address
            phone             = $phone
            website           = $website
            contact_form_url  = $contactFormUrl
            detail_source_url = $website
            industry_fit      = 0
            local_focus       = 1
            network_affinity  = 1
            contactability    = $contactability
        })
    }

    $outputRows = @($detailRows | Sort-Object municipality, company_name)
    if ($successfulDetailFetchCount -eq 0) {
        if ((Test-Path $OutputFile) -and ((Get-Item $OutputFile).Length -gt 3)) {
            Save-LastGoodCsvCache -SourcePath $OutputFile
            Write-LogEntry -Level "warning" -Message "extract-company-details preserved existing file because all detail fetches failed: $OutputFile" -Path $LogFile
            return
        }

        if (Restore-LastGoodCsvCache -TargetPath $OutputFile) {
            Write-LogEntry -Level "warning" -Message "extract-company-details restored last good cache because all detail fetches failed: $OutputFile" -Path $LogFile
            return
        }
    }

    if ($outputRows.Count -eq 0) {
        if ((Test-Path $OutputFile) -and ((Get-Item $OutputFile).Length -gt 3)) {
            Save-LastGoodCsvCache -SourcePath $OutputFile
            Write-LogEntry -Level "warning" -Message "extract-company-details preserved existing file because extraction produced 0 rows: $OutputFile" -Path $LogFile
            return
        }

        if (Restore-LastGoodCsvCache -TargetPath $OutputFile) {
            Write-LogEntry -Level "warning" -Message "extract-company-details restored last good cache because extraction produced 0 rows: $OutputFile" -Path $LogFile
            return
        }
    }
    Write-CsvBom -Rows $outputRows -Path $OutputFile
    if ($outputRows.Count -gt 0) {
        Save-LastGoodCsvCache -SourcePath $OutputFile
    }
    Write-LogEntry -Level "info" -Message "extract-company-details completed: rows=$($outputRows.Count)" -Path $LogFile
}

function Invoke-RunWebPipeline {
    param(
        [string]$ResolvedFile,
        [string]$RegistryFile,
        [string]$WorksetFile,
        [string]$CandidatesFile,
        [string]$NormalizedMembersFile,
        [string]$ResolvedMembersFile,
        [string]$WebsiteResolutionCandidatesFile,
        [string]$DetailsFile,
        [string]$CompanyMasterFile,
        [string]$AllOutputFile,
        [string]$UsableOutputFile,
        [string]$ReportOutputFile,
        [int]$TopWebsiteCandidateCount,
        [string]$LogFile
    )

    Invoke-BuildSourceWorkset -ResolvedFile $ResolvedFile -RegistryFile $RegistryFile -OutputFile $WorksetFile -LogFile $LogFile
    Invoke-ExtractMemberCandidates -WorksetFile $WorksetFile -OutputFile $CandidatesFile -LogFile $LogFile
    Invoke-NormalizeMemberCandidates -CandidatesFile $CandidatesFile -OutputFile $NormalizedMembersFile -LogFile $LogFile

    $normalizedRows = @()
    if (Test-Path $NormalizedMembersFile) {
        $normalizedRows = @(Import-Csv -Path $NormalizedMembersFile | Sort-Object municipality, company_name, person_name)
    }

    # The default member-directory flow uses only fields explicitly published on the member page.
    Write-CsvBom -Rows $normalizedRows -Path $ResolvedMembersFile
    Write-CsvBom -Rows @() -Path $WebsiteResolutionCandidatesFile
    Write-CsvBom -Rows @() -Path $DetailsFile

    Invoke-BuildCompanyMasterCommand -ResolvedFile $ResolvedFile -MembersFile $NormalizedMembersFile -DetailsFile $DetailsFile -ScoringFile $scoringFile -OutputFile $CompanyMasterFile -LogFile $LogFile
    Invoke-BuildSalesListFromCompanyMaster -CompanyMasterFile $CompanyMasterFile -AllOutputFile $AllOutputFile -UsableOutputFile $UsableOutputFile -ReportOutputFile $ReportOutputFile -LogFile $LogFile
    Write-LogEntry -Level "info" -Message "run-web-pipeline completed without post-extraction supplementation" -Path $LogFile
}

function Invoke-ReportStatus {
    param(
        [string]$AreasFile,
        [string]$MembersFile,
        [string]$ResolvedFile,
        [string]$CompanyMasterFile,
        [string]$LogFile,
        [string]$OutputFile
    )

    $areas = @(Import-Csv -Path $AreasFile)
    $members = @(Import-Csv -Path $MembersFile)
    $resolved = @(Import-Csv -Path $ResolvedFile)
    $master = @(Import-Csv -Path $CompanyMasterFile)

    $selectedMunicipalities = @($resolved | Where-Object { $_.selected -eq "true" } | ForEach-Object { $_.municipality })
    $selectedMap = @{}
    foreach ($municipality in $selectedMunicipalities) {
        $selectedMap[$municipality] = $true
    }

    $warningOrErrorCount = 0
    if (Test-Path $LogFile) {
        $warningOrErrorCount = @(Get-Content -Path $LogFile | Where-Object { $_ -match "\[(ERROR|WARNING)\]" }).Count
    }

    $reportRows = @(
        [pscustomobject]@{
            step_name    = "resolve-areas"
            input_count  = $areas.Count
            output_count = @($resolved | Where-Object { $_.selected -eq "true" }).Count
            usable_count = ""
            error_count  = @($resolved | Where-Object { $_.excluded_reason -eq "contracted_area" }).Count
        }
        [pscustomobject]@{
            step_name    = "build-company-master"
            input_count  = @($members | Where-Object { $selectedMap.ContainsKey($_.municipality) }).Count
            output_count = $master.Count
            usable_count = @($master | Where-Object { $_.is_usable -eq "true" }).Count
            error_count  = $warningOrErrorCount
        }
    )

    Write-CsvBom -Rows $reportRows -Path $OutputFile
    Write-LogEntry -Level "info" -Message "report-status completed" -Path $LogFile
}

function Get-StructuredMemberCompaniesFromHtml {
    param(
        [string]$Html,
        [string]$SourceType,
        [string]$BaseUrl
    )

    if ([string]::IsNullOrWhiteSpace($Html)) {
        return @()
    }

    if ($SourceType -ne "chamber_member_directory" -and $SourceType -ne "jc_member_list") {
        return @()
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($tableMatch in [regex]::Matches($Html, '(?is)<table[^>]*>(.*?)</table>')) {
        $tableHtml = $tableMatch.Groups[1].Value
        $rows = @([regex]::Matches($tableHtml, '(?is)<tr[^>]*>(.*?)</tr>'))
        if ($rows.Count -lt 2) {
            continue
        }

        $headerCells = @([regex]::Matches($rows[0].Groups[1].Value, '(?is)<t[hd][^>]*>(.*?)</t[hd]>') | ForEach-Object {
                ([System.Net.WebUtility]::HtmlDecode(($_.Groups[1].Value -replace '<[^>]+>', ' ')) -replace '\s+', ' ').Trim()
            })
        if ($headerCells.Count -eq 0) {
            continue
        }

        $companyIndex = -1
        $personIndex = -1
        $addressIndex = -1
        $phoneIndex = -1
        $industryIndex = -1
        $urlIndex = -1

        for ($i = 0; $i -lt $headerCells.Count; $i++) {
            $headerCell = [string]$headerCells[$i]
            if ($companyIndex -lt 0 -and $headerCell -match '事業所名|企業名|会社名') { $companyIndex = $i }
            if ($personIndex -lt 0 -and $headerCell -match '氏名|名前|会員名|代表者') { $personIndex = $i }
            if ($addressIndex -lt 0 -and $headerCell -match '所在地|住所') { $addressIndex = $i }
            if ($phoneIndex -lt 0 -and $headerCell -match '電話|TEL') { $phoneIndex = $i }
            if ($industryIndex -lt 0 -and $headerCell -match '業種|事業内容') { $industryIndex = $i }
            if ($urlIndex -lt 0 -and $headerCell -match 'URL|HP|ホームページ|公式サイト|Web') { $urlIndex = $i }
        }

        if ($companyIndex -lt 0) {
            continue
        }

        for ($rowIndex = 1; $rowIndex -lt $rows.Count; $rowIndex++) {
            $rowHtml = $rows[$rowIndex].Groups[1].Value
            $rawCells = @([regex]::Matches($rowHtml, '(?is)<t[hd][^>]*>(.*?)</t[hd]>') | ForEach-Object { $_.Groups[1].Value })
            $cells = @($rawCells | ForEach-Object {
                    ([System.Net.WebUtility]::HtmlDecode(($_ -replace '<[^>]+>', ' ')) -replace '\s+', ' ').Trim()
                })
            if ($cells.Count -le $companyIndex) {
                continue
            }

            $companyName = [string]$cells[$companyIndex]
            if ([string]::IsNullOrWhiteSpace($companyName)) {
                continue
            }

            $personName = $(if ($personIndex -ge 0 -and $cells.Count -gt $personIndex) { [string]$cells[$personIndex] } else { "" })
            $address = $(if ($addressIndex -ge 0 -and $cells.Count -gt $addressIndex) { [string]$cells[$addressIndex] } else { "" })
            $phone = $(if ($phoneIndex -ge 0 -and $cells.Count -gt $phoneIndex) { [string]$cells[$phoneIndex] } else { "" })
            $industryText = $(if ($industryIndex -ge 0 -and $cells.Count -gt $industryIndex) { [string]$cells[$industryIndex] } else { "" })
            $industryParts = Split-IndustryText -IndustryText $industryText

            $websiteCandidateUrl = ""
            $rowLinks = New-Object System.Collections.Generic.List[string]

            if ($rawCells.Count -gt $companyIndex) {
                foreach ($linkMatch in [regex]::Matches([string]$rawCells[$companyIndex], '(?is)<a[^>]+href=["'']([^"'']+)["''][^>]*>')) {
                    $rowLinks.Add([string]$linkMatch.Groups[1].Value)
                }
            }
            if ($rowLinks.Count -eq 0) {
                foreach ($linkMatch in [regex]::Matches($rowHtml, '(?is)<a[^>]+href=["'']([^"'']+)["''][^>]*>')) {
                    $rowLinks.Add([string]$linkMatch.Groups[1].Value)
                }
            }

            foreach ($href in $rowLinks) {
                $absoluteUrl = Resolve-AbsoluteUrl -BaseUrl $BaseUrl -Href $href
                if (Test-IgnoredCandidateUrl -SourceUrl $BaseUrl -CandidateUrl $absoluteUrl) {
                    continue
                }

                try {
                    $baseHost = ([System.Uri]$BaseUrl).Host.ToLowerInvariant()
                    $candidateHost = ([System.Uri]$absoluteUrl).Host.ToLowerInvariant()
                    if ($candidateHost -eq $baseHost) {
                        continue
                    }
                }
                catch {
                    continue
                }

                $websiteCandidateUrl = $absoluteUrl
                break
            }

            if ([string]::IsNullOrWhiteSpace($websiteCandidateUrl) -and $urlIndex -ge 0 -and $cells.Count -gt $urlIndex) {
                $candidateCellText = [string]$cells[$urlIndex]
                if ($candidateCellText -match '(?i)https?://[^\s]+') {
                    $websiteCandidateUrl = $matches[0].Trim()
                }
            }

            $titleSnapshot = if ([string]::IsNullOrWhiteSpace($personName)) { $companyName } else { '{0} | {1}' -f $personName, $companyName }
            $results.Add([pscustomobject]@{
                company_name          = $companyName
                person_name           = $personName
                address               = $address
                phone                 = $phone
                industry1             = $industryParts.industry1
                industry2             = $industryParts.industry2
                website_candidate_url = $websiteCandidateUrl
                title_snapshot        = $titleSnapshot
            })
        }
    }

    return @($results | Sort-Object company_name, person_name, website_candidate_url -Unique)
}

function Invoke-ExtractMemberCandidates {
    param(
        [string]$WorksetFile,
        [string]$OutputFile,
        [string]$LogFile
    )

    $worksetRows = @(Import-Csv -Path $WorksetFile)
    $candidates = New-Object System.Collections.Generic.List[object]
    $seenKeys = @{}
    $successfulSourceFetchCount = 0
    $recognizedSourceCount = 0

    foreach ($source in $worksetRows) {
        try {
            $response = Invoke-WebRequest -Uri $source.source_url -UseBasicParsing -TimeoutSec 20
            $successfulSourceFetchCount += 1
        }
        catch {
            Write-LogEntry -Level "warning" -Message "Failed to fetch source page: $($source.source_url)" -Path $LogFile
            continue
        }

        $sourceHtml = [string]$response.Content
        $structuredRows = @(Get-StructuredMemberCompaniesFromHtml -Html $sourceHtml -SourceType ([string]$source.source_type) -BaseUrl ([string]$source.source_url))
        $labeledRows = @(Get-LabeledMemberCompaniesFromHtml -Html $sourceHtml -SourceType ([string]$source.source_type))
        $memberRows = @($structuredRows + $labeledRows)
        $sourceTitle = Get-HtmlTitleFromHtml -Html $sourceHtml
        $sourceText = Convert-HtmlToPlainText -Html $sourceHtml
        $recognition = Test-RecognizedMemberRosterPage -Html $sourceHtml -Text $sourceText -Title $sourceTitle -SourceType ([string]$source.source_type) -SourceUrl ([string]$source.source_url) -StructuredRows $memberRows
        if (-not $recognition.Recognized) {
            Write-LogEntry -Level "info" -Message "Skipped non-roster source: org=$($source.source_org) type=$($source.source_type) url=$($source.source_url) reason=$($recognition.Reason)" -Path $LogFile
            continue
        }
        $recognizedSourceCount += 1

        foreach ($structuredRow in $memberRows) {
            $normalizedStructuredName = Get-NormalizedMemberCompanyName -CompanyName $structuredRow.company_name -TitleSnapshot $structuredRow.title_snapshot -CandidateUrl ([string]$structuredRow.website_candidate_url) -Municipality $source.municipality -SourceType $source.source_type
            if (-not (Test-NormalizedMemberCandidate -NormalizedName $normalizedStructuredName -TitleSnapshot $structuredRow.title_snapshot -CandidateUrl ([string]$structuredRow.website_candidate_url) -Municipality $source.municipality -SourceType $source.source_type)) {
                continue
            }

            $websiteCandidate = [string]$structuredRow.website_candidate_url
            $dedupeKey = "{0}|{1}|{2}" -f $source.municipality, $normalizedStructuredName, $websiteCandidate
            if ($seenKeys.ContainsKey($dedupeKey)) {
                continue
            }
            $seenKeys[$dedupeKey] = $true

            $candidates.Add([pscustomobject]@{
                company_name          = $normalizedStructuredName
                person_name           = [string]$structuredRow.person_name
                municipality          = [string]$source.municipality
                source_org            = [string]$source.source_org
                source_type           = [string]$source.source_type
                source_url            = [string]$source.source_url
                address               = [string]$structuredRow.address
                phone                 = [string]$structuredRow.phone
                industry1             = [string]$structuredRow.industry1
                industry2             = [string]$structuredRow.industry2
                website_candidate_url = $websiteCandidate
                title_snapshot        = [string]$structuredRow.title_snapshot
            })
        }

        if ($memberRows.Count -gt 0) {
            continue
        }

        foreach ($link in @($response.Links)) {
            $hrefProperty = $link.PSObject.Properties["href"]
            if ($null -eq $hrefProperty) {
                continue
            }

            $absoluteUrl = Resolve-AbsoluteUrl -BaseUrl $source.source_url -Href ([string]$hrefProperty.Value)
            if (Test-IgnoredCandidateUrl -SourceUrl $source.source_url -CandidateUrl $absoluteUrl) {
                continue
            }

            $title = Get-WebPageTitle -Url $absoluteUrl -LogFile $LogFile
            $companyName = Convert-TitleToCompanyName -Title $title -Url $absoluteUrl
            if ([string]::IsNullOrWhiteSpace($companyName)) {
                continue
            }

            $dedupeKey = "{0}|{1}|{2}" -f $source.municipality, $companyName, $absoluteUrl
            if ($seenKeys.ContainsKey($dedupeKey)) {
                continue
            }
            $seenKeys[$dedupeKey] = $true

            $candidates.Add([pscustomobject]@{
                company_name          = $companyName
                person_name           = ""
                municipality          = [string]$source.municipality
                source_org            = [string]$source.source_org
                source_type           = [string]$source.source_type
                source_url            = [string]$source.source_url
                address               = ""
                phone                 = ""
                industry1             = ""
                industry2             = ""
                website_candidate_url = $absoluteUrl
                title_snapshot        = $title
            })
        }
    }

    $outputRows = @($candidates | Sort-Object municipality, source_org, company_name)
    Write-CsvBom -Rows $outputRows -Path $OutputFile
    Write-LogEntry -Level "info" -Message "extract-member-candidates completed: candidates=$($outputRows.Count) recognized_sources=$recognizedSourceCount fetched_sources=$successfulSourceFetchCount" -Path $LogFile
}

function Invoke-NormalizeMemberCandidates {
    param(
        [string]$CandidatesFile,
        [string]$OutputFile,
        [string]$LogFile
    )

    $candidateRows = @(Import-Csv -Path $CandidatesFile)
    $normalizedRows = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    foreach ($row in $candidateRows) {
        $normalizedName = Get-NormalizedMemberCompanyName -CompanyName $row.company_name -TitleSnapshot $row.title_snapshot -CandidateUrl $row.website_candidate_url -Municipality $row.municipality -SourceType $row.source_type
        if (-not (Test-NormalizedMemberCandidate -NormalizedName $normalizedName -TitleSnapshot $row.title_snapshot -CandidateUrl $row.website_candidate_url -Municipality $row.municipality -SourceType $row.source_type)) {
            continue
        }

        $dedupeKey = "{0}|{1}" -f $row.municipality, $normalizedName
        if ($seen.ContainsKey($dedupeKey)) {
            continue
        }
        $seen[$dedupeKey] = $true

        $normalizedRows.Add([pscustomobject]@{
            company_name          = $normalizedName
            person_name           = [string]$row.person_name
            municipality          = [string]$row.municipality
            source_org            = [string]$row.source_org
            source_type           = [string]$row.source_type
            source_url            = [string]$row.source_url
            address               = [string]$row.address
            phone                 = [string]$row.phone
            industry1             = [string]$row.industry1
            industry2             = [string]$row.industry2
            website_candidate_url = [string]$row.website_candidate_url
            title_snapshot        = [string]$row.title_snapshot
        })
    }

    $outputRows = @($normalizedRows | Sort-Object municipality, source_org, company_name)
    Write-CsvBom -Rows $outputRows -Path $OutputFile
    Write-LogEntry -Level "info" -Message "normalize-member-candidates completed: companies=$($outputRows.Count)" -Path $LogFile
}

function Invoke-ResolveCompanyWebsites {
    param(
        [string]$MembersFile,
        [string]$CandidatesOutputFile,
        [string]$OutputFile,
        [int]$TopCount,
        [string]$LogFile
    )

    $memberRows = @(Import-Csv -Path $MembersFile)
    $candidateRows = New-Object System.Collections.Generic.List[object]
    $resolvedRows = New-Object System.Collections.Generic.List[object]

    foreach ($row in $memberRows) {
        $existingWebsite = [string]$row.website_candidate_url
        $status = "unknown"
        $resolvedWebsite = ""
        $resolutionReason = ""
        $resolutionScore = 0

        $bestCandidate = $null
        if (-not [string]::IsNullOrWhiteSpace($existingWebsite)) {
            $title = Get-WebPageTitle -Url $existingWebsite -LogFile $LogFile
            $candidateStatus = "official_probable"
            $candidateReason = "member_page_direct_link"
            $candidateScore = 8
            if (Test-TextContainsCompanyToken -Needle ([string]$row.company_name) -Haystack $title) {
                $candidateStatus = "official_confirmed"
                $candidateReason = "member_page_direct_link_title_match"
                $candidateScore = 12
            }

            $bestCandidate = [pscustomobject]@{
                company_name  = [string]$row.company_name
                person_name   = [string]$row.person_name
                municipality  = [string]$row.municipality
                search_query  = "member_page_direct_link"
                candidate_url = $existingWebsite
                title         = $title
                snippet       = ""
                score         = $candidateScore
                score_reason  = $candidateReason
                status        = $candidateStatus
            }
        }
        else {
            $bestCandidate = Resolve-WebsiteByTopSearchResult -CompanyName ([string]$row.company_name) -PersonName ([string]$row.person_name) -Municipality ([string]$row.municipality) -LogFile $LogFile
        }

        if ($null -ne $bestCandidate) {
            $status = [string]$bestCandidate.status
            $resolvedWebsite = [string]$bestCandidate.candidate_url
            $resolutionReason = [string]$bestCandidate.score_reason
            $resolutionScore = [int]$bestCandidate.score

            $candidateRows.Add([pscustomobject]@{
                company_name         = [string]$bestCandidate.company_name
                person_name          = [string]$bestCandidate.person_name
                municipality         = [string]$bestCandidate.municipality
                search_query         = [string]$bestCandidate.search_query
                search_engine        = [string]$bestCandidate.search_engine
                candidate_url        = [string]$bestCandidate.candidate_url
                title                = [string]$bestCandidate.title
                snippet              = [string]$bestCandidate.snippet
                score                = [int]$bestCandidate.score
                score_reason         = [string]$bestCandidate.score_reason
                selected_final       = "true"
                resolution_status    = $status
            })
        }

        $resolvedRows.Add([pscustomobject]@{
            company_name               = [string]$row.company_name
            person_name                = [string]$row.person_name
            municipality               = [string]$row.municipality
            source_org                 = [string]$row.source_org
            source_type                = [string]$row.source_type
            source_url                 = [string]$row.source_url
            address                    = [string]$row.address
            phone                      = [string]$row.phone
            industry1                  = [string]$row.industry1
            industry2                  = [string]$row.industry2
            website_candidate_url      = $resolvedWebsite
            title_snapshot             = [string]$row.title_snapshot
            website_resolution_status  = $status
            website_resolution_score   = $resolutionScore
            website_resolution_reason  = $resolutionReason
        })
    }

    Write-CsvBom -Rows @($candidateRows | Sort-Object municipality, company_name, @{ Expression = { [int]$_.score }; Descending = $true }, candidate_url) -Path $CandidatesOutputFile
    Write-CsvBom -Rows @($resolvedRows | Sort-Object municipality, company_name) -Path $OutputFile
    Write-LogEntry -Level "info" -Message "resolve-company-websites completed: members=$($resolvedRows.Count) candidates=$($candidateRows.Count)" -Path $LogFile
}

function Invoke-ExtractCompanyDetails {
    param(
        [string]$MembersFile,
        [string]$OutputFile,
        [string]$LogFile
    )

    $memberRows = @(Import-Csv -Path $MembersFile)
    $detailRows = New-Object System.Collections.Generic.List[object]

    foreach ($row in $memberRows) {
        $website = [string]$row.website_candidate_url
        $address = [string]$row.address
        $phone = [string]$row.phone
        $contactFormUrl = ""

        if (-not [string]::IsNullOrWhiteSpace($website)) {
            $page = Get-DecodedWebPage -Url $website -LogFile $LogFile
            if ($null -ne $page) {
                $websiteAddress = Find-PostalAddress -Text $page.Text -Html $page.Html
                $websitePhone = Find-PhoneNumber -Text $page.Text
                $contactFormUrl = Find-ContactFormUrl -BaseUrl $website -Response $page.Response
                if (-not [string]::IsNullOrWhiteSpace($websiteAddress)) {
                    $address = $websiteAddress
                }
                if (-not [string]::IsNullOrWhiteSpace($websitePhone)) {
                    $phone = $websitePhone
                }
            }
        }

        $contactability = 0
        if (-not [string]::IsNullOrWhiteSpace($phone) -or -not [string]::IsNullOrWhiteSpace($website) -or -not [string]::IsNullOrWhiteSpace($contactFormUrl)) {
            $contactability = 1
        }

        $detailRows.Add([pscustomobject]@{
            company_name      = [string]$row.company_name
            municipality      = [string]$row.municipality
            address           = $address
            phone             = $phone
            website           = $website
            contact_form_url  = $contactFormUrl
            detail_source_url = $website
            industry1         = [string]$row.industry1
            industry2         = [string]$row.industry2
            industry_fit      = 0
            local_focus       = 1
            network_affinity  = 1
            contactability    = $contactability
        })
    }

    $outputRows = @($detailRows | Sort-Object municipality, company_name)
    Write-CsvBom -Rows $outputRows -Path $OutputFile
    Write-LogEntry -Level "info" -Message "extract-company-details completed: rows=$($outputRows.Count)" -Path $LogFile
}

function Merge-CandidatePair {
    param(
        [pscustomobject]$Primary,
        [pscustomobject]$Secondary
    )

    $representative = Get-PreferredCandidate -Left $Primary -Right $Secondary
    $other = $(if ($representative -eq $Primary) { $Secondary } else { $Primary })

    [pscustomobject]@{
        company_name      = $representative.company_name
        person_name       = $(if (-not [string]::IsNullOrWhiteSpace($representative.person_name)) { $representative.person_name } else { $other.person_name })
        municipality      = $representative.municipality
        address           = $(if (-not [string]::IsNullOrWhiteSpace($representative.address)) { $representative.address } else { $other.address })
        phone             = $(if (-not [string]::IsNullOrWhiteSpace($representative.phone)) { $representative.phone } else { $other.phone })
        website           = $(if (-not [string]::IsNullOrWhiteSpace($representative.website)) { $representative.website } else { $other.website })
        contact_form_url  = $(if (-not [string]::IsNullOrWhiteSpace($representative.contact_form_url)) { $representative.contact_form_url } else { $other.contact_form_url })
        source_org        = $representative.source_org
        source_url        = $representative.source_url
        detail_source_url = $(if (-not [string]::IsNullOrWhiteSpace($representative.detail_source_url)) { $representative.detail_source_url } else { $other.detail_source_url })
        industry1         = $(if (-not [string]::IsNullOrWhiteSpace($representative.industry1)) { $representative.industry1 } else { $other.industry1 })
        industry2         = $(if (-not [string]::IsNullOrWhiteSpace($representative.industry2)) { $representative.industry2 } else { $other.industry2 })
        industry_fit      = [math]::Max([double]$Primary.industry_fit, [double]$Secondary.industry_fit)
        local_focus       = [math]::Max([double]$Primary.local_focus, [double]$Secondary.local_focus)
        network_affinity  = [math]::Max([double]$Primary.network_affinity, [double]$Secondary.network_affinity)
        contactability    = [math]::Max([double]$Primary.contactability, [double]$Secondary.contactability)
        match_status      = $(if ($Primary.match_status -eq "exact" -or $Secondary.match_status -eq "exact") { "exact" } elseif ($Primary.match_status -eq "ambiguous" -or $Secondary.match_status -eq "ambiguous") { "ambiguous" } else { "missing" })
        source_count      = ([int]$Primary.source_count + [int]$Secondary.source_count)
        source_summary    = $(Merge-UniqueSummary -Existing $Primary.source_summary -Additional $Secondary.source_summary)
    }
}

function Merge-DetailRows {
    param([System.Collections.IEnumerable]$Rows)

    $rowList = @($Rows)
    if ($rowList.Count -eq 0) {
        return $null
    }

    $merged = $rowList[0]
    for ($i = 1; $i -lt $rowList.Count; $i++) {
        $current = $rowList[$i]
        if (-not (Test-DuplicateCandidate -Left $merged -Right $current)) {
            return $null
        }

        $merged = [pscustomobject]@{
            company_name      = $(if (-not [string]::IsNullOrWhiteSpace($merged.company_name)) { $merged.company_name } else { $current.company_name })
            municipality      = $(if (-not [string]::IsNullOrWhiteSpace($merged.municipality)) { $merged.municipality } else { $current.municipality })
            address           = $(if (-not [string]::IsNullOrWhiteSpace($merged.address)) { $merged.address } else { $current.address })
            phone             = $(if (-not [string]::IsNullOrWhiteSpace($merged.phone)) { $merged.phone } else { $current.phone })
            website           = $(if (-not [string]::IsNullOrWhiteSpace($merged.website)) { $merged.website } else { $current.website })
            contact_form_url  = $(if (-not [string]::IsNullOrWhiteSpace($merged.contact_form_url)) { $merged.contact_form_url } else { $current.contact_form_url })
            detail_source_url = $(if (-not [string]::IsNullOrWhiteSpace($merged.detail_source_url)) { $merged.detail_source_url } else { $current.detail_source_url })
            industry1         = $(if (-not [string]::IsNullOrWhiteSpace($merged.industry1)) { $merged.industry1 } else { $current.industry1 })
            industry2         = $(if (-not [string]::IsNullOrWhiteSpace($merged.industry2)) { $merged.industry2 } else { $current.industry2 })
            industry_fit      = [math]::Max([double]$merged.industry_fit, [double]$current.industry_fit)
            local_focus       = [math]::Max([double]$merged.local_focus, [double]$current.local_focus)
            network_affinity  = [math]::Max([double]$merged.network_affinity, [double]$current.network_affinity)
            contactability    = [math]::Max([double]$merged.contactability, [double]$current.contactability)
        }
    }

    return $merged
}

function Invoke-BuildCompanyMaster {
    param(
        [System.Collections.IEnumerable]$MemberRows,
        [System.Collections.IEnumerable]$DetailRows,
        [hashtable]$ScoringConfig,
        [string]$LogFile
    )

    $candidateRows = New-Object System.Collections.Generic.List[object]

    foreach ($member in $MemberRows) {
        $exactMatches = @($DetailRows | Where-Object { $_.company_name -eq $member.company_name -and $_.municipality -eq $member.municipality })
        $sameNameMatches = @($DetailRows | Where-Object { $_.company_name -eq $member.company_name })

        $matchStatus = "missing"
        $detail = $null

        if ($exactMatches.Count -eq 1) {
            $detail = $exactMatches[0]
            $matchStatus = "exact"
        }
        elseif ($exactMatches.Count -gt 1) {
            $mergedDetail = Merge-DetailRows -Rows $exactMatches
            if ($null -ne $mergedDetail) {
                $detail = $mergedDetail
                $matchStatus = "exact"
            }
            else {
                $matchStatus = "ambiguous"
            }
        }
        elseif ($sameNameMatches.Count -gt 1) {
            $matchStatus = "ambiguous"
        }

        $address = [string]$member.address
        $phone = [string]$member.phone
        $website = [string]$member.website_candidate_url
        $contactFormUrl = ""
        $detailSource = ""
        $industry1 = [string]$member.industry1
        $industry2 = [string]$member.industry2

        if ($matchStatus -eq "exact" -and $null -ne $detail) {
            if (-not [string]::IsNullOrWhiteSpace([string]$detail.address)) { $address = [string]$detail.address }
            if (-not [string]::IsNullOrWhiteSpace([string]$detail.phone)) { $phone = [string]$detail.phone }
            if (-not [string]::IsNullOrWhiteSpace([string]$detail.website)) { $website = [string]$detail.website }
            $contactFormUrl = [string]$detail.contact_form_url
            $detailSource = [string]$detail.detail_source_url
            if (-not [string]::IsNullOrWhiteSpace([string]$detail.industry1)) { $industry1 = [string]$detail.industry1 }
            if (-not [string]::IsNullOrWhiteSpace([string]$detail.industry2)) { $industry2 = [string]$detail.industry2 }
        }

        $sourceSummary = $member.source_org
        if (-not [string]::IsNullOrWhiteSpace($member.source_url)) {
            $sourceSummary = '{0} <{1}>' -f $member.source_org, $member.source_url
        }

        $candidateRows.Add([pscustomobject]@{
            company_name          = [string]$member.company_name
            person_name           = [string]$member.person_name
            municipality          = [string]$member.municipality
            location_municipality = Get-MunicipalityFromAddress -Address $address -FallbackMunicipality ([string]$member.municipality)
            address               = $address
            phone                 = $phone
            website               = $website
            contact_form_url      = $contactFormUrl
            source_org            = [string]$member.source_org
            source_url            = [string]$member.source_url
            detail_source_url     = $detailSource
            industry1             = $industry1
            industry2             = $industry2
            industry_fit          = $(if ($null -ne $detail) { [double]$detail.industry_fit } else { 0 })
            local_focus           = $(if ($null -ne $detail) { [double]$detail.local_focus } else { 0 })
            network_affinity      = $(if ($null -ne $detail) { [double]$detail.network_affinity } else { 0 })
            contactability        = $(if ($null -ne $detail) { [double]$detail.contactability } else { 0 })
            match_status          = $matchStatus
            source_count          = 1
            source_summary        = $sourceSummary
        })
    }

    $mergedCandidates = Merge-CandidateRows -Rows $candidateRows
    $outputRows = New-Object System.Collections.Generic.List[object]

    foreach ($candidate in $mergedCandidates) {
        $usable = Get-UsableStatus -CompanyName $candidate.company_name -Address $candidate.address -Phone $candidate.phone -Website $candidate.website -MatchStatus $candidate.match_status
        $score = Get-ScoreResult -Detail $candidate -MatchStatus $candidate.match_status -ScoringConfig $ScoringConfig

        $outputRows.Add([pscustomobject]@{
            company_name          = $candidate.company_name
            person_name           = $candidate.person_name
            municipality          = $candidate.municipality
            location_municipality = $(if (-not [string]::IsNullOrWhiteSpace([string]$candidate.location_municipality)) { [string]$candidate.location_municipality } else { Get-MunicipalityFromAddress -Address ([string]$candidate.address) -FallbackMunicipality ([string]$candidate.municipality) })
            address               = $candidate.address
            phone                 = $candidate.phone
            website               = $candidate.website
            contact_form_url      = $candidate.contact_form_url
            source_org            = $candidate.source_org
            source_url            = $candidate.source_url
            source_count          = $candidate.source_count
            source_summary        = $candidate.source_summary
            detail_source_url     = $candidate.detail_source_url
            industry1             = $candidate.industry1
            industry2             = $candidate.industry2
            industry_fit          = $candidate.industry_fit
            local_focus           = $candidate.local_focus
            network_affinity      = $candidate.network_affinity
            contactability        = $candidate.contactability
            is_usable             = $usable.IsUsable
            usable_reason         = $usable.Reason
            priority_score        = $score.Score
            priority_rank         = $score.Rank
            score_reason          = $score.Reason
            score_confidence      = $score.Confidence
        })
    }

    return $outputRows
}

function Convert-CompanyMasterRowToSalesListRow {
    param([pscustomobject]$Row)

    [pscustomobject][ordered]@{
        '所属団体名'               = [string]$Row.source_org
        '企業名'                   = [string]$Row.company_name
        '代表者氏名'               = [string]$Row.person_name
        '所在地(市区町村まで)'     = $(if (-not [string]::IsNullOrWhiteSpace([string]$Row.location_municipality)) { [string]$Row.location_municipality } else { Get-MunicipalityFromAddress -Address ([string]$Row.address) -FallbackMunicipality ([string]$Row.municipality) })
        '公式サイトURL'            = [string]$Row.website
        '電話番号'                 = [string]$Row.phone
        '問い合わせフォームURL'    = [string]$Row.contact_form_url
        '業種1'                    = [string]$Row.industry1
        '業種2'                    = [string]$Row.industry2
        'priority_rank'            = [string]$Row.priority_rank
        'priority_score'           = [string]$Row.priority_score
        'address'                  = [string]$Row.address
        'source_url'               = [string]$Row.source_url
        'score_reason'             = [string]$Row.score_reason
        'score_confidence'         = [string]$Row.score_confidence
        'detail_source_url'        = [string]$Row.detail_source_url
        'source_count'             = [string]$Row.source_count
        'source_summary'           = [string]$Row.source_summary
        'industry_fit'             = [string]$Row.industry_fit
        'local_focus'              = [string]$Row.local_focus
        'network_affinity'         = [string]$Row.network_affinity
        'contactability'           = [string]$Row.contactability
        'municipality_match'       = $(if ($null -ne $Row.PSObject.Properties['municipality_match']) { [string]$Row.municipality_match } else { "" })
    }
}

function Invoke-BuildSalesListFromCompanyMaster {
    param(
        [string]$CompanyMasterFile,
        [string]$AllOutputFile,
        [string]$UsableOutputFile,
        [string]$ReportOutputFile,
        [string]$LogFile
    )

    $allRows = @(Import-Csv -Path $CompanyMasterFile | Sort-Object -Property @{ Expression = { [int]$_.priority_score }; Descending = $true }, municipality, company_name)
    $usableRows = @($allRows | Where-Object {
            $_.is_usable -eq "true" -and
            (Test-AddressMatchesMunicipality -Municipality $_.municipality -Address $_.address) -and
            (Test-WebUsableCompanyNameQuality -CompanyName $_.company_name) -and
            (Test-WebUsableAddressQuality -Address $_.address)
        } | ForEach-Object {
            $_ | Add-Member -NotePropertyName municipality_match -NotePropertyValue "true" -Force
            $_
        })

    $reportRows = @(
        foreach ($group in ($allRows | Group-Object municipality | Sort-Object Name)) {
            $rows = @($group.Group)
            $usableRowsForMunicipality = @($rows | Where-Object {
                    $_.is_usable -eq "true" -and
                    (Test-AddressMatchesMunicipality -Municipality $_.municipality -Address $_.address) -and
                    (Test-WebUsableCompanyNameQuality -CompanyName $_.company_name) -and
                    (Test-WebUsableAddressQuality -Address $_.address)
                })
            [pscustomobject]@{
                municipality       = $group.Name
                total_count        = $rows.Count
                usable_count       = $usableRowsForMunicipality.Count
                top_rank_count     = @($rows | Where-Object { $_.priority_rank -eq "A" }).Count
                contact_form_count = @($rows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.contact_form_url) }).Count
            }
        }
    )

    Write-CsvBom -Rows @($allRows | ForEach-Object { Convert-CompanyMasterRowToSalesListRow -Row $_ }) -Path $AllOutputFile
    Write-CsvBom -Rows @($usableRows | ForEach-Object { Convert-CompanyMasterRowToSalesListRow -Row $_ }) -Path $UsableOutputFile
    Write-CsvBom -Rows $reportRows -Path $ReportOutputFile

    Write-LogEntry -Level "info" -Message "build-sales-list-from-company-master completed: total=$($allRows.Count) usable=$($usableRows.Count) municipalities=$($reportRows.Count)" -Path $LogFile
}

function Convert-CompanyMasterRowToSalesListRow {
    param([pscustomobject]$Row)

    [pscustomobject][ordered]@{
        '所属団体名'             = [string]$Row.source_org
        '企業名'                 = [string]$Row.company_name
        '代表者氏名'             = [string]$Row.person_name
        '所在地(市区町村まで)'   = $(if (-not [string]::IsNullOrWhiteSpace([string]$Row.location_municipality)) { [string]$Row.location_municipality } else { Get-MunicipalityFromAddress -Address ([string]$Row.address) -FallbackMunicipality ([string]$Row.municipality) })
        '公式サイトURL'          = [string]$Row.website
        '電話番号'               = [string]$Row.phone
        '問い合わせフォームURL' = [string]$Row.contact_form_url
        '業種1'                  = [string]$Row.industry1
        '業種2'                  = [string]$Row.industry2
    }
}

$areasFile = Resolve-RepoPath -Path $AreasPath
$contractedFile = Resolve-RepoPath -Path $ContractedPath
$resolvedFile = Resolve-RepoPath -Path $ResolvedAreasPath
$membersFile = Resolve-RepoPath -Path $MemberCompaniesPath
$detailsFile = Resolve-RepoPath -Path $CompanyDetailsPath
$scoringFile = Resolve-RepoPath -Path $ScoringPath
$companyMasterFile = Resolve-RepoPath -Path $CompanyMasterPath
$progressFile = Resolve-RepoPath -Path $ProgressReportPath
$logFile = Resolve-RepoPath -Path $LogPath
$script:CsvNormalizationLogPath = $logFile
$realDirectory = Resolve-RepoPath -Path $RealDataDirectory
$realResolvedFile = Resolve-RepoPath -Path $RealResolvedAreasPath
$realSalesListFile = Resolve-RepoPath -Path $RealSalesListPath
$realSalesUsableFile = Resolve-RepoPath -Path $RealSalesUsablePath
$realSalesReportFile = Resolve-RepoPath -Path $RealSalesReportPath
$sourceRegistryFile = Resolve-RepoPath -Path $SourceRegistryPath
$sourceWorksetFile = Resolve-RepoPath -Path $SourceWorksetPath
$extractedMemberCandidatesFile = Resolve-RepoPath -Path $ExtractedMemberCandidatesPath
$normalizedMemberCompaniesFile = Resolve-RepoPath -Path $NormalizedMemberCompaniesPath
$resolvedMemberCompaniesFile = Resolve-RepoPath -Path $ResolvedMemberCompaniesPath
$websiteResolutionCandidatesFile = Resolve-RepoPath -Path $WebsiteResolutionCandidatesPath
$extractedCompanyDetailsFile = Resolve-RepoPath -Path $ExtractedCompanyDetailsPath
$webSalesListFile = Resolve-RepoPath -Path $WebSalesListPath
$webSalesUsableFile = Resolve-RepoPath -Path $WebSalesUsablePath
$webSalesReportFile = Resolve-RepoPath -Path $WebSalesReportPath
$sourceDiscoveryFile = Resolve-RepoPath -Path $SourceDiscoveryPath
$bootstrapAreaFile = Resolve-RepoPath -Path $BootstrapAreaPath

switch ($Command) {
    "resolve-areas" {
        Invoke-ResolveAreas -AreasFile $areasFile -ContractedFile $contractedFile -OutputFile $resolvedFile -MinimumPopulation $MinPopulation -MaximumPopulation $MaxPopulation -LogFile $logFile
    }
    "build-company-master" {
        Invoke-BuildCompanyMasterCommand -ResolvedFile $resolvedFile -MembersFile $membersFile -DetailsFile $detailsFile -ScoringFile $scoringFile -OutputFile $companyMasterFile -LogFile $logFile
    }
    "report-status" {
        Invoke-ReportStatus -AreasFile $areasFile -MembersFile $membersFile -ResolvedFile $resolvedFile -CompanyMasterFile $companyMasterFile -LogFile $logFile -OutputFile $progressFile
    }
    "build-real-sales-list" {
        Invoke-BuildRealSalesList -RealDirectory $realDirectory -ResolvedFilterFile "" -ScoringFile $scoringFile -AllOutputFile $realSalesListFile -UsableOutputFile $realSalesUsableFile -ReportOutputFile $realSalesReportFile -LogFile $logFile
    }
    "run-real-pipeline" {
        Invoke-RunRealPipeline -AreasFile $areasFile -ContractedFile $contractedFile -ResolvedFile $realResolvedFile -RealDirectory $realDirectory -ScoringFile $scoringFile -AllOutputFile $realSalesListFile -UsableOutputFile $realSalesUsableFile -ReportOutputFile $realSalesReportFile -MinimumPopulation $MinPopulation -MaximumPopulation $MaxPopulation -LogFile $logFile
    }
    "build-source-workset" {
        Invoke-BuildSourceWorkset -ResolvedFile $realResolvedFile -RegistryFile $sourceRegistryFile -OutputFile $sourceWorksetFile -LogFile $logFile
    }
    "extract-member-candidates" {
        Invoke-ExtractMemberCandidates -WorksetFile $sourceWorksetFile -OutputFile $extractedMemberCandidatesFile -LogFile $logFile
    }
    "normalize-member-candidates" {
        Invoke-NormalizeMemberCandidates -CandidatesFile $extractedMemberCandidatesFile -OutputFile $normalizedMemberCompaniesFile -LogFile $logFile
    }
    "resolve-company-websites" {
        Invoke-ResolveCompanyWebsites -MembersFile $normalizedMemberCompaniesFile -CandidatesOutputFile $websiteResolutionCandidatesFile -OutputFile $resolvedMemberCompaniesFile -TopCount $TopWebsiteCandidates -LogFile $logFile
    }
    "extract-company-details" {
        Invoke-ExtractCompanyDetails -MembersFile $resolvedMemberCompaniesFile -OutputFile $extractedCompanyDetailsFile -LogFile $logFile
    }
    "run-web-pipeline" {
        Invoke-RunWebPipeline -ResolvedFile $realResolvedFile -RegistryFile $sourceRegistryFile -WorksetFile $sourceWorksetFile -CandidatesFile $extractedMemberCandidatesFile -NormalizedMembersFile $normalizedMemberCompaniesFile -ResolvedMembersFile $resolvedMemberCompaniesFile -WebsiteResolutionCandidatesFile $websiteResolutionCandidatesFile -DetailsFile $extractedCompanyDetailsFile -CompanyMasterFile $companyMasterFile -AllOutputFile $webSalesListFile -UsableOutputFile $webSalesUsableFile -ReportOutputFile $webSalesReportFile -TopWebsiteCandidateCount $TopWebsiteCandidates -LogFile $logFile
    }
    "discover-source-candidates" {
        Invoke-DiscoverSourceCandidates -Municipality $MunicipalityName -OutputFile $sourceDiscoveryFile -LogFile $logFile
    }
    "register-source-candidates" {
        Invoke-RegisterSourceCandidates -CandidatesFile $sourceDiscoveryFile -RegistryFile $sourceRegistryFile -Municipality $MunicipalityName -TopCount $TopSourceCandidates -LogFile $logFile
    }
    "bootstrap-web-pipeline" {
        Invoke-BootstrapWebPipeline -Municipality $MunicipalityName -AreasFile $areasFile -BootstrapAreaFile $bootstrapAreaFile -ContractedFile $contractedFile -CandidatesFile $sourceDiscoveryFile -RegistryFile $sourceRegistryFile -TopCount $TopSourceCandidates -ResolvedFile $realResolvedFile -WorksetFile $sourceWorksetFile -ExtractedCandidatesFile $extractedMemberCandidatesFile -NormalizedMembersFile $normalizedMemberCompaniesFile -ResolvedMembersFile $resolvedMemberCompaniesFile -WebsiteResolutionCandidatesFile $websiteResolutionCandidatesFile -DetailsFile $extractedCompanyDetailsFile -CompanyMasterFile $companyMasterFile -AllOutputFile $webSalesListFile -UsableOutputFile $webSalesUsableFile -ReportOutputFile $webSalesReportFile -TopWebsiteCandidateCount $TopWebsiteCandidates -LogFile $logFile
    }
}
