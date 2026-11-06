"""Inventory and batch-render the bilingual BioMate series. No external services.

Paths in the catalog are relative to the repository root. Every selected edition
gets an explicit result; missing assets never count as a completed video.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
from types import SimpleNamespace
from storyboard_video import build, plan

ROOT = Path(__file__).resolve().parents[3]


def load_catalog(path, root=ROOT):
    data = json.loads(Path(path).read_text())
    if data.get('schemaVersion') != 1 or data.get('languages') != ['en', 'zh']:
        raise ValueError('Expected bilingual series catalog schema v1')
    ids = [e['id'] for e in data['episodes']]
    if len(ids) != len(set(ids)):
        raise ValueError('Duplicate episode IDs')
    for e in data['episodes']:
        for lang in data['languages']:
            p = root / e['tutorials'][lang]
            if not p.is_file():
                raise ValueError(f'Missing {lang} tutorial: {p}')
        if e.get('parent') and e['parent'] not in ids:
            raise ValueError(f'Unknown parent: {e["parent"]}')
    expected = {str(p.relative_to(root)) for p in (root/'docs/user-manual/tutorials').rglob('*.md') if p.name != 'README.md'}
    mapped = {p for e in data['episodes'] for p in e['tutorials'].values()}
    if expected - mapped:
        raise ValueError(f'Tutorials missing from catalog: {sorted(expected-mapped)}')
    return data


def readiness(episode, lang, silent=False, root=ROOT):
    production = episode['production']
    missing = [k for k in ('storyboard', 'frames') if not production.get(k)]
    if missing:
        return 'BLOCKED', 'Missing ' + ', '.join(missing)
    try:
        audio = root/production['audio']/lang if production.get('audio') else None
        plan(root/production['storyboard'], root/production['frames'], lang, audio, silent=silent)
    except (ValueError, OSError, KeyError, TypeError) as exc:
        return 'BLOCKED', str(exc)
    return 'READY_FOR_INTERNAL_RENDER', 'Release review still required'


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--catalog', required=True)
    p.add_argument('--action', choices=['inventory', 'render'], default='inventory')
    p.add_argument('--only', help='Comma-separated episode IDs; omit for entire series')
    p.add_argument('--language', choices=['en', 'zh', 'both'], default='both')
    p.add_argument('--silent-preview', action='store_true')
    p.add_argument('--out-dir', default=str(ROOT/'recording/output/series-review'))
    p.add_argument('--report', required=True)
    p.add_argument('--encoder', default='libopenh264')
    p.add_argument('--overwrite', action='store_true')
    args = p.parse_args()
    data = load_catalog(args.catalog)
    selected = set(args.only.split(',')) if args.only else {e['id'] for e in data['episodes']}
    unknown = selected - {e['id'] for e in data['episodes']}
    if unknown:
        p.error(f'Unknown episode IDs: {sorted(unknown)}')
    rows = []
    for e in data['episodes']:
        if e['id'] not in selected:
            continue
        for lang in (['en', 'zh'] if args.language == 'both' else [args.language]):
            status, reason = readiness(e, lang, args.silent_preview)
            row = {'episode': e['id'], 'language': lang, 'status': status, 'reason': reason,
                   'productVerification': e['verification']['status'], 'release': 'NOT_RELEASED'}
            if args.action == 'render' and status == 'READY_FOR_INTERNAL_RENDER':
                cfg = e['production']
                render_args = SimpleNamespace(storyboard=ROOT/cfg['storyboard'], frames_dir=ROOT/cfg['frames'],
                    audio_root=ROOT/cfg['audio'] if cfg.get('audio') else None,
                    silent_preview=args.silent_preview, hold=6, encoder=args.encoder,
                    out_dir=Path(args.out_dir)/e['id'], overwrite=args.overwrite)
                try:
                    build(render_args, lang)
                    row['status'] = 'RENDERED_INTERNAL_REVIEW'
                except Exception as exc:
                    row.update(status='FAILED', reason=str(exc))
            rows.append(row)
    summary = dict(Counter(r['status'] for r in rows))
    report = Path(args.report); report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps({'action': args.action, 'silentPreview': args.silent_preview,
        'status':'IN_PRODUCTION_NOT_RELEASED', 'summary': summary, 'editions': rows}, indent=2)+'\n')
    print(json.dumps(summary))
    # Inventory is successful when the catalog was audited, even if production is pending.
    # A render request fails if ANY requested edition is missing or failed.
    if args.action == 'render' and any(r['status'] != 'RENDERED_INTERNAL_REVIEW' for r in rows):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
