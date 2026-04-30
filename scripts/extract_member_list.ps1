param(
    [string[]]$OrganizationName = @(),
    [string[]]$Url = @(),
    [string]$AreaName = '',
    [string]$BaseOutputDir = 'data/out',
    [string]$OutputFileName = '',
    [string]$MemoFileName = '',
    [switch]$PromptInput
)

$ErrorActionPreference = 'Stop'

function New-UnicodeString {
    param([int[]]$CodePoints)

    return (-join ($CodePoints | ForEach-Object { [char]$_ }))
}

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
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }
}

function Get-HtmlEncoding {
    param([byte[]]$Bytes)

    $ascii = [System.Text.Encoding]::ASCII.GetString($Bytes, 0, [Math]::Min($Bytes.Length, 4096))
    $match = [regex]::Match($ascii, '(?i)charset\s*=\s*["'']?([^"''\s/>;]+)')
    if (-not $match.Success) {
        return [System.Text.Encoding]::UTF8
    }

    $charset = $match.Groups[1].Value.Trim().ToLowerInvariant()
    switch -Regex ($charset) {
        '^(shift[-_]?jis|sjis|windows-31j|cp932)$' { return [System.Text.Encoding]::GetEncoding(932) }
        '^utf-?8$' { return [System.Text.Encoding]::UTF8 }
        default { return [System.Text.Encoding]::GetEncoding($charset) }
    }
}

function Get-HtmlUtf8 {
    param([string]$TargetUrl)

    $client = New-Object System.Net.WebClient
    $client.Headers.Add('User-Agent', 'Mozilla/5.0')
    try {
        $bytes = $client.DownloadData($TargetUrl)
        $encoding = Get-HtmlEncoding -Bytes $bytes
        return $encoding.GetString($bytes)
    }
    catch {
        try {
            $response = Invoke-WebRequest -Uri $TargetUrl -UseBasicParsing -MaximumRedirection 5
            return $response.Content
        }
        catch {
            throw "Failed to download $TargetUrl : $($_.Exception.Message)"
        }
    }
    finally {
        $client.Dispose()
    }
}

function Strip-Html {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    $value = $Text -replace '<br\s*/?>', "`n"
    $value = $value -replace '</p>|</div>|</li>|</tr>|</td>|</th>|</h\d>', "`n"
    $value = $value -replace '<[^>]+>', ''
    $value = [System.Net.WebUtility]::HtmlDecode($value)
    $value = $value -replace '[ \t]+', ' '
    $value = $value -replace '\r', ''
    $value = $value -replace '\n{3,}', "`n`n"
    return $value.Trim()
}

function Get-FirstMatchValue {
    param(
        [string]$Text,
        [string]$Pattern
    )

    $match = [regex]::Match($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($match.Success) {
        return $match.Groups[1].Value
    }

    return ''
}

function Write-Utf8BomText {
    param(
        [string]$Path,
        [string[]]$Lines
    )

    Ensure-ParentDirectory -Path $Path
    $encoding = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllLines($Path, $Lines, $encoding)
}

function Normalize-Whitespace {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ''
    }

    return (($Value -replace '\s+', ' ').Trim())
}

function Get-InteractiveValue {
    param(
        [AllowNull()][object]$CurrentValue,
        [string]$PromptMessage
    )

    $values = @(Expand-InputList -Values $CurrentValue)
    if ($values.Count -gt 0) {
        return $values[0]
    }

    return (Read-Host -Prompt $PromptMessage).Trim()
}

function Expand-InputList {
    param([AllowNull()][object]$Values)

    $expanded = New-Object System.Collections.Generic.List[string]
    foreach ($value in @($Values)) {
        if ($null -eq $value) {
            continue
        }

        $text = [string]$value
        foreach ($part in ($text -split '\r?\n|\|\|')) {
            $trimmed = $part.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                $expanded.Add($trimmed)
            }
        }
    }

    return @($expanded)
}

function Get-DefaultAreaName {
    param([string]$InputOrganizationName)

    $value = Normalize-Whitespace $InputOrganizationName
    if ([string]::IsNullOrWhiteSpace($value)) {
        return 'unknown_area'
    }

    $suffixes = @(
        (New-UnicodeString -CodePoints @(0x30ED,0x30FC,0x30BF,0x30EA,0x30FC,0x30AF,0x30E9,0x30D6)),
        (New-UnicodeString -CodePoints @(0x30E9,0x30A4,0x30AA,0x30F3,0x30BA,0x30AF,0x30E9,0x30D6)),
        (New-UnicodeString -CodePoints @(0x9752,0x5E74,0x4F1A,0x8B70,0x6240)),
        (New-UnicodeString -CodePoints @(0x5546,0x5DE5,0x4F1A,0x8B70,0x6240)),
        (New-UnicodeString -CodePoints @(0x5546,0x5DE5,0x4F1A)),
        (New-UnicodeString -CodePoints @(0x30AF,0x30E9,0x30D6))
    )

    foreach ($suffix in $suffixes) {
        if ($value.EndsWith($suffix)) {
            $candidate = $value.Substring(0, $value.Length - $suffix.Length).Trim()
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                return $candidate
            }
        }
    }

    return $value
}

function Get-SafeFileNameSegment {
    param([string]$Value)

    $normalized = Normalize-Whitespace $Value
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return 'member_list'
    }

    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($invalidChar in $invalidChars) {
        $normalized = $normalized.Replace([string]$invalidChar, '_')
    }

    $normalized = $normalized.Replace(' ', '_')
    return $normalized.Trim('_')
}

