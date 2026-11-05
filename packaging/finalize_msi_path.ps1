#Requires -Version 7.4
<#
.SYNOPSIS
Authors and verifies an append-only MSI system PATH row, including uninstall.

.DESCRIPTION
Older Ubuntu wixl cannot compile Environment elements at all; 0.106 also omits
their uninstall flag. This script authors the standard MSI Environment table
directly, with identical semantics on either compiler, and schedules the two
standard environment actions. It never replaces the whole PATH value.
https://learn.microsoft.com/windows/win32/msi/environment-table

.PARAMETER Package
The compiled MSI to modify in place.

.PARAMETER Component
The component that owns the PATH row; it is installed and removed with it.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Package,

    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]*$')]
    [string]$Component
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Name "=-*PATH": "=" sets the value on install, "-" removes our part on
# uninstall, "*" selects the machine environment. Value "[~];X" appends X.
$expected = "SystemPath`t=-*PATH`t[~];[INSTALLFOLDER]`t$Component"

$tables = @(& msiinfo tables $Package)
if ($LASTEXITCODE -ne 0) {
    throw 'Cannot inspect the MSI tables.'
}
if ($tables -contains 'Environment') {
    $existingRows = @(& msiinfo export $Package Environment)
    if ($LASTEXITCODE -ne 0 -or @($existingRows | Select-Object -Skip 3 | Where-Object { $_.Trim() }).Count -ne 0) {
        throw 'Refusing to overwrite existing environment rows.'
    }
}

$components = @(& msiinfo export $Package Component)
if ($LASTEXITCODE -ne 0 -or @($components | Where-Object { ($_ -split "`t")[0] -ceq $Component }).Count -ne 1) {
    throw 'The selected PATH owner component is absent or ambiguous.'
}

# Schedule the environment actions BEFORE importing the Environment table.
# With msitools 0.103 and 0.106, changing InstallExecuteSequence after an IDT
# import produced packages that Windows Installer rejects with error 2229
# ("Could not load table 'InstallExecuteSequence'"), reproduced natively with
# LogRotateWin on Windows 10. This order installs and uninstalls correctly.
$sequence = @(& msiinfo export $Package InstallExecuteSequence)
if ($LASTEXITCODE -ne 0) {
    throw 'Cannot inspect MSI action sequencing.'
}
$actions = @(
    @{
        Name     = 'RemoveEnvironmentStrings'
        Sequence = 3300
    },
    @{
        Name     = 'WriteEnvironmentStrings'
        Sequence = 5200
    }
)
foreach ($action in $actions) {
    $existing = @($sequence | Where-Object { ($_ -split "`t")[0] -ceq $action.Name })
    if ($existing.Count -eq 0) {
        $query = 'INSERT INTO `InstallExecuteSequence` (`Action`, `Sequence`) VALUES (''{0}'', {1})' -f $action.Name, $action.Sequence
        & msibuild $Package -q $query
        if ($LASTEXITCODE -ne 0) {
            throw 'Cannot author required environment actions.'
        }
    }
}

$idt = [IO.Path]::GetTempFileName()
try {
    $definition = @(
        "Environment`tName`tValue`tComponent_",
        "s72`tl64`tL255`ts72",
        "Environment`tEnvironment",
        $expected
    ) -join "`r`n"
    [IO.File]::WriteAllText($idt, $definition + "`r`n", [Text.UTF8Encoding]::new($false))
    & msibuild $Package -i $idt
    if ($LASTEXITCODE -ne 0) {
        throw 'Cannot author the MSI PATH table.'
    }
} finally {
    Remove-Item -LiteralPath $idt -Force
}

# Verify the final package rather than trusting the individual commands.
$rows = @(& msiinfo export $Package Environment)
if ($LASTEXITCODE -ne 0) {
    throw 'Cannot inspect the compiled Environment table.'
}
$payload = @($rows | Select-Object -Skip 3 | Where-Object { $_.Trim() })
if ($payload.Count -ne 1 -or $payload[0].TrimEnd("`r") -cne $expected) {
    throw 'The MSI must append one machine PATH member and remove it on uninstall.'
}
$sequence = @(& msiinfo export $Package InstallExecuteSequence)
foreach ($action in $actions) {
    if (@($sequence | Where-Object { ($_ -split "`t")[0] -ceq $action.Name }).Count -ne 1) {
        throw 'The MSI must schedule each environment action exactly once.'
    }
}
