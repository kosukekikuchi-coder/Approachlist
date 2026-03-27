param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("resolve-areas", "build-company-master", "report-status", "build-real-sales-list", "run-real-pipeline", "build-source-workset", "extract-member-candidates", "normalize-member-candidates", "extract-company-details", "run-web-pipeline", "discover-source-candidates", "register-source-candidates", "bootstrap-web-pipeline")]
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
    [string]$ExtractedCompanyDetailsPath = "data/out/extracted_company_details.csv",
    [string]$WebSalesListPath = "data/out/web_sales_list.csv",
    [string]$WebSalesUsablePath = "data/out/web_sales_list_usable.csv",
    [string]$WebSalesReportPath = "data/out/web_sales_list_report.csv",
    [string]$MunicipalityName = "",
    [string]$SourceDiscoveryPath = "data/out/source_candidates.csv",
    [int]$TopSourceCandidates = 3,
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

    $csv = @($rowArray | ConvertTo-Csv -NoTypeInformation)
    $encoding = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllLines($Path, $csv, $encoding)
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

    $members = Import-Csv -Path $MembersFile | Where-Object { $selectedMap.ContainsKey($_.municipality) }
    $details = Import-Csv -Path $DetailsFile
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
            '\[$'
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

    if ($value.StartsWith("http://") -or $value.StartsWith("https://")) {
        return $value
    }

    return ""
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
        $searchUrl = "https://html.duckduckgo.com/html/?q={0}" -f [System.Uri]::EscapeDataString($query)
        try {
            $response = Invoke-WebRequest -Uri $searchUrl -UseBasicParsing -TimeoutSec 20
        }
        catch {
            Write-LogEntry -Level "warning" -Message "Failed to discover sources for query: $query" -Path $LogFile
            continue
        }

        foreach ($link in @($response.Links)) {
            $hrefProperty = $link.PSObject.Properties["href"]
            if ($null -eq $hrefProperty) {
                continue
            }

            $url = Resolve-SearchResultUrl -Href ([string]$hrefProperty.Value)
            if ([string]::IsNullOrWhiteSpace($url)) {
                continue
            }

            if ($url -match 'facebook|instagram|wikipedia|tripadvisor|jalan|rakuten|newt\.net|hankyu-travel|asahi\.co\.jp|yeg\.jp|jcci\.or\.jp|kachimai\.jp/article|ameblo\.jp|city\.obihiro\.hokkaido\.jp|ideco-ipo-nisa\.com|jc-seniorclub\.jp|jcb\.co\.jp') {
                continue
            }

            $title = Get-WebPageTitle -Url $url -LogFile $LogFile
            $innerText = ""
            $innerTextProperty = $link.PSObject.Properties["innerText"]
            if ($null -ne $innerTextProperty) {
                $innerText = [string]$innerTextProperty.Value
            }
            $snippet = $innerText

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

    $outputRows = @($candidateRows | Sort-Object -Property @{ Expression = { [int]$_.score }; Descending = $true }, source_org_candidate, source_url)
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
        [string]$DetailsFile,
        [string]$CompanyMasterFile,
        [string]$AllOutputFile,
        [string]$UsableOutputFile,
        [string]$ReportOutputFile,
        [string]$LogFile
    )

    if ([string]::IsNullOrWhiteSpace($Municipality)) {
        throw "MunicipalityName is required for bootstrap-web-pipeline."
    }

    Invoke-BuildBootstrapAreaInput -AreasFile $AreasFile -Municipality $Municipality -OutputFile $BootstrapAreaFile
    Invoke-DiscoverSourceCandidates -Municipality $Municipality -OutputFile $CandidatesFile -LogFile $LogFile
    Invoke-RegisterSourceCandidates -CandidatesFile $CandidatesFile -RegistryFile $RegistryFile -Municipality $Municipality -TopCount $TopCount -LogFile $LogFile
    Invoke-ResolveAreas -AreasFile $BootstrapAreaFile -ContractedFile $ContractedFile -OutputFile $ResolvedFile -MinimumPopulation $MinPopulation -MaximumPopulation $MaxPopulation -LogFile $LogFile
    Invoke-RunWebPipeline -ResolvedFile $ResolvedFile -RegistryFile $RegistryFile -WorksetFile $WorksetFile -CandidatesFile $ExtractedCandidatesFile -NormalizedMembersFile $NormalizedMembersFile -DetailsFile $DetailsFile -CompanyMasterFile $CompanyMasterFile -AllOutputFile $AllOutputFile -UsableOutputFile $UsableOutputFile -ReportOutputFile $ReportOutputFile -LogFile $LogFile
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
            "mozilla.org",
            "www.mozilla.org",
            "wordpress.org",
            "ja.wordpress.org",
            "walkerplus.com",
            "www.walkerplus.com",
            "tabiiro.jp",
            "www.tabiiro.jp",
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
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 20
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
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 20
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
    $normalized = ($normalized -replace '^様\s+', '').Trim()
    $normalized = ($normalized -replace '/\s*$', '').Trim()
    $normalized = ($normalized -replace '\[$', '').Trim()
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
    }

    $patterns = @(
        '(所在地|住所)\s*[:：]?\s*(〒\d{3}-\d{4}\s*)?(北海道|東京都|(?:京都|大阪)府|.{2,4}県).{5,100}?((TEL|電話|FAX|営業時間|営業日|定休日|受付時間|メール|Mail|E-mail|Copyright|©)|$)',
        '(〒\d{3}-\d{4}\s*(北海道|東京都|(?:京都|大阪)府|.{2,4}県).{5,100}?)(?=(TEL|電話|FAX|営業時間|営業日|定休日|受付時間|メール|Mail|E-mail|Copyright|©|$))',
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

function Invoke-ExtractMemberCandidates {
    param(
        [string]$WorksetFile,
        [string]$OutputFile,
        [string]$LogFile
    )

    $worksetRows = @(Import-Csv -Path $WorksetFile)
    $candidates = New-Object System.Collections.Generic.List[object]
    $seenKeys = @{}

    foreach ($source in $worksetRows) {
        try {
            $response = Invoke-WebRequest -Uri $source.source_url -UseBasicParsing -TimeoutSec 20
        }
        catch {
            Write-LogEntry -Level "warning" -Message "Failed to fetch source page: $($source.source_url)" -Path $LogFile
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
    Write-CsvBom -Rows $outputRows -Path $OutputFile
    Write-LogEntry -Level "info" -Message "extract-member-candidates completed: candidates=$($outputRows.Count)" -Path $LogFile
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
    $value = ($value -replace '^宮崎県都城市のコーティングならカークリーンサービスヨシハラ$', 'カークリーンサービスヨシハラ').Trim()
    $value = ($value -replace '^畳の新調、襖の張り替え、障子なら$', 'たたみ・ふすまの油井').Trim()
    $value = ($value -replace '^内装工事に携わるなら都城市の株式会社$', '株式会社快誠企画').Trim()
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

    return ($value -replace '\s+', ' ').Trim()
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
            municipality          = $row.municipality
            source_org            = $row.source_org
            source_url            = $row.source_url
            website_candidate_url = $row.website_candidate_url
            title_snapshot        = $row.title_snapshot
        })
    }

    $outputRows = @($normalizedRows | Sort-Object municipality, source_org, company_name)
    Write-CsvBom -Rows $outputRows -Path $OutputFile
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
    Write-CsvBom -Rows $outputRows -Path $OutputFile
    Write-LogEntry -Level "info" -Message "extract-company-details completed: rows=$($outputRows.Count)" -Path $LogFile
}

