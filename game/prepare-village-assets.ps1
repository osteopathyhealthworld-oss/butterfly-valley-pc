# Download a small, pinned CC0 subset of Quaternius Medieval Village MegaKit.
# Run from anywhere: powershell -ExecutionPolicy Bypass -File .\godot\butterfly-valley\prepare-village-assets.ps1
$ErrorActionPreference = "Stop"
$sourceRevision = "21104b4045261c28fc312360841ed1a7b0ac8782"
$sourceRoot = "https://raw.githubusercontent.com/J-Ponzo/gltf-medieval-village-megakit/$sourceRevision/glTF"
$manifest = Join-Path $PSScriptRoot "building-assets-manifest.txt"
$destination = Join-Path $PSScriptRoot "assets\buildings\village"
New-Item -ItemType Directory -Force -Path $destination | Out-Null
$downloadCount = 0

foreach ($line in Get-Content -LiteralPath $manifest) {
    $entry = $line.Trim()
    if ($entry.Length -eq 0 -or $entry.StartsWith("#")) { continue }
    $columns = $entry -split "\s+"
    if ($columns.Count -ne 2) { throw "Bad manifest entry: $line" }
    $name = $columns[0]
    $expectedSize = [long]$columns[1]
    if ($name -notmatch '^[A-Za-z0-9_.-]+$') { throw "Unsafe file name: $name" }
    $target = Join-Path $destination $name
    if ((Test-Path -LiteralPath $target) -and (Get-Item -LiteralPath $target).Length -eq $expectedSize) {
        continue
    }
    $temporary = "$target.download"
    try {
        Invoke-WebRequest -Uri "$sourceRoot/$name" -OutFile $temporary -UseBasicParsing
        $received = (Get-Item -LiteralPath $temporary).Length
        if ($received -ne $expectedSize) {
            throw "Size mismatch for $name ($received versus $expectedSize bytes)"
        }
        Move-Item -LiteralPath $temporary -Destination $target -Force
        $downloadCount++
    } catch {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
        throw "Cannot download Quaternius model $name : $_"
    }
}
Write-Host "Quaternius Medieval Village: $downloadCount new files; selected CC0 models are ready for Godot import."

