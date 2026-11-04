#Requires -Version 7.4
<# Tests ARC installation, repair, PATH discovery and removal on a disposable VM. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Package,
    [Parameter(Mandatory)][ValidateSet('x86', 'x64')][string]$Architecture
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (!$IsWindows) {
    throw 'Use a disposable Windows qualification host.'
}
. (Join-Path $PSScriptRoot 'test_windows_path.ps1')
$programs = if ($Architecture -eq 'x86' -and [Environment]::Is64BitOperatingSystem) {
    [Environment]::GetFolderPath('ProgramFilesX86')
} else {
    [Environment]::GetFolderPath('ProgramFiles')
}
$directory = Join-Path $programs 'SEA ARC'
$exe = Join-Path $directory 'arc.exe'
if (Test-Path -LiteralPath $directory) {
    throw 'An existing ARC installation was preserved; use a clean host.'
}
$before = Get-TestMachinePath
$packagePath = (Resolve-Path -LiteralPath $Package).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('arc-msi-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $work
$installed = $false
function Invoke-TestMsi(
    [string]$Mode,
    [string]$Log
) {
    $process = Start-Process msiexec.exe -ArgumentList @($Mode, ('"' + $packagePath + '"'), '/qn', '/norestart', '/L*v', ('"' + (Join-Path $work $Log) + '"')) -Wait -PassThru
    if ($process.ExitCode -notin 0, 3010) {
        throw "Windows Installer failed ($($process.ExitCode)); inspect $work."
    }
}
try {
    Invoke-TestMsi '/i' 'install.log'
    $installed = $true
    Assert-TestToolPath -Directory $directory -Before $before
    Assert-TestToolDiscovery -Executable $exe -WorkingDirectory $work
    & (Join-Path $PSScriptRoot 'test_roundtrip.ps1') -ArcPath $exe -CheckWindowsNames
    $hash = (Get-FileHash -LiteralPath $exe).Hash
    Remove-Item -LiteralPath $exe
    Invoke-TestMsi '/fa' 'repair.log'
    if ((Get-FileHash -LiteralPath $exe).Hash -ne $hash) {
        throw 'MSI repair did not restore the qualified executable.'
    }
    Assert-TestToolPath -Directory $directory -Before $before
    Assert-TestToolDiscovery -Executable $exe -WorkingDirectory $work
    foreach ($name in @('source.tar.gz', 'COPYING', 'LICENSE', 'MINGW-NOTICES.txt', 'GCC-NOTICES.txt')) {
        if (!(Test-Path -LiteralPath (Join-Path $directory $name))) {
            throw 'The MSI omitted source or licence notices.'
        }
    }
} finally {
    if ($installed) {
        Invoke-TestMsi '/x' 'uninstall.log'
        if (Test-Path -LiteralPath $exe) {
            throw 'Uninstall retained the executable.'
        }
        Assert-TestToolPath -Directory $directory -Before $before -Removed
    }
}
'PASS ARC MSI install, native round trip, repair, cmd/PowerShell discovery, exact PATH restoration and uninstall'
