<#
.SYNOPSIS
    Genereert alle documentatie vanuit de canonical bronnen.

.DESCRIPTION
    Enige toegestane toegangspunt voor documentoutput. Alles leidt af uit:
      - docs/source/**            (canonical Markdown + sticktemplates + Typst-sjabloon)
      - config/sources.json       (canonical waarden: versies, modellen, SKU's, hashes, INF)

    Outputs:
      - docs/generated/stick/RSS-INFO-production.txt en LEESMIJ-AUTOINSTALL.txt
        (komen via Update-RSSMedia.ps1 op de stick)
      - docs/generated/RSS_Technische_bouw_en_beheerhandleiding.docx/.pdf
      - docs/generated/RSS_Operationele_handleiding.docx/.pdf
      - docs/generated/RSS_Test_en_releaseprocedure.docx/.pdf

    Vereisten: pandoc >= 3.6 (https://pandoc.org/installing.html), Typst >= 0.15
    (https://typst.app), Windows of Linux. Padinstelling via $env:PANDOC en
    $env:TYPST of in PATH. -StickDocsOnly werkt zonder die tools.

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
    @{ Md = 'handleiding\RSS_Technische_bouw_en_beheerhandleiding.md'; Name = 'RSS_Technische_bouw_en_beheerhandleiding' },
    @{ Md = 'operationeel\RSS_Operationele_handleiding.md'; Name = 'RSS_Operationele_handleiding' },
    @{ Md = 'procedure\RSS_Test_en_releaseprocedure.md'; Name = 'RSS_Test_en_releaseprocedure' }
)

# --------------------------------------------------------------- manifest
$mst = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Resolve-ManifestPath([string]$Path) {
    # loopt {{a.b.c}}-paden door het manifestobject; numerieke segmenten indexeren arrays
    $value = $mst
    foreach ($segment in $Path.Split('.')) {
        $prop = $value.PSObject.Properties[$segment]
        if ($prop) {
            $value = $prop.Value
        } elseif ($segment -match '^\d+$') {
            $list = @($value)
            if ([int]$segment -ge $list.Count) { throw "manifestpad bestaat niet: $Path" }
            $value = $list[[int]$segment]
        } else {
            throw "manifestpad bestaat niet: $Path"
        }
        if ($null -eq $value) { throw "manifestpad bestaat niet: $Path" }
    }
    return $value
}

function Get-ModelTable {
    $rows = foreach ($pack in $mst.surfaceDriverPacks) {
        $status = $pack.physicalValidation.status
        $statusText = if ($status -eq 'PHYSICALLY VALIDATED') { "fysiek gevalideerd ($($pack.physicalValidation.date))" } else { "**NOT PHYSICALLY VALIDATED**" }
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
        "- $($pack.profile): <Images>:\RSSSetup\$($pack.profile) + <Images>:\RSSDriverArchives\$($pack.profile).esd, volledig pakket met exact $($pack.infCount) INF."
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
    # Voegt zero-width spaces toe na map- en naamtekens in code-spans binnen
    # tabelrijen, zodat lange tokens (MSI-namen, SKU's, paden) netjes omlopen
    # in smalle tabelkolommen zonder de cel te overschrijden.
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

    # {{a.b.c}}-paden uit het manifest (herhaal tot stabiel voor geneste tokens)
    for ($i = 0; $i -lt 5; $i++) {
        $before = $text
        $text = [regex]::Replace($text, '\{\{([A-Za-z0-9_.]+)\}\}', {
            param($match)
            $path = $match.Groups[1].Value
            if ($path -like 'TABLE:*') { return $match.Value }
            $v = Resolve-ManifestPath $path
            if ($v -is [bool]) { if ($v) { 'ja' } else { 'nee' } } else { "$v" }
        })
        if ($text -eq $before) { break }
    }
    if ($text -match '\{\{') {
        throw "onopgeloste tokens in documentatie: $(([regex]::Matches($text, '\{\{[^}]+\}\}') | Select-Object -First 5 -ExpandProperty Value) -join ', ')"
    }
    return Add-TableSoftBreaks $text
}

# ------------------------------------------------------------ stickdocs
$stickInfo = Expand-Tokens (Get-Content (Join-Path $sourceRoot 'stick\RSS-INFO-production.template.txt') -Raw -Encoding UTF8)
$stickReadme = Expand-Tokens (Get-Content (Join-Path $sourceRoot 'stick\LEESMIJ-AUTOINSTALL.template.txt') -Raw -Encoding UTF8)
[System.IO.File]::WriteAllText((Join-Path $generatedRoot 'stick\RSS-INFO-production.txt'), ($stickInfo -replace "`r?`n", "`r`n"), [System.Text.UTF8Encoding]::new($true))
[System.IO.File]::WriteAllText((Join-Path $generatedRoot 'stick\LEESMIJ-AUTOINSTALL.txt'), ($stickReadme -replace "`r?`n", "`r`n"), [System.Text.UTF8Encoding]::new($true))
Write-Host "[ok] stickdocumentatie gegenereerd" -ForegroundColor Green

# ------------------------------------------------------- README-blok
function Update-ReadmeGeneratedBlock {
    # vist de verstreken driverdatum per profiel op uit de releaseDatum-velden
    $rows = foreach ($pack in $mst.surfaceDriverPacks) {
        $status = if ($pack.physicalValidation.status -eq 'PHYSICALLY VALIDATED') {
            "✅ fysiek gevalideerd ($($pack.physicalValidation.date))"
        } else {
            "❌ **NOT PHYSICALLY VALIDATED**"
        }
        $platform = if ($pack.cpuVendor -eq 'AuthenticAMD') { 'AMD' } else { 'Intel' }
        "| $($pack.profile) | $($pack.product) | $platform | $($pack.releaseDate) | $($pack.infCount) | $status |"
    }
    $bootHash = $mst.media.bootWimSha256
    $medium = "**Productiemedium:** Windows 11 Pro $($mst.windows.version), build $($mst.windows.build) (LCU $($mst.windows.cumulativeUpdate.kb), $($mst.windows.cumulativeUpdate.released)), $($mst.windows.language) · ADK $($mst.adk.version) · wimlib $($mst.wimlib.version) · boot.wim SHA-256 ``$($bootHash.Substring(0,7))…$($bootHash.Substring(56))``"
    $block = @(
        '| Profiel | Model | Platform | Driverpakket van | INF | Fysieke status |',
        '|---|---|---|---|---|---|'
    ) + @($rows) + @('', $medium)
    $readmePath = Join-Path $repo 'README.md'
    $readme = Get-Content -LiteralPath $readmePath -Raw -Encoding UTF8
    $pattern = '(?s)(<!-- BEGIN GENERATED:sources[^>]*-->).*(<!-- EIND GENERATED:sources -->)'
    if ($readme -notmatch $pattern) { throw 'README mist het GENERATED:sources-blok' }
    $replacement = '$1' + "`n" + ($block -join "`n") + "`n" + '$2'
    $readme = [regex]::new($pattern).Replace($readme, $replacement, 1)
    [System.IO.File]::WriteAllText($readmePath, $readme, [System.Text.UTF8Encoding]::new($false))
    Write-Host "[ok] README-versieblok ververst" -ForegroundColor Green
}
Update-ReadmeGeneratedBlock

if ($StickDocsOnly) {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    return
}

# ---------------------------------------------------------- tools vinden
$pandoc = if ($env:PANDOC) { $env:PANDOC } elseif (Get-Command pandoc -ErrorAction SilentlyContinue) { (Get-Command pandoc).Source } else { throw 'pandoc niet gevonden (installeer pandoc >= 3.6 of zet $env:PANDOC)' }
$typst = if ($env:TYPST) { $env:TYPST } elseif (Get-Command typst -ErrorAction SilentlyContinue) { (Get-Command typst).Source } else { throw 'typst niet gevonden (installeer Typst >= 0.15 of zet $env:TYPST)' }
Write-Host "pandoc: $pandoc"
Write-Host "typst : $typst"

function Get-MetadataValue([string]$MarkdownPath, [string]$Key) {
    # leest een eenvoudige `key: "value"`-regel uit de YAML-frontmatter
    foreach ($line in (Get-Content -LiteralPath $MarkdownPath -TotalCount 12 -Encoding UTF8)) {
        if ($line -match "^\s*$Key\s*:\s*`"([^`"]+)`"") { return $Matches[1] }
        if ($line -match "^\s*$Key\s*:\s*([^#\r\n]+)") { return $Matches[1].Trim() }
    }
    throw "metadata '$Key' ontbreekt in $MarkdownPath"
}

function Add-RSSDocxHeaderFooter([string]$Path, [string]$Title) {
    # Voegt koptekst (documenttitel) en voettekst (Pagina X van Y) toe aan het
    # door pandoc gegenereerde DOCX; voorpagina (eerste pagina) blijft schoon.
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    function Read-ZipEntryText([System.IO.Compression.ZipArchive]$Zip, [string]$EntryName) {
        $entry = $Zip.GetEntry($EntryName)
        if (-not $entry) { throw "zip-entry ontbreekt: $EntryName" }
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
<w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:p><w:pPr><w:pStyle w:val="Footer"/><w:tabs><w:tab w:val="center" w:pos="4950"/></w:tabs></w:pPr><w:r><w:rPr><w:color w:val="595959"/><w:sz w:val="16"/></w:rPr><w:t xml:space="preserve">RSS - intern beheerdocument</w:t></w:r><w:r><w:tab/></w:r><w:r><w:rPr><w:color w:val="595959"/><w:sz w:val="16"/></w:rPr><w:t xml:space="preserve">Pagina </w:t></w:r><w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:rPr><w:color w:val="595959"/><w:sz w:val="16"/></w:rPr><w:t>1</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r><w:r><w:rPr><w:color w:val="595959"/><w:sz w:val="16"/></w:rPr><w:t xml:space="preserve"> van </w:t></w:r><w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText xml:space="preserve"> NUMPAGES </w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:rPr><w:color w:val="595959"/><w:sz w:val="16"/></w:rPr><w:t>1</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r></w:p></w:ftr>
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

        # 3. header- en footeronderdelen
        Write-ZipEntryText $zip 'word/header1.xml' $headerXml
        Write-ZipEntryText $zip 'word/footer1.xml' $footerXml

        # 4. sectPr: verwijzingen + titlePg (schone voorpagina)
        $docText = Read-ZipEntryText $zip 'word/document.xml'
        if ($docText -notmatch 'rIdHdrRSS') {
            $refs = '<w:headerReference w:type="default" r:id="rIdHdrRSS"/><w:footerReference w:type="default" r:id="rIdFtrRSS"/><w:titlePg/>'
            $regex = [regex]'<w:sectPr(\s[^>]*)?>'
            $match = $regex.Match($docText)
            if (-not $match.Success) { throw 'geen sectPr in document.xml gevonden' }
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
    if ($LASTEXITCODE -ne 0) { throw "pandoc DOCX faalde voor $($doc.Name)" }
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
    if ($LASTEXITCODE -ne 0) { throw "pandoc typst faalde voor $($doc.Name)" }
    $pdfOut = Join-Path $generatedRoot ($doc.Name + '.pdf')
    & $typst compile --root / $typOut $pdfOut
    if ($LASTEXITCODE -ne 0) { throw "typst compile faalde voor $($doc.Name)" }
    Write-Host "[ok] $($doc.Name).docx + .pdf" -ForegroundColor Green
}

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'DOCUMENTATIE-BUILD VOLTOOID' -ForegroundColor Green
