#Requires -Version 7.4
<#
.SYNOPSIS
Packages native ARC for per-machine Windows installation with a managed PATH entry.
.DESCRIPTION
Requires Linux and wixl. BinaryDirectory must come from build_windows.ps1 for
this architecture. SourceArchive must contain the complete corresponding source.
Uses a new output directory; it does not install anything on the build host.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BinaryDirectory,
    [Parameter(Mandatory)][string]$SourceArchive,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [Parameter(Mandatory)][ValidateSet('x86', 'x64')][string]$Architecture
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (!$IsLinux) {
    throw 'MSI packaging requires Linux and wixl.'
}
$null = Get-Command wixl -CommandType Application -ErrorAction Stop
$binary = (Resolve-Path -LiteralPath $BinaryDirectory).Path
$source = (Resolve-Path -LiteralPath $SourceArchive).Path
$exe = Join-Path $binary 'arc.exe'
$bytes = [IO.File]::ReadAllBytes($exe)
$pe = [BitConverter]::ToInt32($bytes, 0x3c)
$machine = [BitConverter]::ToUInt16($bytes, $pe + 4)
$profiles = @{
    x86 = @{
        Machine   = 0x14c
        Folder    = 'ProgramFilesFolder'
        Win64     = 'no'
        Upgrade   = '8e6d8343-c2b4-4b36-ac5a-673e320c45bd'
        Component = '5fb208b9-f498-4531-9ef1-24500457b495'
    }
    x64 = @{
        Machine   = 0x8664
        Folder    = 'ProgramFiles64Folder'
        Win64     = 'yes'
        Upgrade   = 'e09a1ce9-afab-4f65-b93e-a2c261b065d1'
        Component = '5708a788-0513-45ae-bf20-991db89d9243'
    }
}
$profile = $profiles[$Architecture]
if ($machine -ne $profile.Machine -or [Text.Encoding]::ASCII.GetString($bytes, $pe, 4) -ne "PE`0`0") {
    throw 'The native executable architecture differs from the MSI target.'
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) {
    throw 'Choose a new output directory.'
}
$payload = Join-Path $OutputDirectory 'payload'
$null = New-Item -ItemType Directory -Path $payload
foreach ($name in @('arc.exe', 'COPYING', 'LICENSE', 'Readme', 'PACKAGING.md')) {
    Copy-Item -LiteralPath (Join-Path $binary $name) -Destination $payload
}
Copy-Item -LiteralPath $source -Destination (Join-Path $payload 'source.tar.gz')
Copy-Item -LiteralPath '/usr/share/doc/mingw-w64-common/copyright' -Destination (Join-Path $payload 'MINGW-NOTICES.txt')
Copy-Item -LiteralPath '/usr/share/doc/gcc-mingw-w64-base/copyright' -Destination (Join-Path $payload 'GCC-NOTICES.txt')
$payloadXml = [Security.SecurityElement]::Escape($payload)
# Environment Part=last uses Windows Installer's list semantics. Installation
# appends this directory; repair must not duplicate it; uninstall removes only
# this member. Existing processes retain their inherited environment until restart.
$definition = @"
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product Id="*" Name="SEA ARC $Architecture" Language="1033" Version="5.21.3" Manufacturer="Disconnected by Peer AT" UpgradeCode="$($profile.Upgrade)">
    <Package InstallerVersion="500" Compressed="yes" InstallScope="perMachine" />
    <Media Id="1" Cabinet="arc.cab" EmbedCab="yes" />
    <MajorUpgrade DowngradeErrorMessage="A newer ARC package is already installed." />
    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="$($profile.Folder)">
        <Directory Id="INSTALLFOLDER" Name="SEA ARC">
          <Component Id="Runtime" Guid="$($profile.Component)" Win64="$($profile.Win64)">
            <File Id="ArcExe" Source="$payloadXml/arc.exe" KeyPath="yes" />
            <File Id="SourceCode" Source="$payloadXml/source.tar.gz" />
            <File Id="Copying" Source="$payloadXml/COPYING" />
            <File Id="Licence" Source="$payloadXml/LICENSE" />
            <File Id="UpstreamReadme" Source="$payloadXml/Readme" />
            <File Id="Packaging" Source="$payloadXml/PACKAGING.md" />
            <File Id="MingwNotice" Source="$payloadXml/MINGW-NOTICES.txt" />
            <File Id="GccNotice" Source="$payloadXml/GCC-NOTICES.txt" />

          </Component>
        </Directory>
      </Directory>
    </Directory>
    <Feature Id="Main" Title="ARC command, matching source, notices and system PATH entry" Level="1">
      <ComponentRef Id="Runtime" />
    </Feature>
  </Product>
</Wix>
"@
$wxs = Join-Path $OutputDirectory 'arc.wxs'
[IO.File]::WriteAllText($wxs, $definition)
$package = Join-Path $OutputDirectory "arc-5.21q-3-windows-$Architecture.msi"
& wixl -a $Architecture -o $package $wxs
if ($LASTEXITCODE -ne 0) {
    throw 'ARC MSI packaging failed.'
}
& (Join-Path $PSScriptRoot '../../../packaging/finalize_msi_path.ps1') -Package $package -Component Runtime
[pscustomobject]@{
    Package      = $package
    Architecture = $Architecture
    SHA256       = (Get-FileHash -LiteralPath $package).Hash.ToLowerInvariant()
}
