#requires -version 3

$paths = "Private", "Public"
foreach ($path in $paths) {
    $filter = [System.IO.Path]::Combine($PSScriptRoot, $path, '*.ps1')

    Write-Verbose $filter
    Get-ChildItem $filter | ForEach-Object { . $_.FullName }
}
