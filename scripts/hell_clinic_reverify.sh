#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
TOKEN=$(cat /tmp/biomate_e2e_token.txt)
OUT=/Users/kky/biomate-nextphase-ci-fix/frontend/e2e/execshots/hell-clinic-20261113
mkdir -p "$OUT"

echo "=== cancel DE ==="
curl -sS -o /tmp/cancel.json -w "http=%{http_code}\n" -X POST \
  "https://dev-public.biomate.ai/api/workflows/runs/b6cb8481-5254-40c4-a6b3-97dda35ec800/cancel" \
  -H "Cookie: biomate_token=$TOKEN" \
  -H "X-E2E-Test-Token: biomate-e2e-bypass-token-dev-only" \
  -H "Content-Type: application/json" -d '{}' || true
head -c 200 /tmp/cancel.json; echo

echo "=== CHAT Generate 500 ==="
curl -sS -N -X POST "https://dev-public.biomate.ai/api/chat/stream" \
  -H "Cookie: biomate_token=$TOKEN" \
  -H "X-E2E-Test-Token: biomate-e2e-bypass-token-dev-only" \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream" \
  -d '{"message":"Generate 500 candidates for this target with drug-like properties.","history":[]}' \
  --max-time 120 -o "$OUT/02-generate500-chat.sse" -w "http=%{http_code}\n" || true
wc -c "$OUT/02-generate500-chat.sse"

python3 <<'PY'
import re, json, pathlib
out=pathlib.Path("/Users/kky/biomate-nextphase-ci-fix/frontend/e2e/execshots/hell-clinic-20261113")
raw=(out/"02-generate500-chat.sse").read_text(errors="replace")
texts=[]; events=[]
for m in re.finditer(r"data:\s*(\{.*\})", raw):
  try: o=json.loads(m.group(1))
  except: continue
  t=o.get("type") or o.get("event") or o.get("kind")
  events.append(t)
  for k in ("content","text","delta","message","clarification_question"):
    v=o.get(k)
    if isinstance(v,str) and v.strip(): texts.append(v)
joined="".join(texts)
(out/"02-generate500-chat.txt").write_text(joined[:12000])
low=joined.lower()
print("event_types", sorted(set(x for x in events if x))[:50])
print("len_joined", len(joined))
print("ADMET-Gated", "admet-gated" in low or "admet_gated" in low)
print("target-to-lead", "target-to-lead" in low or "target_to_lead" in low)
print("pharmacophore+admet+dock", all(x in low for x in ("pharmacophore","admet","dock")))
print("reinvent", "reinvent" in low)
print("clarification-ish", any(x in low for x in ("missing","pdb","sequence","structure","clarif","need")))
print("---TEXT---")
print(joined[:2500])
chains=sorted(set(re.findall(r'"(?:chain_name|chain_display_name|candidate_chain)"\s*:\s*"([^"]+)"', raw)))
print("chains", chains)
wtypes=sorted(set(re.findall(r'"workflow_type"\s*:\s*"([^"]+)"', raw)))
print("workflow_types", wtypes)
PY

python3 <<'PY'
import json, urllib.request
token=open("/tmp/biomate_e2e_token.txt").read().strip()
body={
  "workflowDefinition": {
    "name": "nf-core/differentialabundance",
    "nextflow_path": "biomni_workflows/nfcore/differentialabundance/main.nf",
    "required_params": [
      {"name":"samplesheet","type":"file","required":True,"value":"s3://biomate-dev-placeholder/samplesheet.csv"},
      {"name":"matrix","type":"file","required":True,"value":None},
      {"name":"contrasts","type":"file","required":True,"value":"s3://biomate-dev-placeholder/contrasts.csv"},
    ],
    "optional_params": [{"name":"input","type":"file","required":False}],
  },
  "params": {
    "samplesheet":"s3://biomate-dev-placeholder/samplesheet.csv",
    "contrasts":"s3://biomate-dev-placeholder/contrasts.csv",
  },
}
req=urllib.request.Request(
  "https://dev-public.biomate.ai/api/workflows/execute",
  data=json.dumps(body).encode(),
  headers={
    "Content-Type":"application/json",
    "Cookie":f"biomate_token={token}",
    "X-E2E-Test-Token":"biomate-e2e-bypass-token-dev-only",
  },
  method="POST",
)
try:
  with urllib.request.urlopen(req, timeout=60) as r:
    print("DE missing-matrix status", r.status)
    print(r.read()[:1000].decode())
except Exception as e:
  print("DE missing-matrix status", getattr(e,"code",None))
  print(e.read()[:1500].decode() if hasattr(e,"read") else e)
PY
