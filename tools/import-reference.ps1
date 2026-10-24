param([Parameter(Mandatory=$true)][string]$GamePath)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$gameRoot=(Resolve-Path -LiteralPath $GamePath).Path
$archivePath=@((Join-Path $gameRoot 'data\databundles\scripts.zip'),(Join-Path $gameRoot 'data\scripts.zip')) | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
if (!$archivePath) { throw 'scripts.zip was not found in the game data directory' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$wanted=@('components/builder.lua','widgets/widget.lua','widgets/text.lua','widgets/textedit.lua','widgets/textbutton.lua','widgets/button.lua','widgets/image.lua','widgets/imagebutton.lua')
$archive=[IO.Compression.ZipFile]::OpenRead($archivePath)
try {
  foreach($name in $wanted) {
    $entry=$archive.Entries | Where-Object {$_.FullName -eq $name -or $_.FullName -eq ('scripts/'+$name)} | Select-Object -First 1
    if (!$entry) { throw ('Reference script missing: '+$name) }
    $target=Join-Path $projectRoot ('reference/scripts/'+$name)
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$true)
  }
} finally { $archive.Dispose() }
Write-Output 'Imported eight scripts from your own game for local development. reference/ stays ignored; do not publish it.'
