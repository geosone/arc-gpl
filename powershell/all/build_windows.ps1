#Requires -Version 7.4
<#
.SYNOPSIS
Builds ARC and MARC for native Windows without a Cygwin/MSYS runtime.
.DESCRIPTION
Requires Linux, make and the matching MinGW-w64 compiler. Uses a fresh private
source directory so builds for different architectures cannot reuse object files.
OutputDirectory must be new; no existing files or archives are overwritten.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('x86', 'x64')][string]$Architecture,
    [Parameter(Mandatory)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (!$IsLinux) {
    throw 'This cross-build entry requires Linux and MinGW-w64.'
}
$compiler = if ($Architecture -eq 'x86') {
    'i686-w64-mingw32-gcc'
} else {
    'x86_64-w64-mingw32-gcc'
}
foreach ($command in @('make', $compiler)) {
    $null = Get-Command $command -CommandType Application -ErrorAction Stop
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) {
    throw 'OutputDirectory must be new.'
}
$source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$work = Join-Path ([IO.Path]::GetTempPath()) ('arc-build-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $work
try {
    Get-ChildItem -LiteralPath $source -File |
        Where-Object { $_.Extension -in '.c', '.h' -or $_.Name -eq 'Makefile' } |
        Copy-Item -Destination $work
    # Keep implicit-function declarations fatal. Windows time/directory handling
    # is implemented explicitly, rather than linking unavailable Unix routines.
    & make -C $work "CC=$compiler" 'PROG=.exe' `
        'CFLAGS=-O2 -Wall -Werror=implicit-function-declaration -std=gnu17 -DSYSV=1' `
        'TMCLOCK=' '-j2'
    if ($LASTEXITCODE -ne 0) {
        throw 'ARC Windows compilation failed.'
    }
    $null = New-Item -ItemType Directory -Path $OutputDirectory
    foreach ($file in @('arc.exe', 'marc.exe')) {
        Copy-Item -LiteralPath (Join-Path $work $file) -Destination $OutputDirectory
    }
    foreach ($file in @('COPYING', 'LICENSE', 'Readme', 'PACKAGING.md')) {
        Copy-Item -LiteralPath (Join-Path $source $file) -Destination $OutputDirectory
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force
}
