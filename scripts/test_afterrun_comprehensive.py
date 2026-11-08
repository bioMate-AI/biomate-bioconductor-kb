#!/usr/bin/env python3
"""Read-only deployed After-run data contract checks using an existing fixture.

No workflow launch, user registration, AI findings/methods generation, data edits
or artifact downloads. UI rendering/download formatting is covered by the React
AfterRunReport suites; minified bundle words and obsolete feature flags are not
valid integration assertions. Missing fixture state is reported as SKIP, never PASS.
Credentials come from E2E environment overrides or the canonical local fixture;
no token, password, signed URL or scientific/private content is printed.
"""
import argparse
import json
import os
from pathlib import Path
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import http.cookiejar


def fixture_value(name, env_name):
    if os.environ.get(env_name):
        return os.environ[env_name]
    source = Path(__file__).resolve().parents[1] / 'frontend/e2e/_fixture-login.ts'
    match = re.search(r'export const ' + name + r'\s*=.*?\|\|\s*"([^\"]+)"', source.read_text(), re.S)
    if not match:
        raise RuntimeError('Set ' + env_name + ' or provide the canonical E2E fixture file')
    return match.group(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', default=os.environ.get('BIOMATE_URL', 'https://dev-public.biomate.ai'))
    parser.add_argument('--sample', type=int, default=2, help='Completed and failed records to inspect (1–5)')
    parser.add_argument('--json', dest='json_path', help='Optional redacted check report')
    args = parser.parse_args()
    base = args.base.rstrip('/')
    checks = []
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
    token = ''

    def record(name, ok, detail=''):
        state = 'PASS' if ok is True else 'FAIL' if ok is False else 'SKIP'
        checks.append({'name': name, 'status': state, 'detail': detail})
        print(f'[{state}] {name}' + (f' — {detail}' if detail else ''), flush=True)

    def request(path, body=None, anonymous=False, headers=None):
        hdr = {'Accept': 'application/json', 'User-Agent': 'biomate-afterrun-readonly-audit'}
        if token and not anonymous:
            hdr['Authorization'] = 'Bearer ' + token
        hdr.update(headers or {})
        data = None
        if body is not None:
            hdr['Content-Type'] = 'application/json'
            data = json.dumps(body).encode()
        req = urllib.request.Request(base + path, data=data, headers=hdr)
        try:
            # Anonymous boundary checks must not reuse the authenticated cookie jar.
            client = urllib.request.urlopen if anonymous else opener.open
            with client(req, timeout=45) as response:
                status, raw = response.status, response.read()
        except urllib.error.HTTPError as error:
            status, raw = error.code, error.read()
        except Exception as error:
            return 0, {'transportError': type(error).__name__}
        try:
            return status, json.loads(raw)
        except (ValueError, UnicodeDecodeError):
            return status, None

    print('Read-only After-run contract audit: ' + base, flush=True)
    try:
        status, auth = request('/api/auth/login', {
            'email': fixture_value('FIXTURE_EMAIL', 'E2E_FIXTURE_EMAIL'),
            'password': fixture_value('FIXTURE_PASSWORD', 'E2E_FIXTURE_PASSWORD'),
        }, headers={'X-E2E-Test-Token': fixture_value('E2E_TOKEN', 'E2E_TEST_TOKEN')})
        token = auth.get('token', '') if isinstance(auth, dict) else ''
        record('Existing fixture authentication', status == 200 and bool(token), f'HTTP {status}')
        if not token:
            raise RuntimeError('Authentication failed; authenticated checks cannot proceed')
        status, build = request('/build-info.json')
        record('Deployed build identity is readable JSON', status == 200 and isinstance(build, dict) and bool(build.get('commit')), f'HTTP {status}; commit={build.get("commit", "unknown") if isinstance(build, dict) else "unknown"}')
        status, body = request('/api/workflows/runs/overview?scope=all_chats&limit=100')
        runs = body.get('runs', body.get('rows')) if isinstance(body, dict) else None
        record('Authenticated Run Manager inventory', status == 200 and isinstance(runs, list), f'HTTP {status}; records={len(runs) if isinstance(runs, list) else "invalid"}')
        if not isinstance(runs, list):
            raise RuntimeError('Invalid run inventory; cannot test saved data contracts')
        get_status = lambda row: str(row.get('status') or (row.get('execution') or {}).get('status') or '').lower()
        groups = {'completed': [r for r in runs if get_status(r) in ('completed', 'succeeded', 'ok')], 'failed': [r for r in runs if get_status(r) in ('failed', 'error')]}
        sample = min(5, max(1, args.sample))
        nonempty_outputs = 0
        for kind, rows in groups.items():
            record(kind.title() + ' fixture state available', True if rows else None, f'{len(rows)} records; absence is a coverage gap, not proof of a UI defect')
            for index, row in enumerate(rows[:sample], 1):
                label = f'{kind} sample {index}'
                rid = row.get('runId') or row.get('id')
                if not rid:
                    record(label + ' has stable run identity', False)
                    continue
                encoded = urllib.parse.quote(str(rid), safe='')
                status, detail = request('/api/workflows/runs/' + encoded)
                record(label + ' reopens saved run', status == 200 and isinstance(detail, dict), f'HTTP {status}')
                path = '/api/runs/' + encoded + '/reproducibility-record'
                status, record_body = request(path)
                valid = status == 200 and isinstance(record_body, dict)
                record(label + ' reproducibility record reachable', valid, f'HTTP {status}')
                if not valid:
                    continue
                record(label + ' identity/status retained', record_body.get('runId') == rid and bool(record_body.get('workflowName')) and bool(record_body.get('status')))
                record(label + ' parameters/input bindings retain structured shape', isinstance(record_body.get('parameters'), dict) and isinstance(record_body.get('inputBindings'), list))
                outputs = record_body.get('outputs')
                valid_outputs = isinstance(outputs, list) and record_body.get('outputCount') == len(outputs)
                record(label + ' export output count matches output list', valid_outputs, f'outputs={len(outputs) if isinstance(outputs, list) else "invalid"}')
                if valid_outputs:
                    nonempty_outputs += bool(outputs)
                    record(label + ' output export metadata has names and valid optional checksums', all(isinstance(item, dict) and isinstance(item.get('name'), str) and item['name'] and (item.get('sha256') is None or bool(re.fullmatch('[0-9a-f]{64}', str(item['sha256'])))) for item in outputs))
                    record(label + ' export does not expose raw storage URIs', not any(re.search(r's3://|X-Amz-Signature=', json.dumps(item), re.I) for item in outputs))
                status2, reopened = request(path)
                record(label + ' reproducibility survives reopening', status2 == 200 and isinstance(reopened, dict) and all(reopened.get(key) == record_body.get(key) for key in ('runId', 'status', 'parameters', 'inputBindings', 'outputs', 'outputCount')))
                anonymous_status, _ = request(path, anonymous=True)
                record(label + ' reproducibility rejects anonymous access', anonymous_status in (401, 403), f'HTTP {anonymous_status}')
                status, canonical = request('/api/runs/' + encoded + '/outputs')
                record(label + ' canonical outputs are readable with consistent count', status == 200 and isinstance(canonical, dict) and isinstance(canonical.get('outputs'), list) and canonical.get('count') == len(canonical['outputs']), f'HTTP {status}')
                sid = row.get('chatSessionId') or (detail.get('chatSessionId') if isinstance(detail, dict) else None)
                if sid:
                    status, chat = request('/api/sessions/' + urllib.parse.quote(str(sid), safe=''))
                    record(label + ' original chat reopens with messages', status == 200 and isinstance(chat, dict) and isinstance(chat.get('messages'), list) and len(chat['messages']) > 0, f'HTTP {status}')
                else:
                    record(label + ' original chat coverage', None, 'No chatSessionId recorded; direct executor history does not establish chat restoration')
                if kind == 'failed':
                    execution = detail.get('execution') or {} if isinstance(detail, dict) else {}
                    nf = execution.get('nextflowStatus') or {}
                    record(label + ' stored failure includes diagnostic evidence', bool(execution.get('errorMessage') or nf.get('error') or nf.get('errorMessage') or nf.get('log_tail') or nf.get('error_message')))
        record('Sample includes actual exported output metadata', nonempty_outputs > 0 if groups['completed'] else None, f'{nonempty_outputs} sampled records with outputs')
    except Exception as error:
        record('Audit completed without setup/transport interruption', False, type(error).__name__ + ': ' + str(error))
    totals = {state: sum(c['status'] == state for c in checks) for state in ('PASS', 'FAIL', 'SKIP')}
    print('\nTOTAL: {PASS} PASS / {FAIL} FAIL / {SKIP} SKIP'.format(**totals))
    print('UI state/formatting: run frontend AfterRunReport component tests; not asserted by this API audit.')
    if args.json_path:
        Path(args.json_path).write_text(json.dumps({'target': base, 'scope': 'authenticated read-only saved-run contracts; no UI/execution claim', 'totals': totals, 'checks': checks}, indent=2) + '\n')
    return 1 if totals['FAIL'] else 0


if __name__ == '__main__':
    sys.exit(main())
