#Requires -Version 7.4
<# Packages a qualified native ARC executable, matching source and system PATH entry. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BinaryDirectory,
    [Parameter(Mandatory)][string]$SourceArchive,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [Parameter(Mandatory)][ValidateSet('x86', 'x64')][string]$Architecture
)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'powershell/linux/all/new_windows_msi.ps1') @PSBoundParameters
