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
    try:
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=15) as response:
            if response.status != 200:
                raise ValueError('Public build identity is not HTTP 200')
            return parse_identity(response.read(65537), response.headers.get('Content-Type', ''))
    except Exception as error:
        if isinstance(error, ValueError):
            raise
        raise ValueError('Public build identity could not be read over verified HTTPS') from None


def git(repo, *args):
    return subprocess.run(['git','-C',str(repo),*args],capture_output=True,text=True)


def preflight(repo, deployed, emergency_reason=None):
    if not isinstance(deployed,str) or not SHA.fullmatch(deployed):
        raise ValueError('Invalid deployed commit identity')
    head = git(repo,'rev-parse','--verify','HEAD^{commit}')
    if head.returncode or not SHA.fullmatch(head.stdout.strip()):
        raise ValueError('Local HEAD is not a valid commit')
    head = head.stdout.strip()
    if git(repo,'cat-file','-e',deployed+'^{commit}').returncode:
        raise ValueError('Deployed commit is unknown locally; explicitly fetch/reconcile before deploying')
    relation = git(repo,'merge-base','--is-ancestor',deployed,head).returncode
    if relation not in (0,1):
        raise ValueError('Cannot establish deployed/local ancestry')
    if relation:
        if not emergency_reason or len(emergency_reason.strip()) < 12:
            raise ValueError('Stale/divergent worktree: deployed commit is not an ancestor of local HEAD')
        return {'deployedCommit':deployed,'localCommit':head,'emergencyOverride':True}
    return {'deployedCommit':deployed,'localCommit':head,'emergencyOverride':False}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',required=True)
    parser.add_argument('--url',default=DEFAULT_URL)
    parser.add_argument('--emergency-override-reason')
    args=parser.parse_args()
    result=preflight(args.repo,public_commit(args.url),args.emergency_override_reason)
    print(json.dumps(result))

if __name__=='__main__':
    try: main()
    except ValueError as error:
        print('Deployment ancestry preflight refused: '+str(error),file=sys.stderr)
        sys.exit(2)
