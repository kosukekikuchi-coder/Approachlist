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
        [System.Collections.IEnumerable]$Rows,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Ensure-ParentDirectory -Path $Path
    $csv = @($Rows | ConvertTo-Csv -NoTypeInformation)
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

    $results = foreach ($area in $areas) {
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
    }

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
    $outputRows = New-Object System.Collections.Generic.List[object]

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
        $detailSource = ""

        if ($matchStatus -eq "exact" -and $null -ne $detail) {
            $address = [string]$detail.address
            $phone = [string]$detail.phone
            $website = [string]$detail.website
            $detailSource = [string]$detail.detail_source_url
        }

        $usable = Get-UsableStatus -CompanyName $member.company_name -Address $address -Phone $phone -Website $website -MatchStatus $matchStatus
        $score = Get-ScoreResult -Detail $detail -MatchStatus $matchStatus -ScoringConfig $scoring

        $outputRows.Add([pscustomobject]@{
            company_name      = $member.company_name
            municipality      = $member.municipality
            address           = $address
            phone             = $phone
            website           = $website
            source_org        = $member.source_org
            source_url        = $member.source_url
            detail_source_url = $detailSource
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

    $areas = Import-Csv -Path $AreasFile
    $members = Import-Csv -Path $MembersFile
    $resolved = Import-Csv -Path $ResolvedFile
    $master = Import-Csv -Path $CompanyMasterFile

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
