param([string]$SourceDirectory = 'C:\Users\Hp\Downloads')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$files = @(
    'Thanushree_kh_Data_Dictionary.xlsx',
    'Koushik_Data_Dictionary Updated Original 1 (1).xlsx',
    'Rajath_Value-List.xlsx',
    'Prajwal_Data_Dictionary_Final (2).xlsx',
    'Skanda_Data_Dictionary_Final.xlsx',
    'Tejaswini_safety_value_list.xlsx',
    'Aditya_Data_Dictionary (4).xlsx',
    'Mahera_Data_Dictionary_FinalLast5.xlsx'
)
$destination = Join-Path $PSScriptRoot '..\docs\review\extracted'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
function Read-Entry($Archive, [string]$Name) {
    $entry = $Archive.GetEntry($Name)
    if ($null -eq $entry) { return $null }
    $reader = [System.IO.StreamReader]::new($entry.Open())
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}
foreach ($file in $files) {
    $path = Join-Path $SourceDirectory $file
    $archive = [System.IO.Compression.ZipFile]::OpenRead($path)
    try {
        [xml]$workbook = Read-Entry $archive 'xl/workbook.xml'
        [xml]$relationships = Read-Entry $archive 'xl/_rels/workbook.xml.rels'
        $targets = @{}
        foreach ($relationship in $relationships.DocumentElement.ChildNodes) {
            $target = [string]$relationship.Target
            if ($target.StartsWith('/')) { $target = $target.TrimStart('/') }
            else { $target = 'xl/' + $target }
            $targets[[string]$relationship.Id] = $target
        }
        $sharedStrings = [System.Collections.Generic.List[string]]::new()
        $sharedText = Read-Entry $archive 'xl/sharedStrings.xml'
        if ($sharedText) {
            [xml]$shared = $sharedText
            foreach ($item in $shared.DocumentElement.ChildNodes) {
                $texts = $item.SelectNodes('.//*[local-name()="t"]')
                $sharedStrings.Add((($texts | ForEach-Object { $_.InnerText }) -join ''))
            }
        }
        $sheets = @()
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add('SOURCE: ' + $file)
        foreach ($sheet in $workbook.SelectNodes('//*[local-name()="sheets"]/*')) {
            $relationshipId = $sheet.GetAttribute('id', 'http://schemas.openxmlformats.org/officeDocument/2006/relationships')
            [xml]$sheetXml = Read-Entry $archive $targets[$relationshipId]
            $rows = @()
            $lines.Add("`nSHEET: " + $sheet.name + ' [state=' + $sheet.state + ']')
            foreach ($row in $sheetXml.SelectNodes('//*[local-name()="sheetData"]/*')) {
                $cells = @()
                foreach ($cell in $row.ChildNodes) {
                    $valueNode = $cell.SelectSingleNode('./*[local-name()="v"]')
                    $value = if ($valueNode) { $valueNode.InnerText } else { '' }
                    if ($cell.t -eq 's') { $value = $sharedStrings[[int]$value] }
                    elseif ($cell.t -eq 'inlineStr') {
                        $value = ($cell.SelectNodes('.//*[local-name()="t"]') | ForEach-Object { $_.InnerText }) -join ''
                    }
                    $formulaNode = $cell.SelectSingleNode('./*[local-name()="f"]')
                    if ($value -ne '' -or $formulaNode) {
                        $cells += [pscustomobject]@{ address = [string]$cell.r; value = $value; formula = $(if ($formulaNode) { $formulaNode.InnerText } else { $null }) }
                    }
                }
                if ($cells.Count -gt 0) {
                    $rows += [pscustomobject]@{ row = [int]$row.r; cells = @($cells) }
                    $lines.Add(($cells | ForEach-Object { $_.address + '=' + ($_.value -replace "`r?`n", ' / ') }) -join ' | ')
                }
            }
            $sheets += [pscustomobject]@{ name = [string]$sheet.name; state = [string]$sheet.state; rows = @($rows) }
        }
        $extras = @()
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName -match '^xl/(comments\d*\.xml|threadedComments/)') {
                $extras += [pscustomobject]@{ part = $entry.FullName; xml = (Read-Entry $archive $entry.FullName) }
                $lines.Add("`nCOMMENTS: " + $entry.FullName + "`n" + (Read-Entry $archive $entry.FullName))
            }
        }
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file)
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName -match '^xl/media/' -and $entry.Name) {
                $mediaPath = [System.IO.Path]::GetFullPath((Join-Path $destination ($baseName + '-' + $entry.Name)))
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $mediaPath, $true)
            }
        }
        [pscustomobject]@{ source = $file; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash; sheets = @($sheets); comments = @($extras) } |
            ConvertTo-Json -Depth 15 | Set-Content -LiteralPath (Join-Path $destination ($baseName + '.json')) -Encoding UTF8
        $lines | Set-Content -LiteralPath (Join-Path $destination ($baseName + '.txt')) -Encoding UTF8
        [pscustomobject]@{ File = $file; Sheets = ($sheets.name -join ', '); Rows = ($sheets | ForEach-Object { $_.rows.Count } | Measure-Object -Sum).Sum; Comments = $extras.Count }
    } finally { $archive.Dispose() }
}
