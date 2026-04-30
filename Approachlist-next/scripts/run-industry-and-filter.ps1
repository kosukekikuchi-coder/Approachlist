param(
    [Parameter(Mandatory = $true)]
    [string]$InputCsv,

    [string]$OutputDir = '',

    [switch]$SkipIndustryClassification
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$inputItem = Get-Item -LiteralPath $InputCsv

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Split-Path -Parent $inputItem.FullName
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$baseName = [IO.Path]::GetFileNameWithoutExtension($inputItem.Name)
$industryCsv = Join-Path $OutputDir ($baseName + '_with_industries.csv')
$industryEvidenceCsv = Join-Path $OutputDir ($baseName + '_industry_evidence.csv')
$filteredCsv = Join-Path $OutputDir ($baseName + '_sales_ready.csv')
$filterReportCsv = Join-Path $OutputDir ($baseName + '_filter_report.csv')

if ($SkipIndustryClassification) {
    Copy-Item -LiteralPath $inputItem.FullName -Destination $industryCsv -Force
}
else {
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptDir 'classify-industries.ps1') `
        -InputCsv $inputItem.FullName `
        -OutputCsv $industryCsv `
        -EvidenceCsv $industryEvidenceCsv
}

powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptDir 'filter-sales-list.ps1') `
    -InputCsv $industryCsv `
    -OutputCsv $filteredCsv `
    -ReportCsv $filterReportCsv

$industryRows = @(Import-Csv -Path $industryCsv).Count
$filteredRows = @(Import-Csv -Path $filteredCsv).Count

[pscustomobject]@{
    input_csv = $inputItem.FullName
    industry_csv = $industryCsv
    industry_evidence_csv = if (Test-Path $industryEvidenceCsv) { $industryEvidenceCsv } else { '' }
    filtered_csv = $filteredCsv
    filter_report_csv = $filterReportCsv
    industry_rows = $industryRows
    filtered_rows = $filteredRows
} | Format-List
