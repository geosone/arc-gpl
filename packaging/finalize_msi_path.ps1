#Requires -Version 7.4
<# Verifies one append-only system PATH row and corrects wixl 0.106 uninstall flags. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Package,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*$')][string]$Component
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Get-PathRow {
    $table = @(& msiinfo export $Package Environment)
    if ($LASTEXITCODE -ne 0) {
        throw 'Cannot inspect the compiled Environment table.'
    }
    $rows = @($table | Select-Object -Skip 3 | Where-Object { $_.Trim() } | ForEach-Object { , ($_ -split "`t") })
    if ($rows.Count -ne 1 -or $rows[0].Count -ne 4) {
        throw 'Expected exactly one managed environment row.'
    }
    $row = $rows[0]
    if ($row[2] -cne '[~];[INSTALLFOLDER]' -or $row[3] -cne $Component) {
        throw 'Refusing a PATH row that replaces the whole value or belongs to another component.'
    }
    return , $row
}
$row = Get-PathRow
if ($row[1] -ceq '=*PATH') {
    # wixl 0.106 emits no '-' flag for Permanent=no. MSI requires this flag to
    # remove the appended list member on uninstall. Keep the WiX declaration
    # correct and normalize only this known compiler omission, never its value.
    # https://learn.microsoft.com/windows/win32/msi/environment-table
    $query = 'UPDATE `Environment` SET `Name` = ''=-*PATH'' WHERE `Name` = ''=*PATH'' AND `Component_` = ''{0}''' -f $Component
    & msibuild $Package -q $query
    if ($LASTEXITCODE -ne 0) {
        throw 'Cannot author the required uninstall flag.'
    }
}
$row = Get-PathRow
if ($row[1] -cne '=-*PATH') {
    throw 'The MSI PATH row must set on install, remove on uninstall and use machine scope.'
}