function Expand-LegalEntityAbbreviation {
    param([string]$CompanyName)

    if ([string]::IsNullOrWhiteSpace($CompanyName)) {
        return ''
    }

    $kabushiki = New-UnicodeString @(0x682A,0x5F0F,0x4F1A,0x793E)
    $yugen = New-UnicodeString @(0x6709,0x9650,0x4F1A,0x793E)
    $godo = New-UnicodeString @(0x5408,0x540C,0x4F1A,0x793E)
    $goshi = New-UnicodeString @(0x5408,0x8CC7,0x4F1A,0x793E)
    $gomei = New-UnicodeString @(0x5408,0x540D,0x4F1A,0x793E)
    $iryou = New-UnicodeString @(0x533B,0x7642,0x6CD5,0x4EBA)
    $ippanZaidan = New-UnicodeString @(0x4E00,0x822C,0x8CA1,0x56E3,0x6CD5,0x4EBA)
    $ippanShadan = New-UnicodeString @(0x4E00,0x822C,0x793E,0x56E3,0x6CD5,0x4EBA)
    $kouekiZaidan = New-UnicodeString @(0x516C,0x76CA,0x8CA1,0x56E3,0x6CD5,0x4EBA)
    $kouekiShadan = New-UnicodeString @(0x516C,0x76CA,0x793E,0x56E3,0x6CD5,0x4EBA)
    $sou = New-UnicodeString @(0x76F8)
    $kabbrev = New-UnicodeString @(0x3231)
    $ybrev = New-UnicodeString @(0x3232)

    $normalized = Normalize-Whitespace $CompanyName
    $normalized = $normalized.Replace('(' + [char]0x682A + ')', $kabushiki)
    $normalized = $normalized.Replace((New-UnicodeString @(0xFF08,0x682A,0xFF09)), $kabushiki)
    $normalized = $normalized.Replace($kabbrev, $kabushiki)
    $normalized = $normalized.Replace('(' + [char]0x6709 + ')', $yugen)
    $normalized = $normalized.Replace((New-UnicodeString @(0xFF08,0x6709,0xFF09)), $yugen)
    $normalized = $normalized.Replace($ybrev, $yugen)
    $normalized = $normalized.Replace('(' + [char]0x5408 + ')', $godo)
    $normalized = $normalized.Replace((New-UnicodeString @(0xFF08,0x5408,0xFF09)), $godo)
    $normalized = $normalized.Replace('(' + [char]0x540C + ')', $godo)
    $normalized = $normalized.Replace((New-UnicodeString @(0xFF08,0x540C,0xFF09)), $godo)
    $normalized = $normalized.Replace('(' + [char]0x8CC7 + ')', $goshi)
    $normalized = $normalized.Replace((New-UnicodeString @(0xFF08,0x8CC7,0xFF09)), $goshi)
    $normalized = $normalized.Replace('(' + [char]0x540D + ')', $gomei)
    $normalized = $normalized.Replace((New-UnicodeString @(0xFF08,0x540D,0xFF09)), $gomei)
    $normalized = $normalized.Replace('(' + [char]0x533B + ')', $iryou)
    $normalized = $normalized.Replace((New-UnicodeString @(0xFF08,0x533B,0xFF09)), $iryou)
    $normalized = $normalized.Replace((New-UnicodeString @(0x0028,0x4E00,0x822C,0x8CA1,0x0029)), $ippanZaidan)
    $normalized = $normalized.Replace((New-UnicodeString @(0xFF08,0x4E00,0x822C,0x8CA1,0xFF09)), $ippanZaidan)
    $normalized = $normalized.Replace((New-UnicodeString @(0x0028,0x4E00,0x822C,0x793E,0x0029)), $ippanShadan)
    $normalized = $normalized.Replace((New-UnicodeString @(0xFF08,0x4E00,0x822C,0x793E,0xFF09)), $ippanShadan)
    $normalized = $normalized.Replace((New-UnicodeString @(0x0028,0x516C,0x76CA,0x8CA1,0x0029)), $kouekiZaidan)
    $normalized = $normalized.Replace((New-UnicodeString @(0xFF08,0x516C,0x76CA,0x8CA1,0xFF09)), $kouekiZaidan)
    $normalized = $normalized.Replace((New-UnicodeString @(0x0028,0x516C,0x76CA,0x793E,0x0029)), $kouekiShadan)
    $normalized = $normalized.Replace((New-UnicodeString @(0xFF08,0x516C,0x76CA,0x793E,0xFF09)), $kouekiShadan)
    $normalized = $normalized.Replace('(' + [char]0x76F8 + ')', $sou)
    $normalized = $normalized.Replace((New-UnicodeString @(0xFF08,0x76F8,0xFF09)), $sou)
    return $normalized
}

