param(
    [Parameter(Mandatory = $true)]
    [string]$InputCsv,

    [Parameter(Mandatory = $true)]
    [string]$OutputCsv,

    [string]$ReportCsv = ""
)

$ErrorActionPreference = 'Stop'

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

function Test-HasOfficialHp {
    param([string]$Value)

    return -not (
        [string]::IsNullOrWhiteSpace($Value) -or
        $Value -eq '不明' -or
        $Value -eq 'UNKNOWN'
    )
}

$rows = Import-Csv -Path $InputCsv
if (-not $rows -or $rows.Count -eq 0) {
    throw "Input CSV has no rows: $InputCsv"
}

$headerNames = @($rows[0].PSObject.Properties.Name)
$companyHeader = Get-FirstAvailableHeaderName -HeaderNames $headerNames -Candidates @('企業名', 'company_name', 'company')
$officialHpHeader = Get-FirstAvailableHeaderName -HeaderNames $headerNames -Candidates @('公式HP', '公式サイトURL', '公式サイト', 'website', 'official_hp', 'url', 'site_url')
$industry1Header = Get-FirstAvailableHeaderName -HeaderNames $headerNames -Candidates @('業種1', 'industry1')
$industry2Header = Get-FirstAvailableHeaderName -HeaderNames $headerNames -Candidates @('業種2', 'industry2')

if (-not $companyHeader) {
    throw "Could not find company name column. Expected one of: 企業名, company_name, company"
}

if (-not $officialHpHeader) {
    throw "Could not find website column. Expected one of: 公式HP, 公式サイトURL, 公式サイト, website, official_hp, url, site_url"
}

if (-not $industry1Header -or -not $industry2Header) {
    throw "Could not find industry columns. Expected 業種1/業種2 or industry1/industry2"
}

$corpPattern = '株式会社|（株）|\(株\)|㈱|有限会社|（有）|\(有\)|㈲|合同会社|（同）|\(同\)|合資会社|合名会社'
$nonprofitPattern = '特定非営利活動法人|NPO法人|一般社団法人|公益社団法人|一般財団法人|公益財団法人|社会福祉法人|学校法人|宗教法人'
$singleIndustryRemovals = @(
    '宿泊業・飲食サービス業',
    '教育・学習支援業',
    '金融業・保険業',
    '医療・福祉'
)

$resultRows = New-Object System.Collections.Generic.List[object]
$reportRows = New-Object System.Collections.Generic.List[object]

foreach ($row in $rows) {
    $name = [string]$row.$companyHeader
    $officialHp = [string]$row.$officialHpHeader
    $industry1 = [string]$row.$industry1Header
    $industry2 = [string]$row.$industry2Header
    $removeReason = ''

    if (-not (Test-HasOfficialHp $officialHp)) {
        $removeReason = 'no_official_hp'
    }
    else {
        $isNonprofit = $name -match $nonprofitPattern
        $hasCorporateForm = $name -match $corpPattern
        $isPersonal = (-not $hasCorporateForm) -and (-not $isNonprofit)

        if ($isPersonal -or $isNonprofit) {
            $removeReason = 'personal_or_nonprofit'
        }
        elseif (($singleIndustryRemovals -contains $industry1) -and ($industry2 -eq 'なし' -or [string]::IsNullOrWhiteSpace($industry2))) {
            $removeReason = 'excluded_single_industry'
        }
    }

    if ([string]::IsNullOrWhiteSpace($removeReason)) {
        $resultRows.Add($row) | Out-Null
    }

    if ($ReportCsv) {
        $reportRows.Add([pscustomobject]@{
            company = $name
            official_hp = $officialHp
            industry1 = $industry1
            industry2 = $industry2
            action = if ([string]::IsNullOrWhiteSpace($removeReason)) { 'keep' } else { 'remove' }
            reason = $removeReason
        }) | Out-Null
    }
}

$resultRows | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8

if ($ReportCsv) {
    $reportRows | Export-Csv -Path $ReportCsv -NoTypeInformation -Encoding UTF8
}
