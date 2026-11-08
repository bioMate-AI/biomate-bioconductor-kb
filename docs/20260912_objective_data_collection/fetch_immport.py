"""Authenticated ImmPort download for patient-level therapy-duration labels.

Reads credentials from the environment — NOTHING is hardcoded and no access is
faked. If credentials are absent it exits with instructions and downloads nothing.

    export IMMPORT_USERNAME='...'
    export IMMPORT_PASSWORD='...'
    python3 fetch_immport.py SDY1490          # iWITH withdrawal study (default)

Flow (ImmPort Data API):
  1. POST username/password to the auth endpoint -> bearer token.
  2. Use the token against the Data Query / file-download API for the study.
Target tables for the therapy-duration objective: subject, arm/cohort, planned &
actual visits, assessments, adverse events, and the treatment/withdrawal records
(reason + dates) needed for time-to-event. Aggregate trial counts do NOT substitute
for these. Everything lands in raw/immport/ and is hashed into the manifest;
training-eligibility stays False pending the admission gate.
"""
import os, sys, json, hashlib, urllib.request, urllib.parse, urllib.error
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "raw" / "immport"
AUTH_URL = "https://auth.immport.org/auth/token"
DATA_BASE = "https://api.immport.org/data/query"  # study/file query base

def die(msg, code=2):
    print(msg, file=sys.stderr)
    sys.exit(code)

def get_token(user, pw):
    data = urllib.parse.urlencode({"username": user, "password": pw}).encode()
    req = urllib.request.Request(AUTH_URL, data=data,
                                 headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            tok = json.loads(r.read()).get("token")
    except urllib.error.HTTPError as e:
        die(f"ImmPort auth failed: HTTP {e.code} {e.read().decode(errors='replace')[:300]}")
    if not tok:
        die("ImmPort auth returned no token — check credentials.")
    return tok

def fetch(token, study, manifest):
    OUT.mkdir(parents=True, exist_ok=True)
    hdr = {"Authorization": f"bearer {token}"}
    # study metadata + the result-file summary that lists downloadable tables
    for name, url in [
        (f"{study}_summary.json", f"{DATA_BASE}/study/summary/{study}"),
        (f"{study}_filePath.json", f"{DATA_BASE}/result/filePath?studyAccession={study}"),
    ]:
        req = urllib.request.Request(url, headers=hdr)
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                blob = r.read()
        except urllib.error.HTTPError as e:
            print(f"  {name}: HTTP {e.code} {e.read().decode(errors='replace')[:200]}", file=sys.stderr)
            manifest.append(dict(file=name, url=url, status="failed", http=e.code))
            continue
        (OUT / name).write_bytes(blob)
        manifest.append(dict(file=name, url=url, bytes=len(blob),
                             sha256=hashlib.sha256(blob).hexdigest(),
                             status="downloaded", training_eligible=False))
        print(f"  {name}: {len(blob)} bytes")
    (ROOT / "immport_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

if __name__ == "__main__":
    study = sys.argv[1] if len(sys.argv) > 1 else "SDY1490"
    user, pw = os.environ.get("IMMPORT_USERNAME"), os.environ.get("IMMPORT_PASSWORD")
    if not user or not pw:
        die("No credentials. Set IMMPORT_USERNAME and IMMPORT_PASSWORD, then re-run.\n"
            "  In this session you can run:  ! export IMMPORT_USERNAME=... IMMPORT_PASSWORD=...\n"
            "Nothing was downloaded; no access was faked.")
    print(f"Authenticating to ImmPort as {user} …")
    token = get_token(user, pw)
    print(f"Fetching {study} …")
    fetch(token, study, [])
    print("Done. Review raw/immport/ then run label extraction for time-to-event fields.")
