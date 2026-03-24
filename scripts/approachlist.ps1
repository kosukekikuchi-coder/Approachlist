param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("resolve-areas", "build-company-master", "report-status")]
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
    [string]$LogPath = "logs/run.log"
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
    $candidateRows = New-Object System.Collections.Generic.List[object]

    foreach ($member in $members) {
        $exactMatches = @($details | Where-Object {
            $_.company_name -eq $member.company_name -and $_.municipality -eq $member.municipality
        })
        $sameNameMatches = @($details | Where-Object { $_.company_name -eq $member.company_name })

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
        $score = Get-ScoreResult -Detail $candidate -MatchStatus $candidate.match_status -ScoringConfig $scoring

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

    Write-CsvBom -Rows $outputRows -Path $OutputFile
    Write-LogEntry -Level "info" -Message "build-company-master completed: output=$($outputRows.Count)" -Path $LogFile
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

switch ($Command) {
    "resolve-areas" {
        Invoke-ResolveAreas -AreasFile $areasFile -ContractedFile $contractedFile -OutputFile $resolvedFile -MinimumPopulation $MinPopulation -MaximumPopulation $MaxPopulation -LogFile $logFile
    }
    "build-company-master" {
        Invoke-BuildCompanyMaster -ResolvedFile $resolvedFile -MembersFile $membersFile -DetailsFile $detailsFile -ScoringFile $scoringFile -OutputFile $companyMasterFile -LogFile $logFile
    }
    "report-status" {
        Invoke-ReportStatus -AreasFile $areasFile -MembersFile $membersFile -ResolvedFile $resolvedFile -CompanyMasterFile $companyMasterFile -LogFile $logFile -OutputFile $progressFile
    }
}
