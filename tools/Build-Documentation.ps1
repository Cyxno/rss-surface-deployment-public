<#
.SYNOPSIS
    Generates all documentation from the canonical sources.

.DESCRIPTION
    The only permitted entry point for documentation output. Everything is derived from:
      - docs/source/**            (canonical Markdown + stick templates + Typst template)
      - config/sources.json       (canonical values: versions, models, SKUs, hashes, INF)

    Outputs:
      - docs/generated/stick/RSS-INFO-production.txt and README-AUTOINSTALL.txt
        (placed on the stick via Update-RSSMedia.ps1)
      - docs/generated/RSS_Technical_Build_and_Management_Manual.docx/.pdf
      - docs/generated/RSS_Operations_Manual.docx/.pdf
      - docs/generated/RSS_Test_and_Release_Procedure.docx/.pdf

    Requirements: pandoc >= 3.6 (https://pandoc.org/installing.html), Typst >= 0.15
    (https://typst.app), Windows or Linux. Set the paths via $env:PANDOC and
    $env:TYPST or via PATH. -StickDocsOnly works without those tools.

.EXAMPLE
    .\tools\Build-Documentation.ps1
    .\tools\Build-Documentation.ps1 -StickDocsOnly
#>
[CmdletBinding()]
param(
    [switch]$StickDocsOnly
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repo 'config\sources.json'
$sourceRoot = Join-Path $repo 'docs\source'
$generatedRoot = Join-Path $repo 'docs\generated'
$typstTemplate = Join-Path $sourceRoot 'templates\rss-pandoc.typ'
$referenceDocx = Join-Path $sourceRoot 'templates\reference.docx'
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('rss-docbuild-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $work, $generatedRoot, (Join-Path $generatedRoot 'stick') | Out-Null

$documents = @(
    @{ Md = 'manual\RSS_Technical_Build_and_Management_Manual.md'; Name = 'RSS_Technical_Build_and_Management_Manual' },
    @{ Md = 'operations\RSS_Operations_Manual.md'; Name = 'RSS_Operations_Manual' },
    @{ Md = 'procedure\RSS_Test_and_Release_Procedure.md'; Name = 'RSS_Test_and_Release_Procedure' }
)

# --------------------------------------------------------------- manifest
$mst = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Resolve-ManifestPath([string]$Path) {
    # walks {{a.b.c}} paths through the manifest object; numeric segments index arrays
    $value = $mst
    foreach ($segment in $Path.Split('.')) {
        $prop = $value.PSObject.Properties[$segment]
        if ($prop) {
            $value = $prop.Value
        } elseif ($segment -match '^\d+$') {
            $list = @($value)
            if ([int]$segment -ge $list.Count) { throw "manifest path does not exist: $Path" }
            $value = $list[[int]$segment]
        } else {
            throw "manifest path does not exist: $Path"
        }
        if ($null -eq $value) { throw "manifest path does not exist: $Path" }
    }
    return $value
}

function Get-ModelTable {
    $rows = foreach ($pack in $mst.surfaceDriverPacks) {
        $status = $pack.physicalValidation.status
        $statusText = if ($status -eq 'PHYSICALLY VALIDATED') { "physically validated ($($pack.physicalValidation.date))" } else { "**NOT PHYSICALLY VALIDATED**" }
        "| $($pack.profile) | $($pack.product) | $($pack.cpuVendor) | $($pack.infCount) | $statusText |"
    }
    return @($rows) -join "`n"
}

function Get-ModelSkuTable {
    $rows = foreach ($pack in $mst.surfaceDriverPacks) {
        $status = if ($pack.physicalValidation.status -eq 'PHYSICALLY VALIDATED') { "PHYSICALLY VALIDATED ($($pack.physicalValidation.date))" } else { "NOT PHYSICALLY VALIDATED" }
        $skus = (@($pack.systemSku.supported) | ForEach-Object { "``$_``" }) -join ' · '
        "| $($pack.profile) | $($pack.product) | $skus | $($pack.infCount) | $status |"
    }
    return @($rows) -join "`n"
}

function Get-DriverTable {
    $rows = foreach ($pack in $mst.surfaceDriverPacks) {
        "| $($pack.profile) | ``$($pack.msiFilename)`` | $($pack.releaseDate) | $($pack.infCount) | $($pack.lifecycle.driverFirmwareEol) |"
    }
    return @($rows) -join "`n"
}

function Get-SafetyTable {
    return (@($mst.diskSafety.rules) -join "`n")
}

function Get-RoutingTable {
    $rows = foreach ($pack in $mst.surfaceDriverPacks) {
        "- $($pack.profile): <Images>:\RSSSetup\$($pack.profile) + <Images>:\RSSDriverArchives\$($pack.profile).esd, full package with exactly $($pack.infCount) INF files."
    }
    return @($rows) -join "`n"
}

function Get-PacksTable {
    $rows = foreach ($pack in $mst.surfaceDriverPacks) {
        "- $($pack.profile): $($pack.msiFilename) ($($pack.releaseDate)); $($pack.infCount) INF; archief SHA-256 $($pack.archiveSha256)"
    }
    return @($rows) -join "`n"
}

function Add-TableSoftBreaks([string]$Text) {
    # Adds zero-width spaces after path and name characters inside code spans in
    # table rows, so long tokens (MSI names, SKUs, paths) wrap neatly in narrow
    # table columns without overflowing the cell.
    $zwsp = [char]0x200B
    $lines = $Text -split "`n", 0, 'SimpleMatch'
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\|') {
            $lines[$i] = [regex]::Replace($lines[$i], '`([^`\r\n]+)`', {
                param($m)
                [regex]::Replace($m.Groups[1].Value, '([\\/_.:@-])', ('$1' + $zwsp))
            })
        }
    }
    return ($lines -join "`n")
}

function Expand-Tokens([string]$Text) {
    $text = $Text -replace '\{\{TABLE:MODELS\}\}', (Get-ModelTable)
    $text = $text -replace '\{\{TABLE:MODELSKU\}\}', (Get-ModelSkuTable)
    $text = $text -replace '\{\{TABLE:DRIVERS\}\}', (Get-DriverTable)
    $text = $text -replace '\{\{TABLE:SAFETY\}\}', (Get-SafetyTable)
    $text = $text -replace '\{\{TABLE:ROUTING\}\}', (Get-RoutingTable)
    $text = $text -replace '\{\{TABLE:PACKS\}\}', (Get-PacksTable)
    $text = $text -replace '\{\{TABLE:WINPEOCS\}\}', (@($mst.adk.winpeOptionalComponents) -join ', ')
    $text = $text -replace '\{\{TABLE:INFSLINE\}\}', ((@($mst.surfaceDriverPacks) | ForEach-Object { "$($_.profile) $($_.infCount)" }) -join ', ')
    $text = $text -replace '\{\{TABLE:PROFILELINE\}\}', ((@($mst.surfaceDriverPacks) | ForEach-Object product) -join ', ')

    # {{a.b.c}} paths from the manifest (repeat until stable, for nested tokens)
    for ($i = 0; $i -lt 5; $i++) {
        $before = $text
        $text = [regex]::Replace($text, '\{\{([A-Za-z0-9_.]+)\}\}', {
            param($match)
            $path = $match.Groups[1].Value
            if ($path -like 'TABLE:*') { return $match.Value }
            $v = Resolve-ManifestPath $path
            if ($v -is [bool]) { if ($v) { 'yes' } else { 'no' } } else { "$v" }
        })
        if ($text -eq $before) { break }
    }
    if ($text -match '\{\{') {
        throw "unresolved tokens in documentation: $(([regex]::Matches($text, '\{\{[^}]+\}\}') | Select-Object -First 5 -ExpandProperty Value) -join ', ')"
    }
    return Add-TableSoftBreaks $text
}

# ------------------------------------------------------------ stickdocs
$stickInfo = Expand-Tokens (Get-Content (Join-Path $sourceRoot 'stick\RSS-INFO-production.template.txt') -Raw -Encoding UTF8)
$stickReadme = Expand-Tokens (Get-Content (Join-Path $sourceRoot 'stick\README-AUTOINSTALL.template.txt') -Raw -Encoding UTF8)
[System.IO.File]::WriteAllText((Join-Path $generatedRoot 'stick\RSS-INFO-production.txt'), ($stickInfo -replace "`r?`n", "`r`n"), [System.Text.UTF8Encoding]::new($true))
[System.IO.File]::WriteAllText((Join-Path $generatedRoot 'stick\README-AUTOINSTALL.txt'), ($stickReadme -replace "`r?`n", "`r`n"), [System.Text.UTF8Encoding]::new($true))
Write-Host "[ok] stick documentation generated" -ForegroundColor Green

# ------------------------------------------------------- README block
function Update-ReadmeGeneratedBlock {
    # picks out the elapsed driver date per profile from the release date fields
    $rows = foreach ($pack in $mst.surfaceDriverPacks) {
        $status = if ($pack.physicalValidation.status -eq 'PHYSICALLY VALIDATED') {
            "✅ physically validated ($($pack.physicalValidation.date))"
        } else {
            "❌ **NOT PHYSICALLY VALIDATED**"
        }
        $platform = if ($pack.cpuVendor -eq 'AuthenticAMD') { 'AMD' } else { 'Intel' }
        "| $($pack.profile) | $($pack.product) | $platform | $($pack.releaseDate) | $($pack.infCount) | $status |"
    }
    $bootHash = $mst.media.bootWimSha256
    $medium = "**Production medium:** Windows 11 Pro $($mst.windows.version), build $($mst.windows.build) (LCU $($mst.windows.cumulativeUpdate.kb), $($mst.windows.cumulativeUpdate.released)), $($mst.windows.language) · ADK $($mst.adk.version) · wimlib $($mst.wimlib.version) · boot.wim SHA-256 ``$($bootHash.Substring(0,7))…$($bootHash.Substring(56))``"
    $block = @(
        '| Profile | Model | Platform | Driver package from | INF | Physical status |',
        '|---|---|---|---|---|---|'
    ) + @($rows) + @('', $medium)
    $readmePath = Join-Path $repo 'README.md'
    $readme = Get-Content -LiteralPath $readmePath -Raw -Encoding UTF8
    $pattern = '(?s)(<!-- BEGIN GENERATED:sources[^>]*-->).*(<!-- EIND GENERATED:sources -->)'
    if ($readme -notmatch $pattern) { throw 'README is missing the GENERATED:sources block' }
    $replacement = '$1' + "`n" + ($block -join "`n") + "`n" + '$2'
    $readme = [regex]::new($pattern).Replace($readme, $replacement, 1)
    [System.IO.File]::WriteAllText($readmePath, $readme, [System.Text.UTF8Encoding]::new($false))
    Write-Host "[ok] README version block refreshed" -ForegroundColor Green
}
Update-ReadmeGeneratedBlock

if ($StickDocsOnly) {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    return
}

# ---------------------------------------------------------- locate tools
$pandoc = if ($env:PANDOC) { $env:PANDOC } elseif (Get-Command pandoc -ErrorAction SilentlyContinue) { (Get-Command pandoc).Source } else { throw 'pandoc not found (install pandoc >= 3.6 or set $env:PANDOC)' }
$typst = if ($env:TYPST) { $env:TYPST } elseif (Get-Command typst -ErrorAction SilentlyContinue) { (Get-Command typst).Source } else { throw 'typst not found (install Typst >= 0.15 or set $env:TYPST)' }
Write-Host "pandoc: $pandoc"
Write-Host "typst : $typst"

function Get-MetadataValue([string]$MarkdownPath, [string]$Key) {
    # reads a simple `key: "value"` line from the YAML frontmatter
    foreach ($line in (Get-Content -LiteralPath $MarkdownPath -TotalCount 12 -Encoding UTF8)) {
        if ($line -match "^\s*$Key\s*:\s*`"([^`"]+)`"") { return $Matches[1] }
        if ($line -match "^\s*$Key\s*:\s*([^#\r\n]+)") { return $Matches[1].Trim() }
    }
    throw "metadata '$Key' missing in $MarkdownPath"
}

function Add-RSSDocxHeaderFooter([string]$Path, [string]$Title) {
    # Adds a header (document title) and footer (Page X of Y) to the DOCX
    # generated by pandoc; the title page (first page) stays clean.
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    function Read-ZipEntryText([System.IO.Compression.ZipArchive]$Zip, [string]$EntryName) {
        $entry = $Zip.GetEntry($EntryName)
        if (-not $entry) { throw "zip entry missing: $EntryName" }
        $reader = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    }
    function Write-ZipEntryText([System.IO.Compression.ZipArchive]$Zip, [string]$EntryName, [string]$Text) {
        $existing = $Zip.GetEntry($EntryName)
        if ($existing) { $existing.Delete() }
        $entry = $Zip.CreateEntry($EntryName)
        $writer = New-Object System.IO.StreamWriter($entry.Open(), (New-Object System.Text.UTF8Encoding($false)))
        try { $writer.Write($Text) } finally { $writer.Dispose() }
    }

    $zip = [System.IO.Compression.ZipFile]::Open($Path, 'Update')
    try {
        $escape = { param($s) $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;') }

        $headerXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:p><w:pPr><w:pStyle w:val="Header"/><w:jc w:val="right"/></w:pPr><w:r><w:rPr><w:color w:val="595959"/><w:sz w:val="16"/></w:rPr><w:t xml:space="preserve">TITLEPLACEHOLDER</w:t></w:r></w:p></w:hdr>
'@
        $footerXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:p><w:pPr><w:pStyle w:val="Footer"/><w:tabs><w:tab w:val="center" w:pos="4950"/></w:tabs></w:pPr><w:r><w:rPr><w:color w:val="595959"/><w:sz w:val="16"/></w:rPr><w:t xml:space="preserve">RSS - administration document</w:t></w:r><w:r><w:tab/></w:r><w:r><w:rPr><w:color w:val="595959"/><w:sz w:val="16"/></w:rPr><w:t xml:space="preserve">Page </w:t></w:r><w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:rPr><w:color w:val="595959"/><w:sz w:val="16"/></w:rPr><w:t>1</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r><w:r><w:rPr><w:color w:val="595959"/><w:sz w:val="16"/></w:rPr><w:t xml:space="preserve"> of </w:t></w:r><w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText xml:space="preserve"> NUMPAGES </w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:rPr><w:color w:val="595959"/><w:sz w:val="16"/></w:rPr><w:t>1</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r></w:p></w:ftr>
'@
        $headerXml = $headerXml.Replace('TITLEPLACEHOLDER', (& $escape $Title))

        # 1. content types
        $ctText = Read-ZipEntryText $zip '[Content_Types].xml'
        if ($ctText -notmatch 'header1\.xml') {
            $ctText = $ctText.Replace('</Types>',
                '<Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/><Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/></Types>')
            Write-ZipEntryText $zip '[Content_Types].xml' $ctText
        }

        # 2. relationships
        $relsText = Read-ZipEntryText $zip 'word/_rels/document.xml.rels'
        $relsText = $relsText.Replace('</Relationships>',
            '<Relationship Id="rIdHdrRSS" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/><Relationship Id="rIdFtrRSS" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/></Relationships>')
        Write-ZipEntryText $zip 'word/_rels/document.xml.rels' $relsText

        # 3. header and footer parts
        Write-ZipEntryText $zip 'word/header1.xml' $headerXml
        Write-ZipEntryText $zip 'word/footer1.xml' $footerXml

        # 4. sectPr: references + titlePg (clean title page)
        $docText = Read-ZipEntryText $zip 'word/document.xml'
        if ($docText -notmatch 'rIdHdrRSS') {
            $refs = '<w:headerReference w:type="default" r:id="rIdHdrRSS"/><w:footerReference w:type="default" r:id="rIdFtrRSS"/><w:titlePg/>'
            $regex = [regex]'<w:sectPr(\s[^>]*)?>'
            $match = $regex.Match($docText)
            if (-not $match.Success) { throw 'no sectPr found in document.xml' }
            $docText = $docText.Remove($match.Index, $match.Length).Insert($match.Index, "<w:sectPr$($match.Groups[1].Value)>$refs")
            Write-ZipEntryText $zip 'word/document.xml' $docText
        }
    } finally {
        $zip.Dispose()
    }
}

foreach ($doc in $documents) {
    $mdPath = Join-Path $sourceRoot $doc.Md
    $expandedMd = Expand-Tokens (Get-Content -LiteralPath $mdPath -Raw -Encoding UTF8)
    $workMd = Join-Path $work ($doc.Name + '.md')
    [System.IO.File]::WriteAllText($workMd, $expandedMd, [System.Text.UTF8Encoding]::new($false))

    Write-Host "  DOCX $($doc.Name)..."
    $docxOut = Join-Path $generatedRoot ($doc.Name + '.docx')
    $refArgs = @()
    if (Test-Path -LiteralPath $referenceDocx) { $refArgs = @('--reference-doc', $referenceDocx) }
    & $pandoc $workMd `
        --from gfm+pipe_tables+yaml_metadata_block `
        --to docx `
        --toc --toc-depth=2 `
        @refArgs `
        -o $docxOut
    if ($LASTEXITCODE -ne 0) { throw "pandoc DOCX failed for $($doc.Name)" }
    Add-RSSDocxHeaderFooter -Path $docxOut -Title ((Expand-Tokens (Get-MetadataValue $workMd 'title')))

    Write-Host "  PDF  $($doc.Name)..."
    $typOut = Join-Path $work ($doc.Name + '.typ')
    & $pandoc $workMd `
        --from gfm+pipe_tables+yaml_metadata_block `
        --to typst `
        --template $typstTemplate `
        -V docdate=$($mst.generated) `
        -V title-short=$($doc.Name) `
        -V subtitle-short=$($mst.project.internalName) `
        -o $typOut
    if ($LASTEXITCODE -ne 0) { throw "pandoc typst failed for $($doc.Name)" }
    $pdfOut = Join-Path $generatedRoot ($doc.Name + '.pdf')
    & $typst compile --root / $typOut $pdfOut
    if ($LASTEXITCODE -ne 0) { throw "typst compile failed for $($doc.Name)" }
    Write-Host "[ok] $($doc.Name).docx + .pdf" -ForegroundColor Green
}

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'DOCUMENTATION BUILD COMPLETE' -ForegroundColor Green
