# Baut Token Stats für Windows als einzelne, eigenständige EXE (ohne installierte .NET-Laufzeit).
# Standard ist ARM64; `-Runtime win-x64` für Intel/AMD.
param(
    [ValidateSet('win-arm64', 'win-x64')]
    [string]$Runtime = 'win-arm64'
)

$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot 'TokenStats\TokenStats.csproj'
$output = Join-Path $PSScriptRoot "..\build\windows\$Runtime"

dotnet publish $project -c Release -r $Runtime --self-contained `
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true -p:DebugType=none `
    -o $output
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Get-Item (Join-Path $output 'TokenStats.exe') | Select-Object FullName, Length
