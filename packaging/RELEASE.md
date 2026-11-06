Native Windows x86/x64 ARC packages, based on the historical SEA ARC format.

MSI installs arc.exe under Program Files/SEA ARC and appends that directory to system PATH. Repair does not duplicate the entry; uninstall removes only its own member. Restart existing shells and BBS services to inherit environment changes. Portable ZIP extraction does not change PATH.

5.21q-3: adding a file whose name differs from an existing member only in case (`file_id.diz` and `FILE_ID.DIZ`) now replaces that member on Windows instead of storing a second copy; Mystic's "Update DIZ" relies on this. Upgrades 5.21q-2 in place.

Includes corresponding source and original GPLv2 notices. Required CI tests cover ARC binary/text/multiple-member round trips, unsafe Windows member rejection, Linux/Windows archive exchange, MSI install/repair/uninstall and discovery from CMD/PowerShell. Hosted x86 tests run under WOW64; local native Windows 10 x86 and x64 MSI tests also passed.

Historical limits remain: short 8.3 basenames and paths within the legacy 100-byte buffers. Unicode/long paths and MARC operations are not qualified. This is SEA ARC, not FreeArc. Mystic/MUTIL record configuration is separate. No production deployment is included.
