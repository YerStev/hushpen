#!/bin/bash
# Source review gate, not OS network isolation. See docs/TECHNICAL.md.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - "${1:-}" <<'PY'
import hashlib,json,re,sys
from pathlib import Path
root=Path('.build/checkouts/desert-ant-core')
assert root.is_dir(), 'Resolve SDK dependencies first'
source=root/'Sources'
pattern=re.compile(r'URLSession|HTTPClient|URLRequest|sendBeacon|NWConnection|CFSocket|socket\(|\bhttp(?:GET|POST|Request)\b')
files=[]
for p in source.rglob('*.swift'):
    code='\n'.join(line for line in p.read_text().splitlines() if not line.lstrip().startswith('//'))
    if pattern.search(code): files.append(str(p.relative_to(root)))
files.sort()
assert all(Path(p).parts[1] in {'Usage','ModelStore','PlatformSupport','HostBridge','CoreAndroidTests'} for p in files), 'New networking module requires review'
reviewed=sorted(p for module in ['Usage','ModelStore','PlatformSupport','HostBridge','CoreAndroidTests'] for p in (source/module).glob('*.swift'))
reviewed += [source/'Voz/Catalog.swift',source/'Voz/Voz.swift']
hashes={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in reviewed}
baseline=Path('scripts/sdk-network-baseline.txt')
hashfile=Path('scripts/sdk-reviewed-sha256.json')
pins=json.loads(Path('Package.resolved').read_text())['pins']
pin=next(p['state'] for p in pins if p['identity']=='desert-ant-core')
assert pin['version']=='4.3.0', 'SDK version requires review'
licensing=(source/'Usage/Licensing.swift').read_text()
for name,expected in [('LicenseGrantRequest',['installId','model','modelVersion','sdk','platform','app','key']),('LicenseActivateRequest',['license','key'])]:
    body=re.search(r'struct '+name+r': Encodable \{(.*?)\n\}',licensing,re.S).group(1)
    assert re.findall(r'var (\w+):',body)==expected, name+' payload changed'
assert 'https://events.desertant.com/api/v1' in licensing
assert 'send("license", request, who)' in licensing and 'send("activate", request, who)' in licensing
for p in Path('Sources/hushpen').glob('*.swift'):
    code=p.read_text()
    assert not re.search(r'\bModelStore\b',code), 'Use public Voz.download'
    assert not re.search(r'(usageDisabled|DAL_USAGE_DISABLED|licenseEndpoint|DAL_LICENSE_ENDPOINT)\s*=',code), 'Do not alter licensing'
if sys.argv[1]=='--write-baseline':
    baseline.write_text('\n'.join(files)+'\n')
    hashfile.write_text(json.dumps({'sdk':pin,'sha256':hashes},indent=2,sort_keys=True)+'\n')
    print('Recorded reviewed SDK sources. Review must be documented in docs/TECHNICAL.md.')
else:
    assert baseline.read_text().splitlines()==files, 'Network inventory changed; review and document first'
    saved=json.loads(hashfile.read_text())
    assert saved=={'sdk':pin,'sha256':hashes}, 'Reviewed SDK sources changed; review and document first'
    print('SDK 4.3.0 network inventory, source hashes and license payloads: passed.')
PY
