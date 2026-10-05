Set-StrictMode -Version Latest

$tosecDemosArchive = "Demos.zip"
$tosecDemosSrc = "Demos"
$topDemosList = "top200-demos.txt"

$tosecGamesArchive = "Games.zip"
$tosecGamesSrc = "Games"

# Extracts $Archive into $DestDir if $SrcDir doesn't already exist locally and
# $Archive is present.
function Assert-Extracted {
    param(
        [string]$SrcDir,
        [string]$Archive,
        [string]$DestDir
    )

    if (Test-Path $SrcDir -PathType Container) { return }
    if (-not (Test-Path $Archive -PathType Leaf)) { return }

    Write-Host "Extracting $Archive..."
    try {
        Expand-Archive -Path $Archive -DestinationPath $DestDir -Force -ErrorAction Stop
    } catch {
        Write-Error "Failed to extract $Archive`: $_"
        exit 1
    }

    if (-not (Test-Path $SrcDir -PathType Container)) {
        Write-Error "Extraction of $Archive did not produce expected folder $SrcDir"
        exit 1
    }
}

# Makes $Name safe to copy onto the FAT32-formatted USB stick used by The
# Spectrum: drops apostrophes/backticks, replaces anything outside a
# conservative ASCII set with "_", trims leading spaces and trailing
# spaces/dots, and truncates to $Max characters. When $KeepExt is set the
# extension is kept intact and excluded from the sanitisation.
function Get-SanitizedName {
    param(
        [string]$Name,
        [int]$Max,
        [bool]$KeepExt
    )
    $base = $Name
    $ext = ""
    if ($KeepExt) {
        $ext = [IO.Path]::GetExtension($Name)
        $base = [IO.Path]::GetFileNameWithoutExtension($Name)
    }
    $base = $base -replace '[''`]', '' -replace '[^\]A-Za-z0-9 ()\[,._&+!#-]', '_'
    $base = $base.TrimStart(' ')
    if ($base.Length -gt $Max - $ext.Length) { $base = $base.Substring(0, $Max - $ext.Length) }
    $base = $base.TrimEnd(' ', '.')
    if (-not $base) { $base = "_" }
    return "$base$ext"
}

# Moves the supported files from the title folder $SrcTitle into $Dest
# (created if needed), sanitising names and avoiding collisions. $Dest is
# removed again if nothing was moved into it.
function Move-TitleFiles {
    param(
        [string]$SrcTitle,
        [string]$Dest
    )

    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    Get-ChildItem -LiteralPath $SrcTitle -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.tap', '.tzx', '.pzx', '.rom', '.szx', '.z80', '.sna', '.m3u' } | ForEach-Object {
        $name = Get-SanitizedName -Name $_.Name -Max 128 -KeepExt $true
        $target = $name
        $n = 2
        while (Test-Path -LiteralPath (Join-Path $Dest $target)) {
            $target = "$([IO.Path]::GetFileNameWithoutExtension($name)) ($n)$([IO.Path]::GetExtension($name))"
            $n++
        }
        if ($target -ne $_.Name) { Write-Host "  Renamed: $($_.Name) -> $target" }
        Move-Item -LiteralPath $_.FullName -Destination (Join-Path $Dest $target)
    }
    if (-not (Get-ChildItem -LiteralPath $Dest -Force)) {
        Remove-Item -LiteralPath $Dest
    }
}

