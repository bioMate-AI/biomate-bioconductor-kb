"""Validate JSON health responses; an HTTP-200 SPA fallback is not API health."""
import argparse
import json
import urllib.request


def validate_health_response(endpoint, status, content_type, body):
    if status != 200 or 'application/json' not in content_type.lower():
        return False
    try:
        value = json.loads(body)
    except (ValueError, TypeError):
        return False
    if not isinstance(value, dict):
        return False
    if endpoint == '/healthz':
        return value.get('ok') is True
    if endpoint == '/api/biomate/health':
        return value.get('status') == 'ok' and value.get('assistantReady') is True
    if endpoint == '/api/galaxy/version':
        return isinstance(value.get('version_major'), str) and bool(value['version_major'])
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', default='https://dev-public.biomate.ai')
    args = parser.parse_args()
    failed = False
    for endpoint in ['/healthz', '/api/biomate/health', '/api/galaxy/version']:
        try:
            with urllib.request.urlopen(args.base.rstrip('/') + endpoint, timeout=20) as response:
                ok = validate_health_response(endpoint, response.status, response.headers.get('Content-Type', ''), response.read(65536))
            print(('PASS' if ok else 'FAIL') + ' ' + endpoint)
        except Exception as error:
            ok = False
            print('FAIL ' + endpoint + ' ' + type(error).__name__)
        failed = failed or not ok
    return 1 if failed else 0


if __name__ == '__main__':
    raise SystemExit(main())
