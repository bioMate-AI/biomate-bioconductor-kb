#!/usr/bin/env python3
"""Fail closed before a stale worktree can replace newer public dev code.

Two gates (both required):

1. **Commit ancestry** — HEAD must contain the live build-info (and ledger) commit.
2. **Content preservation** — for product paths whose tree differs from that live
   tip, HEAD must include at least one *non-merge* commit after the tip that
   touches the path. A bare `git merge -s ours <live>` records ancestry while
   keeping the other branch's tree; that pattern used to pass gate 1 and silently
   clobber dig (e.g. skills UI). Gate 2 refuses it.

No fetch/reset/remote mutation. Emergency override permits a known divergent /
older commit *or* an intentional content clobber, and requires an explicit
operator reason (≥12 chars). Identity failures and unknown deployed commits
remain fatal even with override.
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

# Paths whose live blobs must not disappear via ancestry-only merges.
# Docs / caches / DBs are excluded — they churn without meaning "dropped work".
_PROTECTED_PREFIXES = (
    'frontend/',
    'backend/lib/',
    'backend/biomni_workflows/',
    'backend/config/',
    'scripts/',
)


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


def lost_commits(repo, deployed, head, limit=30):
    """Commits live on dev that `head` does not contain — what this deploy would drop."""
    out = git(repo, 'log', '--no-merges', '--format=%h %an %ad %s', '--date=short', f'{head}..{deployed}')
    lines = [l for l in out.stdout.splitlines() if l.strip()]
    return lines[:limit], len(lines)


def _protected_path(path):
    return any(path == p[:-1] or path.startswith(p) for p in _PROTECTED_PREFIXES)


def content_clobber_paths(repo, baseline, head, limit=40):
    """Product paths live on `baseline` whose blobs would change on deploy of `head`
    without any non-merge commit in baseline..head touching the path.

    That is the fingerprint of `git merge -s ours <baseline>` (ancestry recorded,
    other branch's tree kept) and of merge resolutions that discard live content
    without an explicit follow-up commit.
    """
    if baseline == head:
        return []
    diff = git(repo, 'diff', '--name-status', baseline, head)
    if diff.returncode:
        raise ValueError(f'Cannot diff {baseline[:10]}..{head[:10]} for content preservation')
    clobbered = []
    for line in diff.stdout.splitlines():
        if not line.strip():
            continue
        parts = line.split('\t')
        status, path = parts[0], parts[-1]
        # Renames: name-status is "R###\told\tnew" — protect both ends.
        paths = parts[1:] if status.startswith('R') or status.startswith('C') else [path]
        for p in paths:
            if not _protected_path(p):
                continue
            # --ancestry-path: only commits that descend from baseline toward head.
            # Without it, a parallel branch's older edit (kept by `merge -s ours`)
            # would look like "forward work" and wrongly pass.
            touched = git(
                repo, 'log', '--no-merges', '--ancestry-path', '--format=%H',
                f'{baseline}..{head}', '--', p,
            )
            if touched.returncode:
                raise ValueError(f'Cannot read history for {p} between {baseline[:10]} and {head[:10]}')
            if touched.stdout.strip():
                continue  # real forward work on this path after the live tip
            clobbered.append(f'{status}\t{p}')
            if len(clobbered) >= limit:
                return clobbered
    return clobbered


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


def _require_content_preserved(repo, baseline, head, label, emergency_reason):
    """Refuse ancestry-only merges that drop live product-file content.
    Returns True when an emergency override permitted a clobber."""
    clobbered = content_clobber_paths(repo, baseline, head)
    if not clobbered:
        return False
    if emergency_reason and len(emergency_reason.strip()) >= 12:
        return True
    raise ValueError(
        f'Content clobber: deploying {head[:10]} would discard live {label} ({baseline[:10]}) '
        f'product files without a follow-up commit on those paths '
        f'(typical of `git merge -s ours`). Refused paths:\n  '
        + '\n  '.join(clobbered)
        + '\nDo a real merge that keeps the live blobs, or commit an explicit intentional '
        'override on each path, then retry. Emergency: BIOMATE_EMERGENCY_DEPLOY_REASON=…'
    )


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
    # 3. Containing the live commit is not enough: `merge -s ours` records ancestry
    #    while keeping the other tree. Require a real non-merge commit on every
    #    protected path that would change vs the live tip(s).
    override = _require_content_preserved(repo, deployed, head, 'deployed', emergency_reason) or override
    if ledger_head and SHA.fullmatch(ledger_head) and ledger_head != deployed:
        override = _require_content_preserved(
            repo, ledger_head, head, 'last-ledger', emergency_reason) or override
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