function Get-CompanyNameFromLines {
    param([string[]]$Lines)

    if ($null -eq $Lines -or $Lines.Count -eq 0) {
        return ''
    }

    $normalizedLines = @(
        $Lines |
        ForEach-Object { Normalize-Whitespace $_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if ($normalizedLines.Count -eq 0) {
        return ''
    }

    $legalForms = @(
        (New-UnicodeString @(0x682A,0x5F0F,0x4F1A,0x793E)),
        (New-UnicodeString @(0x6709,0x9650,0x4F1A,0x793E)),
        (New-UnicodeString @(0x5408,0x540C,0x4F1A,0x793E)),
        (New-UnicodeString @(0x5408,0x8CC7,0x4F1A,0x793E)),
        (New-UnicodeString @(0x5408,0x540D,0x4F1A,0x793E)),
        (New-UnicodeString @(0x533B,0x7642,0x6CD5,0x4EBA)),
        (New-UnicodeString @(0x4E00,0x822C,0x8CA1,0x56E3,0x6CD5,0x4EBA)),
        (New-UnicodeString @(0x4E00,0x822C,0x793E,0x56E3,0x6CD5,0x4EBA)),
        (New-UnicodeString @(0x516C,0x76CA,0x8CA1,0x56E3,0x6CD5,0x4EBA)),
        (New-UnicodeString @(0x516C,0x76CA,0x793E,0x56E3,0x6CD5,0x4EBA))
    )

    if ($normalizedLines.Count -ge 2 -and $legalForms -contains $normalizedLines[0]) {
        return ($normalizedLines[0] + $normalizedLines[1])
    }

    return $normalizedLines[0]
}

function Get-HeaderTokens {
    return @{
        name = @(
            (New-UnicodeString @(0x6C0F,0x540D)),
            (New-UnicodeString @(0x4F1A,0x54E1,0x540D)),
            (New-UnicodeString @(0x4EE3,0x8868,0x8005)),
            (New-UnicodeString @(0x540D,0x524D))
        )
        company = @(
            (New-UnicodeString @(0x52E4,0x52D9,0x5148)),
            (New-UnicodeString @(0x4F1A,0x793E,0x540D)),
            (New-UnicodeString @(0x4E8B,0x696D,0x6240)),
            (New-UnicodeString @(0x4E8B,0x696D,0x6240,0x540D)),
            (New-UnicodeString @(0x6240,0x5C5E))
        )
        role = @(
            (New-UnicodeString @(0x5F79,0x8077)),
            (New-UnicodeString @(0x8077,0x540D)),
            (New-UnicodeString @(0x80A9,0x66F8))
        )
        classification = @(
            (New-UnicodeString @(0x8077,0x696D,0x5206,0x985E)),
            (New-UnicodeString @(0x696D,0x7A2E)),
            (New-UnicodeString @(0x696D,0x614B))
        )
    }
}

function Normalize-HeaderText {
    param([string]$Value)

    $normalized = Normalize-Whitespace $Value
    $normalized = $normalized.Replace(' ', '')
    $normalized = $normalized.Replace((New-UnicodeString @(0x3000)), '')
    return $normalized
}

function Header-ContainsAnyToken {
    param(
        [string]$HeaderText,
        [string[]]$Tokens
    )

    foreach ($token in $Tokens) {
        if (-not [string]::IsNullOrWhiteSpace($token) -and $HeaderText.Contains($token)) {
            return $true
        }
    }

    return $false
}

function Get-CellTextLines {
    param([string]$CellHtml)

    $text = Strip-Html ($CellHtml -replace '(?i)<br\s*/?>', "`n")
    return @(
        $text -split "`n" |
        ForEach-Object { Normalize-Whitespace $_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Get-PhoneNumberFromText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    $match = [regex]::Match($Text, '(0\d{1,4}-\d{1,4}-\d{3,4})')
    if ($match.Success) {
        return $match.Groups[1].Value
    }

    return ''
}

function Get-FormUrlFromCell {
    param([string]$CellHtml)

    if ([string]::IsNullOrWhiteSpace($CellHtml)) {
        return ''
    }

    $linkMatches = [regex]::Matches(
        $CellHtml,
        '(?i)<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    foreach ($linkMatch in $linkMatches) {
        $href = Normalize-Whitespace $linkMatch.Groups[1].Value
        $anchorText = Normalize-HeaderText (Strip-Html $linkMatch.Groups[2].Value)
        $hrefLower = $href.ToLowerInvariant()
        if (
            $hrefLower.Contains('contact') -or
            $hrefLower.Contains('inquiry') -or
            $hrefLower.Contains('form') -or
            $hrefLower.Contains('toiawase') -or
            $anchorText.Contains((New-UnicodeString @(0x554F,0x3044,0x5408,0x308F,0x305B))) -or
            $anchorText.Contains((New-UnicodeString @(0x304A,0x554F,0x5408,0x305B)))
        ) {
            return $href
        }
    }

    return ''
}

function Resolve-AbsoluteUrl {
    param(
        [string]$BaseUrl,
        [string]$RelativeOrAbsoluteUrl
    )

    $candidate = Normalize-Whitespace $RelativeOrAbsoluteUrl
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        return ''
    }

    try {
        $uri = [System.Uri]$candidate
        if ($uri.IsAbsoluteUri) {
            return $uri.AbsoluteUri
        }
    }
    catch {
    }

    return ([System.Uri]::new([System.Uri]$BaseUrl, $candidate)).AbsoluteUri
}

function Get-DetailFieldValue {
    param(
        [string]$Html,
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Html) -or [string]::IsNullOrWhiteSpace($Label)) {
        return ''
    }

    $escapedLabel = [regex]::Escape($Label)
    $patterns = @(
        "<p>\s*$escapedLabel\s*</p>\s*<p>(.*?)</p>",
        "<p>\s*$escapedLabel\s*</p>\s*<a\b[^>]*>(.*?)</a>"
    )

    foreach ($pattern in $patterns) {
        $value = Get-FirstMatchValue -Text $Html -Pattern $pattern
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return Normalize-Whitespace (Strip-Html $value)
        }
    }

    return ''
}

function Get-DetailFieldHref {
    param(
        [string]$Html,
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Html) -or [string]::IsNullOrWhiteSpace($Label)) {
        return ''
    }

    $escapedLabel = [regex]::Escape($Label)
    $value = Get-FirstMatchValue -Text $Html -Pattern "<p>\s*$escapedLabel\s*</p>\s*<a\b[^>]*href=""([^""]+)"""
    return Normalize-Whitespace $value
}

