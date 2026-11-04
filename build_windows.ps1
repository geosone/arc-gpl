#Requires -Version 7.4
<# Builds the native Windows ARC tools on Linux with MinGW-w64. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('x86', 'x64')][string]$Architecture,
    [Parameter(Mandatory)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'powershell/all/build_windows.ps1') @PSBoundParameters
