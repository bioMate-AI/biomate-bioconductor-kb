#!/usr/bin/env python3
"""Inventory tutorial deliverables without treating file existence as approval."""
import hashlib
import json
import pathlib
import re
import subprocess
import wave
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/qa/20261003-tutorial-release'


def digest(p):
    h = hashlib.sha256()
    with p.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    report = {'checkedAt': datetime.now(timezone.utc).isoformat(), 'releaseStatus': 'HOLD',
              'documents': [], 'videos': [], 'pilotAudio': {}}
    for p in sorted((ROOT / 'docs/user-manual/tutorials').rglob('*.md')):
        txt = p.read_text()
        images = re.findall(r'!\[[^\]]*\]\(([^)]+)\)', txt)
        missing = [x for x in images if not x.startswith(('https:', 'http:'))
                   and not (p.parent / x.split(' "')[0]).exists()]
        report['documents'].append({'path': str(p.relative_to(ROOT)), 'sha256': digest(p),
            'images': len(images), 'missingImages': missing,
            'unfinishedFigures': len(re.findall(r'Figure to add|待补|待添加|待截图', txt)),
            'captureMarkers': txt.count('<!-- CAPTURE'), 'releaseStatus': 'UNREVIEWED'})
    for p in sorted((ROOT / 'recording/output').glob('*.mp4')):
        probe = subprocess.run(['ffprobe', '-v', 'error', '-show_entries',
            'format=duration:stream=codec_name,codec_type,width,height,r_frame_rate,sample_rate,channels',
            '-of', 'json', str(p)], check=True, capture_output=True, text=True)
        report['videos'].append({'path': str(p.relative_to(ROOT)), 'sha256': digest(p),
            'bytes': p.stat().st_size, 'media': json.loads(probe.stdout), 'releaseStatus': 'HOLD'})
    meta = json.loads((ROOT / 'recording/audio/drug-dev-shared/record_meta.json').read_text())
    for lang in ['en', 'zh']:
        clips = []
        for i, start in enumerate(meta['timeline']):
            p = ROOT / f'recording/audio/drug-dev-{lang}/step-{i+1:03d}.wav'
            with wave.open(str(p)) as w:
                duration = w.getnframes() / w.getframerate()
                channels, width = w.getnchannels(), w.getsampwidth()
            end = meta['timeline'][i+1] if i+1 < len(meta['timeline']) else meta['total_seconds']
            clips.append({'scene': i+1, 'duration': round(duration, 3),
                'slot': round(end-start, 3), 'overrun': round(max(0, duration-(end-start)), 3),
                'channels': channels, 'sampleWidth': width})
        report['pilotAudio'][lang] = clips
    report['summary'] = {'documents': len(report['documents']),
        'documentsWithMissingImages': sum(bool(d['missingImages']) for d in report['documents']),
        'unfinishedFigures': sum(d['unfinishedFigures'] for d in report['documents']),
        'existingVideos': len(report['videos']), 'upgradedPilotSeconds': meta['total_seconds'],
        'approvedVideos': 0}
    (OUT / 'asset-inventory.json').write_text(json.dumps(report, indent=2, ensure_ascii=False))
    print(json.dumps(report['summary'], indent=2))


if __name__ == '__main__':
    main()