function Parse-MemberCards {
    param(
        [string]$Html,
        [string]$OrganizationNameValue,
        [string]$AreaNameValue,
        [string]$SourceUrl
    )

    $articleMatches = [regex]::Matches(
        $Html,
        '<article\b[^>]*>(.*?)</article>',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($articleMatch in $articleMatches) {
        $articleHtml = $articleMatch.Groups[1].Value
        $company = Normalize-Whitespace (Strip-Html (Get-FirstMatchValue -Text $articleHtml -Pattern '<p>(.*?)</p>'))
        $detailHref = Normalize-Whitespace (Get-FirstMatchValue -Text $articleHtml -Pattern '(?i)<a\b[^>]*href="([^"]+)"')

        if ([string]::IsNullOrWhiteSpace($company) -or [string]::IsNullOrWhiteSpace($detailHref)) {
            continue
        }

        $detailUrl = Resolve-AbsoluteUrl -BaseUrl $SourceUrl -RelativeOrAbsoluteUrl $detailHref
        $detailHtml = Get-HtmlUtf8 -TargetUrl $detailUrl

        $memberName = Get-DetailFieldValue -Html $detailHtml -Label (New-UnicodeString @(0x4F1A,0x54E1,0x6C0F,0x540D))
        $role = Get-DetailFieldValue -Html $detailHtml -Label (New-UnicodeString @(0x5F79,0x8077))
        $classification = Get-DetailFieldValue -Html $detailHtml -Label (New-UnicodeString @(0x696D,0x52D9,0x5185,0x5BB9))
        $phoneNumber = Get-PhoneNumberFromText -Text (Get-DetailFieldValue -Html $detailHtml -Label (New-UnicodeString @(0x9023,0x7D61,0x5148)))
        $officialHp = Get-DetailFieldHref -Html $detailHtml -Label (New-UnicodeString @(0x516C,0x5F0F,0x30B5,0x30A4,0x30C8))
        $formUrl = Get-FormUrlFromCell -CellHtml $detailHtml

        if ([string]::IsNullOrWhiteSpace($memberName)) {
            continue
        }

        $rows.Add([pscustomobject]@{
            (New-UnicodeString @(0x6240,0x5C5E,0x56E3,0x4F53)) = $OrganizationNameValue
            (New-UnicodeString @(0x4F01,0x696D,0x540D)) = (Expand-LegalEntityAbbreviation -CompanyName $company)
            (New-UnicodeString @(0x4EE3,0x8868,0x8005,0x6C0F,0x540D)) = $memberName
            (New-UnicodeString @(0x6240,0x5728,0x5730,0xFF08,0x5E02,0x533A,0x753A,0x6751,0xFF09)) = $AreaNameValue
            (New-UnicodeString @(0x516C,0x5F0F,0x30B5,0x30A4,0x30C8,0x0055,0x0052,0x004C)) = $officialHp
            (New-UnicodeString @(0x96FB,0x8A71,0x756A,0x53F7)) = $phoneNumber
            (New-UnicodeString @(0x554F,0x3044,0x5408,0x308F,0x305B,0x30D5,0x30A9,0x30FC,0x30E0)) = $formUrl
            (New-UnicodeString @(0x696D,0x7A2E,0x0031)) = $classification
            (New-UnicodeString @(0x696D,0x7A2E,0x0032)) = ''
        })
    }

    if ($rows.Count -gt 0) {
        return $rows
    }

    $headingMatches = [regex]::Matches(
        $Html,
        '(?i)<h3\b[^>]*>(.*?)</h3>(.*?)(?=<h[23]\b|$)',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    $seenHeadings = @{}
    $businessLabel = New-UnicodeString @(0x4E8B,0x696D,0x6240,0x540D)
    $addressLabel = New-UnicodeString @(0x6240,0x5728,0x5730)

    foreach ($headingMatch in $headingMatches) {
        $headingText = Normalize-Whitespace (Strip-Html $headingMatch.Groups[1].Value)
        $bodyHtml = $headingMatch.Groups[2].Value
        $bodyText = Strip-Html $bodyHtml

        if ([string]::IsNullOrWhiteSpace($headingText) -or -not $bodyText.Contains($businessLabel)) {
            continue
        }

        $memberMatch = [regex]::Match($headingText, '^(.+?)\s*[\(\uFF08]')
        $memberName = if ($memberMatch.Success) {
            Normalize-Whitespace $memberMatch.Groups[1].Value
        }
        else {
            $headingText
        }

        $companyMatch = [regex]::Match(
            $bodyText,
            [regex]::Escape($businessLabel) + '\s*(.+?)(?:\r?\n\s*' + [regex]::Escape($addressLabel) + '|\r?\n|$)',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )
        if (-not $companyMatch.Success) {
            continue
        }

        $company = Expand-LegalEntityAbbreviation -CompanyName (Normalize-Whitespace $companyMatch.Groups[1].Value)
        $dedupeKey = '{0}|{1}' -f $memberName, $company
        if ([string]::IsNullOrWhiteSpace($memberName) -or [string]::IsNullOrWhiteSpace($company) -or $seenHeadings.ContainsKey($dedupeKey)) {
            continue
        }

        $seenHeadings[$dedupeKey] = $true
        $officialHp = Normalize-Whitespace (Get-FirstMatchValue -Text $bodyHtml -Pattern '(?i)<a\b[^>]*href="([^"]+)"')
        if (-not [string]::IsNullOrWhiteSpace($officialHp)) {
            $officialHp = Resolve-AbsoluteUrl -BaseUrl $SourceUrl -RelativeOrAbsoluteUrl $officialHp
            if ($officialHp -match ('^' + [regex]::Escape($SourceUrl) + '#')) {
                $officialHp = ''
            }
        }

        $rows.Add([pscustomobject]@{
            (New-UnicodeString @(0x6240,0x5C5E,0x56E3,0x4F53)) = $OrganizationNameValue
            (New-UnicodeString @(0x4F01,0x696D,0x540D)) = $company
            (New-UnicodeString @(0x4EE3,0x8868,0x8005,0x6C0F,0x540D)) = $memberName
            (New-UnicodeString @(0x6240,0x5728,0x5730,0xFF08,0x5E02,0x533A,0x753A,0x6751,0xFF09)) = $AreaNameValue
            (New-UnicodeString @(0x516C,0x5F0F,0x30B5,0x30A4,0x30C8,0x0055,0x0052,0x004C)) = $officialHp
            (New-UnicodeString @(0x96FB,0x8A71,0x756A,0x53F7)) = Get-PhoneNumberFromText -Text $bodyText
            (New-UnicodeString @(0x554F,0x3044,0x5408,0x308F,0x305B,0x30D5,0x30A9,0x30FC,0x30E0)) = Get-FormUrlFromCell -CellHtml $bodyHtml
            (New-UnicodeString @(0x696D,0x7A2E,0x0031)) = ''
            (New-UnicodeString @(0x696D,0x7A2E,0x0032)) = ''
        })
    }

    if ($rows.Count -gt 0) {
        return $rows
    }

    $anchorHtml = $Html
    $memberSectionMarker = New-UnicodeString @(0x6566,0x8CC0,0x0059,0x0045,0x0047,0x30E1,0x30F3,0x30D0,0x30FC)
    $infoSectionMarker = New-UnicodeString @(0x5358,0x4F1A,0x60C5,0x5831)
    $memberSectionStart = $Html.IndexOf($memberSectionMarker)
    if ($memberSectionStart -ge 0) {
        $memberSectionEnd = $Html.IndexOf($infoSectionMarker, $memberSectionStart)
        if ($memberSectionEnd -gt $memberSectionStart) {
            $anchorHtml = $Html.Substring($memberSectionStart, $memberSectionEnd - $memberSectionStart)
        }
    }

    $anchorMatches = [regex]::Matches(
        $anchorHtml,
        '<a\b[^>]*>(.*?)</a>',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    $seen = @{}

    foreach ($anchorMatch in $anchorMatches) {
        $anchorText = Normalize-Whitespace (Strip-Html $anchorMatch.Groups[1].Value)
        $memberMatch = [regex]::Match($anchorText, '^(.+?)\s*[\(\uFF08](.+?)[\)\uFF09]\s*(.*)$')
        if (-not $memberMatch.Success) {
            continue
        }

        $memberName = Normalize-Whitespace $memberMatch.Groups[1].Value
        $company = Expand-LegalEntityAbbreviation -CompanyName (Normalize-Whitespace $memberMatch.Groups[2].Value)
        $classification = Normalize-Whitespace $memberMatch.Groups[3].Value
        $dedupeKey = '{0}|{1}' -f $memberName, $company

        if ([string]::IsNullOrWhiteSpace($memberName) -or [string]::IsNullOrWhiteSpace($company) -or $seen.ContainsKey($dedupeKey)) {
            continue
        }

        $seen[$dedupeKey] = $true
        $rows.Add([pscustomobject]@{
            (New-UnicodeString @(0x6240,0x5C5E,0x56E3,0x4F53)) = $OrganizationNameValue
            (New-UnicodeString @(0x4F01,0x696D,0x540D)) = $company
            (New-UnicodeString @(0x4EE3,0x8868,0x8005,0x6C0F,0x540D)) = $memberName
            (New-UnicodeString @(0x6240,0x5728,0x5730,0xFF08,0x5E02,0x533A,0x753A,0x6751,0xFF09)) = $AreaNameValue
            (New-UnicodeString @(0x516C,0x5F0F,0x30B5,0x30A4,0x30C8,0x0055,0x0052,0x004C)) = ''
            (New-UnicodeString @(0x96FB,0x8A71,0x756A,0x53F7)) = ''
            (New-UnicodeString @(0x554F,0x3044,0x5408,0x308F,0x305B,0x30D5,0x30A9,0x30FC,0x30E0)) = ''
            (New-UnicodeString @(0x696D,0x7A2E,0x0031)) = $classification
            (New-UnicodeString @(0x696D,0x7A2E,0x0032)) = ''
        })
    }

    return $rows
}

function Parse-HeaderlessMemberTables {
    param(
        [string]$Html,
        [string]$OrganizationNameValue,
        [string]$AreaNameValue,
        [string]$SourceUrl
    )

    $tableMatches = [regex]::Matches(
        $Html,
        '<table\b[^>]*>(.*?)</table>',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    $rows = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    foreach ($tableMatch in $tableMatches) {
        $tableHtml = $tableMatch.Groups[1].Value
        $tableText = Normalize-Whitespace (Strip-Html $tableHtml)
        $nameHeader = New-UnicodeString @(0x6C0F,0x540D)
        $classificationHeader = New-UnicodeString @(0x8077,0x696D)
        $workplaceHeader = New-UnicodeString @(0x52E4,0x52D9,0x5148)
        $hasRosterTriples = $tableText.Contains($nameHeader) -and $tableText.Contains($classificationHeader) -and $tableText.Contains($workplaceHeader)
        $rowMatches = [regex]::Matches(
            $tableHtml,
            '<tr\b[^>]*>(.*?)</tr>',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )

        foreach ($rowMatch in $rowMatches) {
            $cellMatches = [regex]::Matches(
                $rowMatch.Groups[1].Value,
                '<td\b[^>]*>(.*?)</td>',
                [System.Text.RegularExpressions.RegexOptions]::Singleline
            )

            if ($cellMatches.Count -lt 3) {
                continue
            }

            if ($hasRosterTriples) {
                for ($cellIndex = 0; $cellIndex -le ($cellMatches.Count - 3); $cellIndex += 3) {
                    $name = Normalize-Whitespace (Strip-Html $cellMatches[$cellIndex].Groups[1].Value)
                    $classification = Normalize-Whitespace (Strip-Html $cellMatches[$cellIndex + 1].Groups[1].Value)
                    $company = Expand-LegalEntityAbbreviation -CompanyName (Normalize-Whitespace (Strip-Html $cellMatches[$cellIndex + 2].Groups[1].Value))

                    if (
                        [string]::IsNullOrWhiteSpace($name) -or
                        [string]::IsNullOrWhiteSpace($company) -or
                        $name.Contains($nameHeader) -or
                        $company.Contains($workplaceHeader)
                    ) {
                        continue
                    }

                    $dedupeKey = '{0}|{1}' -f $name, $company
                    if ($seen.ContainsKey($dedupeKey)) {
                        continue
                    }

                    $seen[$dedupeKey] = $true
                    $officialHp = Normalize-Whitespace (Get-FirstMatchValue -Text $cellMatches[$cellIndex + 2].Groups[1].Value -Pattern '(?i)<a\b[^>]*href="([^"]+)"')
                    if (-not [string]::IsNullOrWhiteSpace($officialHp)) {
                        $officialHp = Resolve-AbsoluteUrl -BaseUrl $SourceUrl -RelativeOrAbsoluteUrl $officialHp
                    }

                    $rows.Add([pscustomobject]@{
                        (New-UnicodeString @(0x6240,0x5C5E,0x56E3,0x4F53)) = $OrganizationNameValue
                        (New-UnicodeString @(0x4F01,0x696D,0x540D)) = $company
                        (New-UnicodeString @(0x4EE3,0x8868,0x8005,0x6C0F,0x540D)) = $name
                        (New-UnicodeString @(0x6240,0x5728,0x5730,0xFF08,0x5E02,0x533A,0x753A,0x6751,0xFF09)) = $AreaNameValue
                        (New-UnicodeString @(0x516C,0x5F0F,0x30B5,0x30A4,0x30C8,0x0055,0x0052,0x004C)) = $officialHp
                        (New-UnicodeString @(0x96FB,0x8A71,0x756A,0x53F7)) = Get-PhoneNumberFromText -Text (Strip-Html $rowMatch.Groups[1].Value)
                        (New-UnicodeString @(0x554F,0x3044,0x5408,0x308F,0x305B,0x30D5,0x30A9,0x30FC,0x30E0)) = ''
                        (New-UnicodeString @(0x696D,0x7A2E,0x0031)) = $classification
                        (New-UnicodeString @(0x696D,0x7A2E,0x0032)) = ''
                    })
                }

                continue
            }

            $name = Normalize-Whitespace (Strip-Html $cellMatches[0].Groups[1].Value)
            $company = Expand-LegalEntityAbbreviation -CompanyName (Normalize-Whitespace (Strip-Html $cellMatches[1].Groups[1].Value))
            $phoneNumber = if ($cellMatches.Count -ge 4) {
                Get-PhoneNumberFromText -Text (Strip-Html $cellMatches[3].Groups[1].Value)
            }
            else {
                Get-PhoneNumberFromText -Text (Strip-Html $rowMatch.Groups[1].Value)
            }

            if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($company)) {
                continue
            }

            $dedupeKey = '{0}|{1}' -f $name, $company
            if ($seen.ContainsKey($dedupeKey)) {
                continue
            }

            $seen[$dedupeKey] = $true
            $officialHp = Normalize-Whitespace (Get-FirstMatchValue -Text $cellMatches[1].Groups[1].Value -Pattern '(?i)<a\b[^>]*href="([^"]+)"')
            if (-not [string]::IsNullOrWhiteSpace($officialHp)) {
                $officialHp = Resolve-AbsoluteUrl -BaseUrl $SourceUrl -RelativeOrAbsoluteUrl $officialHp
            }

            $rows.Add([pscustomobject]@{
                (New-UnicodeString @(0x6240,0x5C5E,0x56E3,0x4F53)) = $OrganizationNameValue
                (New-UnicodeString @(0x4F01,0x696D,0x540D)) = $company
                (New-UnicodeString @(0x4EE3,0x8868,0x8005,0x6C0F,0x540D)) = $name
                (New-UnicodeString @(0x6240,0x5728,0x5730,0xFF08,0x5E02,0x533A,0x753A,0x6751,0xFF09)) = $AreaNameValue
                (New-UnicodeString @(0x516C,0x5F0F,0x30B5,0x30A4,0x30C8,0x0055,0x0052,0x004C)) = $officialHp
                (New-UnicodeString @(0x96FB,0x8A71,0x756A,0x53F7)) = $phoneNumber
                (New-UnicodeString @(0x554F,0x3044,0x5408,0x308F,0x305B,0x30D5,0x30A9,0x30FC,0x30E0)) = ''
                (New-UnicodeString @(0x696D,0x7A2E,0x0031)) = ''
                (New-UnicodeString @(0x696D,0x7A2E,0x0032)) = ''
            })
        }
    }

    return $rows
}

function Find-BestMemberTable {
    param([string]$Html)

    $headerTokens = Get-HeaderTokens
    $tableMatches = [regex]::Matches(
        $Html,
        '<table\b[^>]*>(.*?)</table>',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    $bestTable = $null
    $bestScore = -1

    foreach ($tableMatch in $tableMatches) {
        $tableHtml = $tableMatch.Groups[1].Value
        $rowMatches = [regex]::Matches(
            $tableHtml,
            '<tr\b[^>]*>(.*?)</tr>',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )

        foreach ($rowMatch in $rowMatches) {
            $cellMatches = [regex]::Matches(
                $rowMatch.Groups[1].Value,
                '<t[hd]\b[^>]*>(.*?)</t[hd]>',
                [System.Text.RegularExpressions.RegexOptions]::Singleline
            )

            if ($cellMatches.Count -lt 2) {
                continue
            }

            $score = 0
            foreach ($cellMatch in $cellMatches) {
                $headerText = Normalize-HeaderText (Strip-Html $cellMatch.Groups[1].Value)
                if (Header-ContainsAnyToken -HeaderText $headerText -Tokens $headerTokens.name) { $score += 4 }
                if (Header-ContainsAnyToken -HeaderText $headerText -Tokens $headerTokens.company) { $score += 4 }
                if (Header-ContainsAnyToken -HeaderText $headerText -Tokens $headerTokens.role) { $score += 2 }
                if (Header-ContainsAnyToken -HeaderText $headerText -Tokens $headerTokens.classification) { $score += 2 }
            }

            if ($score -gt $bestScore) {
                $bestScore = $score
                $bestTable = [pscustomobject]@{
                    table_html = $tableHtml
                    header_row_html = $rowMatch.Groups[1].Value
                }
            }
        }
    }

    if ($bestScore -lt 6) {
        throw 'No usable member table was found.'
    }

    return $bestTable
}

function Get-ColumnIndexes {
    param([string]$HeaderRowHtml)

    $headerTokens = Get-HeaderTokens
    $cellMatches = [regex]::Matches(
        $HeaderRowHtml,
        '<t[hd]\b[^>]*>(.*?)</t[hd]>',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    $indexes = @{
        name = -1
        company = -1
        role = -1
        classification = -1
        header_count = $cellMatches.Count
        leading_group_column = $false
    }

    for ($i = 0; $i -lt $cellMatches.Count; $i++) {
        $headerText = Normalize-HeaderText (Strip-Html $cellMatches[$i].Groups[1].Value)
        if ($indexes.name -lt 0 -and (Header-ContainsAnyToken -HeaderText $headerText -Tokens $headerTokens.name)) {
            $indexes.name = $i
            continue
        }
        if ($indexes.company -lt 0 -and (Header-ContainsAnyToken -HeaderText $headerText -Tokens $headerTokens.company)) {
            $indexes.company = $i
            continue
        }
        if ($indexes.role -lt 0 -and (Header-ContainsAnyToken -HeaderText $headerText -Tokens $headerTokens.role)) {
            $indexes.role = $i
            continue
        }
        if ($indexes.classification -lt 0 -and (Header-ContainsAnyToken -HeaderText $headerText -Tokens $headerTokens.classification)) {
            $indexes.classification = $i
            continue
        }
    }

    $firstHeaderText = ''
    if ($cellMatches.Count -gt 0) {
        $firstHeaderText = Normalize-HeaderText (Strip-Html $cellMatches[0].Groups[1].Value)
    }

    if ([string]::IsNullOrWhiteSpace($firstHeaderText) -and $indexes.name -gt 0 -and $indexes.company -gt 0) {
        $indexes.leading_group_column = $true
    }

    return $indexes
}

function Parse-MemberRows {
    param(
        [string]$Html,
        [string]$OrganizationNameValue,
        [string]$AreaNameValue,
        [string]$SourceUrl
    )

    try {
        $bestTable = Find-BestMemberTable -Html $Html
    }
    catch {
        $headerlessRows = Parse-HeaderlessMemberTables -Html $Html -OrganizationNameValue $OrganizationNameValue -AreaNameValue $AreaNameValue -SourceUrl $SourceUrl
        if ($headerlessRows.Count -gt 0) {
            return $headerlessRows
        }

        return (Parse-MemberCards -Html $Html -OrganizationNameValue $OrganizationNameValue -AreaNameValue $AreaNameValue -SourceUrl $SourceUrl)
    }
    $columnIndexes = Get-ColumnIndexes -HeaderRowHtml $bestTable.header_row_html
    $rowMatches = [regex]::Matches(
        $bestTable.table_html,
        '<tr\b[^>]*>(.*?)</tr>',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    $rows = New-Object System.Collections.Generic.List[object]
    $headerSkipped = $false

    foreach ($rowMatch in $rowMatches) {
        $rowHtml = $rowMatch.Groups[1].Value
        $cellMatches = [regex]::Matches(
            $rowHtml,
            '<t[hd]\b[^>]*>(.*?)</t[hd]>',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )

        if ($cellMatches.Count -lt 2) {
            continue
        }

        if (-not $headerSkipped) {
            $headerSkipped = $true
            continue
        }

        $cells = @($cellMatches | ForEach-Object { $_.Groups[1].Value })
        $offset = $cells.Count - [int]$columnIndexes.header_count
        if ($offset -lt 0 -and [bool]$columnIndexes.leading_group_column -and $cells.Count -eq ([int]$columnIndexes.header_count - 1)) {
            $offset = -1
        }

        if ($offset -lt -1) {
            continue
        }

        $nameIndex = [int]$columnIndexes.name + $offset
        $companyIndex = [int]$columnIndexes.company + $offset
        $roleIndex = if ([int]$columnIndexes.role -ge 0) { [int]$columnIndexes.role + $offset } else { -1 }
        $classificationIndex = if ([int]$columnIndexes.classification -ge 0) { [int]$columnIndexes.classification + $offset } else { -1 }

        if ($nameIndex -lt 0 -or $nameIndex -ge $cells.Count -or $companyIndex -lt 0 -or $companyIndex -ge $cells.Count) {
            continue
        }

        $name = Normalize-Whitespace (Strip-Html $cells[$nameIndex])
        $classification = if ($classificationIndex -ge 0 -and $classificationIndex -lt $cells.Count) {
            Normalize-Whitespace (Strip-Html $cells[$classificationIndex])
        }
        else {
            ''
        }

        $companyLines = Get-CellTextLines -CellHtml $cells[$companyIndex]
        if ([string]::IsNullOrWhiteSpace($name) -or $companyLines.Count -eq 0) {
            continue
        }

        $company = Expand-LegalEntityAbbreviation -CompanyName (Get-CompanyNameFromLines -Lines $companyLines)
        $role = ''
        if ($roleIndex -ge 0 -and $roleIndex -lt $cells.Count) {
            $role = Normalize-Whitespace (Strip-Html $cells[$roleIndex])
        }
        elseif ($companyLines.Count -ge 2) {
            $role = $companyLines[1]
        }

        $officialHp = Normalize-Whitespace (Get-FirstMatchValue -Text $cells[$companyIndex] -Pattern '(?i)<a\b[^>]*href="([^"]+)"')
        $phoneNumber = Get-PhoneNumberFromText -Text (Strip-Html $cells[$companyIndex])
        $formUrl = Get-FormUrlFromCell -CellHtml $cells[$companyIndex]
        $industry2 = ''

        $rows.Add([pscustomobject]@{
            (New-UnicodeString @(0x6240,0x5C5E,0x56E3,0x4F53)) = $OrganizationNameValue
            (New-UnicodeString @(0x4F01,0x696D,0x540D)) = $company
            (New-UnicodeString @(0x4EE3,0x8868,0x8005,0x6C0F,0x540D)) = $name
            (New-UnicodeString @(0x6240,0x5728,0x5730,0xFF08,0x5E02,0x533A,0x753A,0x6751,0xFF09)) = $AreaNameValue
            (New-UnicodeString @(0x516C,0x5F0F,0x30B5,0x30A4,0x30C8,0x0055,0x0052,0x004C)) = $officialHp
            (New-UnicodeString @(0x96FB,0x8A71,0x756A,0x53F7)) = $phoneNumber
            (New-UnicodeString @(0x554F,0x3044,0x5408,0x308F,0x305B,0x30D5,0x30A9,0x30FC,0x30E0)) = $formUrl
            (New-UnicodeString @(0x696D,0x7A2E,0x0031)) = $classification
            (New-UnicodeString @(0x696D,0x7A2E,0x0032)) = $industry2
        })
    }

    return $rows
}

$organizationNames = @(Expand-InputList -Values $OrganizationName)
$urls = @(Expand-InputList -Values $Url)

if ($organizationNames.Count -eq 0) {
    $organizationNames = @((Get-InteractiveValue -CurrentValue $null -PromptMessage 'Organization name'))
}

if ($urls.Count -eq 0) {
    $urls = @((Get-InteractiveValue -CurrentValue $null -PromptMessage 'Member list URL'))
}

if ($organizationNames.Count -ne $urls.Count) {
    throw "OrganizationName count ($($organizationNames.Count)) must match Url count ($($urls.Count))."
}

$defaultAreaName = Get-DefaultAreaName -InputOrganizationName $organizationNames[0]
$AreaName = if ($PromptInput) {
    $enteredArea = Read-Host -Prompt ("Area name [{0}]" -f $defaultAreaName)
    if ([string]::IsNullOrWhiteSpace($enteredArea)) { $defaultAreaName } else { $enteredArea.Trim() }
}
elseif ([string]::IsNullOrWhiteSpace($AreaName)) {
    $defaultAreaName
}
else {
    $AreaName.Trim()
}

$areaNameValue = $AreaName
$fileStem = if ($organizationNames.Count -gt 1) {
    Get-SafeFileNameSegment -Value $areaNameValue
}
else {
    Get-SafeFileNameSegment -Value $organizationNames[0]
}

if ([string]::IsNullOrWhiteSpace($OutputFileName)) {
    $OutputFileName = '{0}_members.csv' -f $fileStem
}

if ([string]::IsNullOrWhiteSpace($MemoFileName)) {
    $MemoFileName = '{0}_memo.md' -f $fileStem
}

$resolvedAreaDir = Resolve-RepoPath -Path (Join-Path $BaseOutputDir $areaNameValue)
$resolvedOutputPath = Join-Path $resolvedAreaDir $OutputFileName
$resolvedMemoPath = Join-Path $resolvedAreaDir $MemoFileName

$allRows = New-Object System.Collections.Generic.List[object]
$sourceSummaries = New-Object System.Collections.Generic.List[string]

for ($i = 0; $i -lt $urls.Count; $i++) {
    $organizationNameValue = $organizationNames[$i].Trim()
    $sourceUrl = $urls[$i].Trim()

    if ([string]::IsNullOrWhiteSpace($organizationNameValue) -or [string]::IsNullOrWhiteSpace($sourceUrl)) {
        throw "OrganizationName and Url cannot be blank."
    }

    $html = Get-HtmlUtf8 -TargetUrl $sourceUrl
    $rows = Parse-MemberRows -Html $html -OrganizationNameValue $organizationNameValue -AreaNameValue $areaNameValue -SourceUrl $sourceUrl

    if ($rows.Count -eq 0) {
        throw "No member rows were extracted from $sourceUrl"
    }

    foreach ($row in $rows) {
        $allRows.Add($row)
    }

    $sourceSummaries.Add("- source: $organizationNameValue / $sourceUrl / row_count: $($rows.Count)")
}

$csvLines = @($allRows | ConvertTo-Csv -NoTypeInformation)
Write-Utf8BomText -Path $resolvedOutputPath -Lines $csvLines

$memoLines = @(
    '# Member extraction memo',
    '',
    "- organization_count: $($organizationNames.Count)",
    "- area_name: $areaNameValue",
    "- row_count: $($allRows.Count)",
    '- method: auto-detected member table headers and extracted company, person, classification, role, and official HP when present',
    '',
    'Sources:'
) + @($sourceSummaries) + @(
    '',
    'Notes:',
    '- Output files are always stored under an area-specific folder.',
    '- Company names are normalized to formal legal-entity spellings before CSV export.',
    '- Best-effort extraction for HTML member tables; unusual layouts may still need source-specific tuning.'
)
Write-Utf8BomText -Path $resolvedMemoPath -Lines $memoLines

Write-Output "ORGANIZATIONS=$($organizationNames.Count)"
Write-Output "ROWS=$($allRows.Count)"
Write-Output "OUTPUT=$resolvedOutputPath"
Write-Output "MEMO=$resolvedMemoPath"
