#Requires -Version 7.4
<#
.SYNOPSIS
Checks native SEA ARC creation, extraction, binary fidelity and unsafe names.
.DESCRIPTION
Runs only in a disposable directory. ReferenceArchive may be produced by a
separate implementation and is extracted for comparison with the same fixtures.
Keep WorkDirectory when collecting archives for a cross-platform comparison.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArcPath,
    [string]$WorkDirectory,
    [string]$ReferenceArchive,
    [switch]$CheckWindowsNames
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ArcPath = (Resolve-Path -LiteralPath $ArcPath).Path
$keepWork = [bool]$WorkDirectory
if (!$WorkDirectory) {
    # ARC keeps archive paths in historical fixed-size buffers and rejects
    # longer arguments ("Too long argument"). A full 32-digit GUID below a
    # hosted runner's %TEMP% exceeds that limit, so use a short random suffix.
    $WorkDirectory = Join-Path ([IO.Path]::GetTempPath()) ('arc-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
}
if (Test-Path -LiteralPath $WorkDirectory) {
    throw 'Use a new, empty test directory.'
}
$WorkDirectory = [IO.Path]::GetFullPath($WorkDirectory)
$inputDirectory = Join-Path $WorkDirectory 'input files'
$outputDirectory = Join-Path $WorkDirectory 'output files'
$null = New-Item -ItemType Directory -Path $inputDirectory, $outputDirectory
$payloads = [ordered]@{
    'file_id.diz' = [Text.Encoding]::ASCII.GetBytes("Mystic ARC fixture`r`nOldschool interface.`r`n")
    'binary.dat'  = [byte[]](0..255 * 64)
    'repeat.txt'  = [Text.Encoding]::ASCII.GetBytes(('A' * 8192))
    'empty.txt'   = [byte[]]@()
}
try {
    foreach ($name in $payloads.Keys) {
        [IO.File]::WriteAllBytes((Join-Path $inputDirectory $name), $payloads[$name])
    }
    $archive = Join-Path $WorkDirectory 'trial.arc'
    Push-Location $inputDirectory
    try {
        & $ArcPath a $archive @($payloads.Keys)
        if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $archive)) {
            throw 'ARC creation failed.'
        }
    } finally {
        Pop-Location
    }
    $archives = @($archive)
    if ($ReferenceArchive) {
        $archives += (Resolve-Path -LiteralPath $ReferenceArchive).Path
    }
    foreach ($candidate in $archives) {
        Push-Location $outputDirectory
        try {
            & $ArcPath eo $candidate
            if ($LASTEXITCODE -ne 0) {
                throw "ARC extraction failed: $candidate"
            }
            foreach ($name in $payloads.Keys) {
                $file = Join-Path $outputDirectory $name
                if (!(Test-Path -LiteralPath $file) -or ![Linq.Enumerable]::SequenceEqual[byte]($payloads[$name], [IO.File]::ReadAllBytes($file))) {
                    throw "ARC byte comparison failed: $name"
                }
                Remove-Item -LiteralPath $file
            }
        } finally {
            Pop-Location
        }
    }
    if ($CheckWindowsNames) {
        if (!$IsWindows) {
            throw 'Windows filename checks require a native Windows test host.'
        }
        $original = [IO.File]::ReadAllBytes($archive)
        # SEA ARC starts with marker/method bytes followed by a 13-byte basename.
        # Change only the first member name; its payload and CRC stay intact.
        foreach ($unsafe in @('../bad', '..\bad', 'C:bad', 'x:y', 'CON', 'nul.txt', 'COM1.log', 'CON .txt', 'LPT9', 'trailing.', 'space ', 'x/y', 'x\y', 'bad*')) {
            $changed = [byte[]]$original.Clone()
            [Array]::Clear($changed, 2, 13)
            $encoded = [Text.Encoding]::ASCII.GetBytes($unsafe)
            [Array]::Copy($encoded, 0, $changed, 2, $encoded.Length)
            $hostile = Join-Path $WorkDirectory 'unsafe.arc'
            [IO.File]::WriteAllBytes($hostile, $changed)
            Push-Location $outputDirectory
            try {
                $message = & $ArcPath eo $hostile 2>&1
                if ($LASTEXITCODE -eq 0 -or ($message -join "`n") -notmatch 'illegal filename') {
                    throw "An unsafe Windows archive name was not rejected: $unsafe"
                }
                if (@(Get-ChildItem -LiteralPath $outputDirectory -Force).Count -ne 0) {
                    throw 'An unsafe archive wrote a file before rejection.'
                }
                # The nonzero native status was expected and checked above.
                # GitHub's pwsh wrapper exits with LASTEXITCODE, so clear only
                # this handled rejection after every assertion has passed.
                $global:LASTEXITCODE = 0
            } finally {
                Pop-Location
            }
        }
    }
    # Mystic's "Update DIZ" adds a lower-case file_id.diz to an archive that
    # usually holds FILE_ID.DIZ. Windows names ignore case, so the member is
    # replaced there; Unix keeps both names as before.
    $dizArchive = Join-Path $WorkDirectory 'diz.arc'
    $dizDirectory = Join-Path $WorkDirectory 'dizfiles'
    $null = New-Item -ItemType Directory -Path (Join-Path $dizDirectory 'old'), (Join-Path $dizDirectory 'new')
    [IO.File]::WriteAllText((Join-Path $dizDirectory 'old/FILE_ID.DIZ'), "old`r`n")
    [IO.File]::WriteAllText((Join-Path $dizDirectory 'new/file_id.diz'), "new`r`n")
    foreach ($step in 'old/FILE_ID.DIZ', 'new/file_id.diz') {
        $null = & $ArcPath a $dizArchive (Join-Path $dizDirectory $step)
        if ($LASTEXITCODE -ne 0) {
            throw "ARC could not add $step."
        }
    }
    $members = @(& $ArcPath l $dizArchive | Where-Object { $_ -match '^(FILE_ID|file_id)\.(DIZ|diz)\s+\d' } | ForEach-Object { ($_ -split '\s+')[0] })
    $expected = if ($IsWindows) {
        'file_id.diz'
    } else {
        'FILE_ID.DIZ,file_id.diz'
    }
    if (($members -join ',') -cne $expected) {
        throw "Adding file_id.diz left the members $($members -join ',')."
    }
    if ($IsWindows) {
        Push-Location $outputDirectory
        try {
            $null = & $ArcPath eo $dizArchive
            if ($LASTEXITCODE -ne 0 -or [IO.File]::ReadAllText((Join-Path $outputDirectory 'file_id.diz')) -ne "new`r`n") {
                throw 'The replaced FILE_ID.DIZ member does not hold the new content.'
            }
            Remove-Item -LiteralPath (Join-Path $outputDirectory 'file_id.diz')
        } finally {
            Pop-Location
        }
    }
    'PASS native ARC binary/text/empty/multiple-member round trip, case-insensitive member replacement on Windows and optional reference archive/name checks'
} finally {
    if (!$keepWork) {
        Remove-Item -LiteralPath $WorkDirectory -Recurse -Force
    }
}
