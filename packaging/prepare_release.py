"""Package only artifacts from the CI run whose required tests have passed."""
from pathlib import Path
import shutil
import sys
import zipfile

artifacts, output = map(Path, sys.argv[1:])
output.mkdir()
source = None
for architecture in ('x86', 'x64'):
    native = artifacts / f'windows-{architecture}'
    snapshot = (native / 'source.tar.gz').read_bytes()
    if source is not None and source != snapshot:
        raise SystemExit('Architecture source snapshots differ')
    source = snapshot
    name = f'arc-5.21q-3-windows-{architecture}'
    with zipfile.ZipFile(output / (name + '.zip'), 'w', zipfile.ZIP_DEFLATED) as archive:
        for member in ('arc.exe', 'COPYING', 'LICENSE', 'Readme', 'PACKAGING.md', 'source.tar.gz'):
            archive.write(native / member, name + '/' + member)
    packages = list((artifacts / f'msi-{architecture}').glob('*.msi'))
    if len(packages) != 1:
        raise SystemExit('Expected exactly one qualified MSI per architecture')
    shutil.copy2(packages[0], output / packages[0].name)
(output / 'arc-5.21q-3-source.tar.gz').write_bytes(source)