function Invoke-ProcessSource {
    param(
        [string]$Src,
        [string]$Namespace
    )

    if (-not (Test-Path $Src -PathType Container)) {
        Write-Error "Source directory not found: $Src\. Place $Src.zip or the unzipped $Src\ folder from the TOSEC archive here first."
        exit 1
    }

    $folder = ""
    $folder_ext = 0
    Get-ChildItem -Directory -Path $Src | ForEach-Object {
        $file = $_.Name
        if ($file.StartsWith('!')) { return }
        $firstChar = $file.Substring(0, 1)
        $letter = if ($firstChar -match '\d') { '#' } else { $firstChar.ToUpper() }
        if ($folder -ne $letter) {
            $count = 0
            $folder = $letter
        }
        $folder_ext = [math]::Floor($count / 256)
        $count++
        Write-Host "Processing: $file"
        $dest = "THESPECTRUM\$Namespace\$folder$folder_ext\$(Get-SanitizedName -Name $file -Max 64 -KeepExt $false)"
        Move-TitleFiles -SrcTitle $_.FullName -Dest $dest
    }
}

# Moves only the title folders named in $List (one per line, in rank order)
# from $Src into THESPECTRUM\$Namespace\ as a flat list, each folder prefixed
# with its zero-padded position in $List ("001. Title"). Titles missing from
# $Src are skipped with a warning, but still consume their position.
function Invoke-ProcessDemoList {
    param(
        [string]$Src,
        [string]$List,
        [string]$Namespace
    )

    if (-not (Test-Path $Src -PathType Container)) {
        Write-Error "Source directory not found: $Src\. Place $Src.zip or the unzipped $Src\ folder from the TOSEC archive here first."
        exit 1
    }
    if (-not (Test-Path $List -PathType Leaf)) {
        Write-Error "Demo list not found: $List"
        exit 1
    }

    $seq = 0
    foreach ($line in Get-Content -LiteralPath $List) {
        $title = $line.Trim()
        if (-not $title) { continue }
        $seq++
        if (-not (Test-Path -LiteralPath (Join-Path $Src $title) -PathType Container)) {
            Write-Warning "$title (#$seq in $List) not found in $Src\; skipping."
            continue
        }
        Write-Host "Processing: $title"
        $dest = "THESPECTRUM\$Namespace\$(Get-SanitizedName -Name ('{0:D3}. {1}' -f $seq, $title) -Max 64 -KeepExt $false)"
        Move-TitleFiles -SrcTitle (Join-Path $Src $title) -Dest $dest
    }
}

Assert-Extracted -SrcDir $tosecDemosSrc -Archive $tosecDemosArchive -DestDir "."
Invoke-ProcessDemoList -Src $tosecDemosSrc -List $topDemosList -Namespace "TOSEC-Demos"

Assert-Extracted -SrcDir $tosecGamesSrc -Archive $tosecGamesArchive -DestDir "."
Invoke-ProcessSource -Src $tosecGamesSrc -Namespace "TOSEC-Games"

$romsDir = "THESPECTRUM\roms"
New-Item -ItemType Directory -Force -Path $romsDir | Out-Null
# To pin to a specific FBZX release, replace "refs/heads/master" with a commit SHA.
$urls = @(
    "https://github.com/rastersoft/fbzx/raw/refs/heads/master/data/spectrum-roms/128-0.rom",
    "https://github.com/rastersoft/fbzx/raw/refs/heads/master/data/spectrum-roms/128-1.rom",
    "https://github.com/rastersoft/fbzx/raw/refs/heads/master/data/spectrum-roms/48.rom",
    "https://github.com/rastersoft/fbzx/raw/refs/heads/master/data/spectrum-roms/plus3-0.rom",
    "https://github.com/rastersoft/fbzx/raw/refs/heads/master/data/spectrum-roms/plus3-1.rom",
    "https://github.com/rastersoft/fbzx/raw/refs/heads/master/data/spectrum-roms/plus3-2.rom",
    "https://github.com/rastersoft/fbzx/raw/refs/heads/master/data/spectrum-roms/plus3-3.rom"
)
try {
    foreach ($url in $urls) {
        Invoke-WebRequest -Uri $url -OutFile (Join-Path $romsDir (Split-Path -Leaf $url)) -ErrorAction Stop
    }
} catch {
    Write-Error "Failed to download ROM: $_"
    exit 1
}
