# Сборка архива релиза RaidMinus для GitHub: release\RaidMinus-<версия>.zip с папкой RaidMinus\ внутри
# (её кладут в Interface\AddOns). В архив не входят docs\, tools\, release\, .git и README.md репозитория.
# Запуск из папки аддона: powershell -ExecutionPolicy Bypass -File tools\release.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$version = (Select-String -Path (Join-Path $root 'RaidMinus.toc') -Pattern '^## Version:\s*(\S+)').Matches[0].Groups[1].Value
if (-not $version) { throw 'нет ## Version в RaidMinus.toc' }

$out = Join-Path $root 'release'
New-Item -ItemType Directory -Force $out | Out-Null
$zipPath = Join-Path $out "RaidMinus-$version.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath }

$skip = @('.git', 'docs', 'tools', 'release')
$files = Get-ChildItem $root -Recurse -File | Where-Object {
    $rel = $_.FullName.Substring($root.Length + 1)
    $top = $rel.Split('\')[0]
    -not ($skip -contains $top) -and $rel -ne '.gitignore' -and $rel -ne 'README.md'
}

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::Open($zipPath, 'Create')
try {
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, "RaidMinus/$rel", 'Optimal')
    }
} finally { $zip.Dispose() }

$sha = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLower()
Write-Host "Готово: $zipPath ($($files.Count) файлов)"
Write-Host "Версия: v$version"
Write-Host "SHA256: $sha"
