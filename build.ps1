# Base settings
$sourcePath = Get-Location
$tocFile = Join-Path $sourcePath "Simple_Frame_Assistant.toc"

# Check if TOC exists
if (!(Test-Path $tocFile)) {
    Write-Error "Simple_Frame_Assistant.toc not found"
    exit
}

# Read version from TOC
$versionLine = Get-Content $tocFile | Where-Object { $_ -match "^##\s*Version:" }

if (!$versionLine) {
    Write-Error "## Version line not found in TOC"
    exit
}

$Version = ($versionLine -replace "##\s*Version:\s*", "").Trim()

# Paths
$tempFolder = Join-Path $sourcePath "Simple_Frame_Assistant"
$zipPath = Join-Path $sourcePath "Simple_Frame_Assistant-$Version.zip"

# Cleanup old files
if (Test-Path $tempFolder) {
    Remove-Item $tempFolder -Recurse -Force
}
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

try {
    # Create temp addon folder
    New-Item -ItemType Directory -Path $tempFolder | Out-Null

    # Copy .lua files
    Get-ChildItem -Path $sourcePath -Filter *.lua | ForEach-Object {
        Copy-Item $_.FullName -Destination $tempFolder
    }

    # Copy .md files
    Get-ChildItem -Path $sourcePath -Filter *.md | ForEach-Object {
        Copy-Item $_.FullName -Destination $tempFolder
    }
	
    # Copy Icon.tga
    $iconPath = Join-Path $sourcePath "Icon.tga"
    if (Test-Path $iconPath) {
        Copy-Item $iconPath -Destination $tempFolder
    } else {
        Write-Warning "Icon.tga not found"
    }

    # Copy TOC file
    Copy-Item $tocFile -Destination $tempFolder

    # Create ZIP including the Simple_Frame_Assistant folder itself
    Compress-Archive -Path $tempFolder -DestinationPath $zipPath

    Write-Host "Archive created: $zipPath"
}
finally {
    # Remove temp folder after archive is created
    if (Test-Path $tempFolder) {
        Remove-Item $tempFolder -Recurse -Force
    }
}