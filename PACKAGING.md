# Native ARC build and qualification

This branch starts from [gaborbata/arc-gpl](https://github.com/gaborbata/arc-gpl)
commit `661988cd300dd6b2c295d9d467bc110a3bb692d2`. It is the historical SEA ARC
format used by BBS software. FreeArc's `.arc` files use a different format.

The upstream history is retained. In particular, this base includes the Debian
patch import `e1ef8a5` and the compression-output truncation fix `3c0e081`.
The source was compared with Debian's published `arc_5.21q-15` patch series.
Those changes are already present; the truncation fix is additional.
The alternative `hyc/arc` forks reviewed during selection did not provide a
qualified native Windows build. GnuWin32's published Windows port is 5.21j from
2005 and is not used as our binary source.

## Licence

Keep upstream `COPYING`, `LICENSE` and individual source notices. This is GPLv2
code, not a GPLv3 relicensing. When distributing binaries, supply their matching
source and build scripts under the applicable GPL terms. Do not publish an EXE
alone without arranging its corresponding source. No third-party Windows
compatibility implementation was copied into this branch.

## Build

On Linux, install MinGW-w64, make and PowerShell, then run:

```powershell
./build_windows.ps1 -Architecture x86 -OutputDirectory /tmp/arc-win32
./build_windows.ps1 -Architecture x64 -OutputDirectory /tmp/arc-win64
```

Each build copies source inputs into a separate temporary directory; object
files cannot leak between architectures. Both tools remain `arc.exe` and
`marc.exe`. The output directory must not exist. This is a cross-build entry;
PowerShell is a build/test dependency, not an ARC runtime dependency.

The Windows-specific changes cover:

- binary archive and temporary-file streams, including the underlying descriptor;
- MinGW directory enumeration and alphabetical ordering with allocation cleanup;
- local DOS timestamps through explicit 64-bit CRT time functions;
- native TEMP/TMP lookup instead of assuming `/tmp` exists;
- rejecting directory separators, drive/ADS syntax, invalid Windows characters,
  trailing-dot/space aliases and reserved device names in archive members.

Unix behavior stays behind its existing branches. The Windows build does not
link the Unix-only tmclock helper. Implicit-function errors remain fatal.

## Tests and limits

`packaging/test_roundtrip.ps1` creates and compares four members: FILE_ID.DIZ,
all byte values including CR/LF and 0x1a, compressible text and an empty file.
It tests multiple members and directories containing spaces. On Windows,
`-CheckWindowsNames` also mutates valid archive headers and verifies rejection
before any member is written. `-ReferenceArchive` checks an archive made by a
separate build against the same expected bytes. `-WorkDirectory` retains results
for cross-platform exchange and must name a new directory.

Native Windows 10 x86 and x64 round trips and filename-rejection tests passed
on 2026-11-04. Linux native round trips passed as well. Record further distro
interoperability results in the installer archive qualification document.

ARC retains historical limits: a 100-byte path buffer, a 13-byte member-name
field and 8.3 archive-name construction. Use short archive/member basenames;
Unicode and long path support are not qualified. These tests do not constitute
a complete security audit of this legacy parser. MARC compiles but is not yet
covered by the ARC round-trip tests. MSI packaging and actual Mystic/MUTIL
macro/working-directory integration remain separate pending work.

## MSI and command discovery

`new_windows_msi.ps1` packages a qualified native build plus matching source.
MSI version 5.21.2 installs under Program Files/SEA ARC and appends that folder
to machine PATH using Windows Installer list semantics. Repair does not duplicate
the entry and uninstall removes only its own member. Existing shells/services
must be restarted. The portable ZIP does not modify PATH.

`packaging/finalize_msi_path.ps1` checks the compiled Environment table. wixl
0.106 omits the uninstall '-' flag even for Permanent=no; this helper fixes only
that known omission and refuses a row that would replace the entire PATH.
Native x86/x64 tests cover installation, real ARC operations, repair, discovery
from both CMD and PowerShell and exact PATH restoration after removal.
