from pathlib import Path
import hashlib,json

root=Path(__file__).resolve().parent
m=json.loads((root/'manifest.json').read_text(encoding='utf-8'))
out=root/m['restored_filename']
if out.exists():
    raise SystemExit(f'Refusing to overwrite: {out}')
for part in m['parts']:
    data=(root/'parts'/part['file']).read_bytes()
    if len(data)!=part['size'] or hashlib.sha256(data).hexdigest()!=part['sha256']:
        raise SystemExit(f"Missing or damaged part: {part['file']}")
full=hashlib.sha256();total=0
with out.open('xb') as f:
    for part in m['parts']:
        data=(root/'parts'/part['file']).read_bytes();f.write(data);full.update(data);total+=len(data)
if total!=m['size'] or full.hexdigest()!=m['sha256']:
    raise SystemExit('Merged archive verification failed')
print(f'Archive restored and SHA-256 verified: {out}')