function Invoke-RunWebPipeline {
    param(
        [string]$ResolvedFile,
        [string]$RegistryFile,
        [string]$WorksetFile,
        [string]$CandidatesFile,
        [string]$NormalizedMembersFile,
        [string]$DetailsFile,
        [string]$CompanyMasterFile,
        [string]$AllOutputFile,
        [string]$UsableOutputFile,
        [string]$ReportOutputFile,
        [string]$LogFile
    )

    Invoke-BuildSourceWorkset -ResolvedFile $ResolvedFile -RegistryFile $RegistryFile -OutputFile $WorksetFile -LogFile $LogFile
    Invoke-ExtractMemberCandidates -WorksetFile $WorksetFile -OutputFile $CandidatesFile -LogFile $LogFile
    Invoke-NormalizeMemberCandidates -CandidatesFile $CandidatesFile -OutputFile $NormalizedMembersFile -LogFile $LogFile
    Invoke-ExtractCompanyDetails -MembersFile $NormalizedMembersFile -OutputFile $DetailsFile -LogFile $LogFile
    Invoke-BuildCompanyMasterCommand -ResolvedFile $ResolvedFile -MembersFile $NormalizedMembersFile -DetailsFile $DetailsFile -ScoringFile $scoringFile -OutputFile $CompanyMasterFile -LogFile $LogFile
    Invoke-BuildSalesListFromCompanyMaster -CompanyMasterFile $CompanyMasterFile -AllOutputFile $AllOutputFile -UsableOutputFile $UsableOutputFile -ReportOutputFile $ReportOutputFile -LogFile $LogFile
    Write-LogEntry -Level "info" -Message "run-web-pipeline completed" -Path $LogFile
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

$areasFile = Resolve-RepoPath -Path $AreasPath
$contractedFile = Resolve-RepoPath -Path $ContractedPath
$resolvedFile = Resolve-RepoPath -Path $ResolvedAreasPath
$membersFile = Resolve-RepoPath -Path $MemberCompaniesPath
$detailsFile = Resolve-RepoPath -Path $CompanyDetailsPath
$scoringFile = Resolve-RepoPath -Path $ScoringPath
$companyMasterFile = Resolve-RepoPath -Path $CompanyMasterPath
$progressFile = Resolve-RepoPath -Path $ProgressReportPath
$logFile = Resolve-RepoPath -Path $LogPath
$realDirectory = Resolve-RepoPath -Path $RealDataDirectory
$realResolvedFile = Resolve-RepoPath -Path $RealResolvedAreasPath
$realSalesListFile = Resolve-RepoPath -Path $RealSalesListPath
$realSalesUsableFile = Resolve-RepoPath -Path $RealSalesUsablePath
$realSalesReportFile = Resolve-RepoPath -Path $RealSalesReportPath
$sourceRegistryFile = Resolve-RepoPath -Path $SourceRegistryPath
$sourceWorksetFile = Resolve-RepoPath -Path $SourceWorksetPath
$extractedMemberCandidatesFile = Resolve-RepoPath -Path $ExtractedMemberCandidatesPath
$normalizedMemberCompaniesFile = Resolve-RepoPath -Path $NormalizedMemberCompaniesPath
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
    "extract-company-details" {
        Invoke-ExtractCompanyDetails -MembersFile $normalizedMemberCompaniesFile -OutputFile $extractedCompanyDetailsFile -LogFile $logFile
    }
    "run-web-pipeline" {
        Invoke-RunWebPipeline -ResolvedFile $realResolvedFile -RegistryFile $sourceRegistryFile -WorksetFile $sourceWorksetFile -CandidatesFile $extractedMemberCandidatesFile -NormalizedMembersFile $normalizedMemberCompaniesFile -DetailsFile $extractedCompanyDetailsFile -CompanyMasterFile $companyMasterFile -AllOutputFile $webSalesListFile -UsableOutputFile $webSalesUsableFile -ReportOutputFile $webSalesReportFile -LogFile $logFile
    }
    "discover-source-candidates" {
        Invoke-DiscoverSourceCandidates -Municipality $MunicipalityName -OutputFile $sourceDiscoveryFile -LogFile $logFile
    }
    "register-source-candidates" {
        Invoke-RegisterSourceCandidates -CandidatesFile $sourceDiscoveryFile -RegistryFile $sourceRegistryFile -Municipality $MunicipalityName -TopCount $TopSourceCandidates -LogFile $logFile
    }
    "bootstrap-web-pipeline" {
        Invoke-BootstrapWebPipeline -Municipality $MunicipalityName -AreasFile $areasFile -BootstrapAreaFile $bootstrapAreaFile -ContractedFile $contractedFile -CandidatesFile $sourceDiscoveryFile -RegistryFile $sourceRegistryFile -TopCount $TopSourceCandidates -ResolvedFile $realResolvedFile -WorksetFile $sourceWorksetFile -ExtractedCandidatesFile $extractedMemberCandidatesFile -NormalizedMembersFile $normalizedMemberCompaniesFile -DetailsFile $extractedCompanyDetailsFile -CompanyMasterFile $companyMasterFile -AllOutputFile $webSalesListFile -UsableOutputFile $webSalesUsableFile -ReportOutputFile $webSalesReportFile -LogFile $logFile
    }
}
