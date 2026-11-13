#!/usr/bin/env python3
"""Fail closed before a stale worktree can replace newer public dev code.

No fetch/reset/remote mutation. Emergency override permits a KNOWN divergent or
older commit only, and requires an explicit operator reason. Identity failures
and unknown deployed commits remain fatal even with override.
"""
import argparse
import json
import re
import subprocess
import sys
import urllib.parse
import urllib.request

DEFAULT_URL = 'https://dev-public.biomate.ai/build-info.json'
SHA = re.compile(r'^[0-9a-f]{40}$')


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError('Public build identity redirected; refusing')


def parse_identity(raw, content_type):
    if len(raw) > 65536 or content_type.split(';')[0].strip().lower() != 'application/json':
        raise ValueError('Public build identity must be bounded JSON, not HTML')
    try:
        data = json.loads(raw)
    except (ValueError, UnicodeError):
        raise ValueError('Public build identity is invalid JSON') from None
    commit = data.get('commit') if isinstance(data, dict) else None
    if not isinstance(commit, str) or not SHA.fullmatch(commit):
        raise ValueError('Public build identity lacks a full lowercase commit SHA')
    return commit


def public_commit(url=DEFAULT_URL):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or parsed.fragment:
        raise ValueError('Build identity requires a credential-free HTTPS URL')
    request = urllib.request.Request(url, headers={'Accept':'application/json', 'Cache-Control':'no-cache'})
    # Hit the origin directly. Env HTTP(S)_PROXY (Cursor sandbox CONNECT tunnels,
    # corporate MITM) is not on the trust path and previously failed closed as an
    # opaque "could not be read" after a 403 tunnel — SSH/SSM still worked, so
    # operators saw a false "dev is down" signal. Empty ProxyHandler disables them.
    opener = urllib.request.build_opener(NoRedirect(), urllib.request.ProxyHandler({}))
    try:
        with opener.open(request, timeout=15) as response:
            if response.status != 200:
                raise ValueError('Public build identity is not HTTP 200')
            return parse_identity(response.read(65537), response.headers.get('Content-Type', ''))
    except Exception as error:
        if isinstance(error, ValueError):
            raise
        raise ValueError(
            f'Public build identity could not be read over verified HTTPS '
            f'({type(error).__name__}: {error})'
        ) from None


def git(repo, *args):
    return subprocess.run(['git','-C',str(repo),*args],capture_output=True,text=True)


def lost_commits(repo, deployed, head, limit=30):
    """Commits live on dev that `head` does not contain — what this deploy would drop."""
    out = git(repo, 'log', '--no-merges', '--format=%h %an %ad %s', '--date=short', f'{head}..{deployed}')
    lines = [l for l in out.stdout.splitlines() if l.strip()]
    return lines[:limit], len(lines)


def _require_contained(repo, commit, head, label, emergency_reason):
    """HEAD must contain `commit`, else refuse (unless an emergency reason is given).
    Returns True when an emergency override was used to permit a non-contained commit."""
    if git(repo,'cat-file','-e',commit+'^{commit}').returncode:
        raise ValueError(f'{label} commit {commit[:10]} is unknown locally; explicitly fetch/reconcile before deploying')
    relation = git(repo,'merge-base','--is-ancestor',commit,head).returncode
    if relation not in (0,1):
        raise ValueError(f'Cannot establish {label}/local ancestry')
    if relation:
        if not emergency_reason or len(emergency_reason.strip()) < 12:
            lost, n = lost_commits(repo, commit, head)
            raise ValueError(
                f'Stale/divergent: the {label} commit ({commit[:10]}) is not contained in the commit '
                f'being deployed ({head[:10]}). Deploying would REMOVE {n} commit(s) of other people\'s work:\n  '
                + '\n  '.join(lost)
                + ('\n  …' if n > len(lost) else '')
                + f'\nMerge {commit[:10]} (or its branch) into what you deploy, then retry.')
        return True
    return False


def preflight(repo, deployed, emergency_reason=None, head_ref='HEAD', ledger_head=None):
    if not isinstance(deployed,str) or not SHA.fullmatch(deployed):
        raise ValueError('Invalid deployed commit identity')
    head = git(repo,'rev-parse','--verify',head_ref+'^{commit}')
    if head.returncode or not SHA.fullmatch(head.stdout.strip()):
        raise ValueError('Local HEAD is not a valid commit')
    head = head.stdout.strip()
    # 1. HEAD must contain the commit the public build-info.json reports.
    override = _require_contained(repo, deployed, head, 'deployed', emergency_reason)
    # 2. HEAD must ALSO contain the ledger's last-recorded deploy, when supplied.
    #    build-info.json is baked only into the FRONTEND image, so a backend/db/
    #    workflow-only deploy leaves it stale — and a later full deploy could then
    #    pass step 1 against that stale commit and silently overwrite the
    #    backend-only work. The ledger records every deploy's full HEAD, so
    #    requiring HEAD ⊇ ledger-head closes that window.
    if ledger_head and SHA.fullmatch(ledger_head) and ledger_head != deployed:
        override = _require_contained(repo, ledger_head, head, 'last-ledger', emergency_reason) or override
    return {'deployedCommit':deployed,'localCommit':head,'emergencyOverride':override,
            'ledgerHead':ledger_head if (ledger_head and SHA.fullmatch(ledger_head)) else None}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',required=True)
    parser.add_argument('--url',default=DEFAULT_URL)
    parser.add_argument('--emergency-override-reason')
    parser.add_argument('--head', default='HEAD', help='commit to be deployed (default: local HEAD; the GitHub Action passes the image commit)')
    parser.add_argument('--ledger-head', help='last commit recorded in the dev deploy ledger (closes the backend-only build-info gap); the sync script reads it over the held lease')
    args=parser.parse_args()
    result=preflight(args.repo,public_commit(args.url),args.emergency_override_reason,args.head,args.ledger_head)
    print(json.dumps(result))

if __name__=='__main__':
    try: main()
    except ValueError as error:
        print('Deployment ancestry preflight refused: '+str(error),file=sys.stderr)
        sys.exit(2)
