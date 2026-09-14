#!/bin/bash
# Collect additional cyclic-peptide training/test data on a short-lived AWS instance.
# Best-effort per dataset: a failure in one does not abort the others. Raw archives are
# uploaded (with SHA256 + readback) BEFORE any processing, so provenance survives a
# processing failure. See docs/DATA_COLLECTION_PLAN.md.
set -uo pipefail
export AWS_DEFAULT_REGION=us-west-2
export DEBIAN_FRONTEND=noninteractive
ROOT=/opt/cyclic-collect
BUCKET=knowledge-datasets-1759951976
OUT_S3="s3://$BUCKET/cyclic_peptide"
STATUS="$ROOT/status"
mkdir -p "$ROOT" "$STATUS"
exec > >(tee -a "$STATUS/collect.log") 2>&1
echo "== collector start $(date -u +%FT%TZ) =="

# Auto-terminate safety net (in case the script hangs).
systemd-run --unit=collect-deadline --on-active="${MAX_RUNTIME:-4h}" /sbin/shutdown -h now || true
sync_status() { aws s3 sync "$STATUS" "$OUT_S3/datasets/_collect_status/" --only-show-errors || true; }
trap 'rc=$?; echo "== collector exit rc=$rc =="; sync_status; shutdown -h now; exit $rc' EXIT

if [ "${SKIP_SETUP:-0}" != 1 ]; then
  for a in 1 2 3 4 5; do apt-get -o DPkg::Lock::Timeout=300 update -qq && break; sleep 10; done
  apt-get -o DPkg::Lock::Timeout=300 install -y -qq python3-venv python3-pip unzip curl
  # AWS CLI: Ubuntu 24.04 has NO 'awscli' apt package, so install v2 from the official zip.
  if ! command -v aws >/dev/null 2>&1; then
    curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscliv2.zip
    (cd /tmp && unzip -q -o awscliv2.zip && ./aws/install --update)
  fi
  python3 -m venv "$ROOT/venv"
  "$ROOT/venv/bin/pip" install -q --disable-pip-version-check 'pip==25.0.1'
  "$ROOT/venv/bin/pip" install -q 'requests==2.32.3' 'boto3>=1.36,<2' 'rdkit==2024.9.6' \
    'biopython==1.83' 'pandas==2.2.2' 'numpy==1.26.4'
fi
PY="$ROOT/venv/bin/python"

record() { echo "{\"dataset\":\"$1\",\"status\":\"$2\",\"time\":\"$(date -u +%FT%TZ)\",\"detail\":\"${3:-}\"}" > "$STATUS/$1.json"; sync_status; }

# Verified S3 upload: put object with sha256 metadata, read back, compare.
put_verified() { # $1 local file  $2 s3 key
  local f="$1" key="$2"
  local sha; sha=$(sha256sum "$f" | awk '{print $1}')
  aws s3api put-object --bucket "$BUCKET" --key "$key" --body "$f" \
    --metadata "sha256=$sha" --only-show-errors >/dev/null || { aws s3 cp "$f" "s3://$BUCKET/$key" --only-show-errors || return 1; }
  local rb="$ROOT/.rb"; aws s3 cp "s3://$BUCKET/$key" "$rb" --only-show-errors || return 1
  local sha2; sha2=$(sha256sum "$rb" | awk '{print $1}'); rm -f "$rb"
  [ "$sha" = "$sha2" ] || { echo "READBACK MISMATCH $key"; return 1; }
  echo "$sha"
}

################################ 4. HELM monomer library ############################
( set -e
  echo "-- HELM monomers --"
  D="$ROOT/helm"; mkdir -p "$D"; cd "$D"
  COMMIT=$(curl -m 30 -s "https://api.github.com/repos/PistoiaHELM/HELMMonomerSets/commits?per_page=1" | "$PY" -c "import sys,json;print(json.load(sys.stdin)[0]['sha'])")
  echo "HELM commit $COMMIT"
  for f in "HELMCoreLibrary.db" "HELMmonomerSchema.json" "LICENSE" "README.md"; do
    curl -m 120 -fsS -o "$(basename "$f")" "https://raw.githubusercontent.com/PistoiaHELM/HELMMonomerSets/$COMMIT/$f" || true
  done
  tar -czf helm_monomers.tgz HELMCoreLibrary.db HELMmonomerSchema.json LICENSE README.md 2>/dev/null
  SHA=$(put_verified helm_monomers.tgz "cyclic_peptide/datasets/helm_monomers/$COMMIT/helm_monomers.tgz")
  echo "{\"dataset\":\"helm_monomers\",\"repo\":\"PistoiaHELM/HELMMonomerSets\",\"commit\":\"$COMMIT\",\"sha256\":\"$SHA\",\"s3\":\"$OUT_S3/datasets/helm_monomers/$COMMIT/helm_monomers.tgz\"}" > "$STATUS/helm_monomers_acquisition.json"
  record helm_monomers ok "$COMMIT"
) || record helm_monomers failed

################################ 1. PepBDB (+cyclic subset) #########################
( set -e
  echo "-- PepBDB --"
  D="$ROOT/pepbdb"; mkdir -p "$D"; cd "$D"
  URL="http://huanglab.phys.hust.edu.cn/pepbdb/db/download/pepbdb-20200318.tgz"
  curl -m 1800 -fsS -o pepbdb.tgz "$URL"
  SHA=$(put_verified pepbdb.tgz "cyclic_peptide/datasets/pepbdb/20200318/pepbdb-20200318.tgz")
  echo "{\"dataset\":\"pepbdb\",\"source_url\":\"$URL\",\"release\":\"20200318\",\"sha256\":\"$SHA\"}" > "$STATUS/pepbdb_acquisition.json"
  record pepbdb raw_uploaded "$SHA"
  # cyclic-subset detection (best effort)
  tar -xzf pepbdb.tgz
  "$PY" - <<'PYEOF'
import os, json, glob, hashlib
from Bio.PDB import PDBParser
import numpy as np
parser = PDBParser(QUIET=True)
_dirs = [d for d in glob.glob('pepbdb*') if os.path.isdir(d)]
root = _dirs[0] if _dirs else '.'
# PepBDB layout: <root>/<pdbid_chain>/peptide.pdb
entries, cyclic = [], []
def load_pep(p):
    try: return parser.get_structure('p', p)
    except Exception: return None
for d in sorted(glob.glob(os.path.join(root, '*'))):
    pep = os.path.join(d, 'peptide.pdb')
    if not os.path.isfile(pep): continue
    s = load_pep(pep)
    if s is None: continue
    res = [r for r in s.get_residues() if 'CA' in r]
    if len(res) < 2 or len(res) > 50: continue
    is_cyc = False; reason = None
    # head-to-tail: N of first residue near C of last residue
    try:
        n0 = res[0]['N'].coord; cL = res[-1]['C'].coord
        if np.linalg.norm(n0 - cL) < 2.0: is_cyc, reason = True, 'head_to_tail'
    except Exception: pass
    if not is_cyc:  # disulfide between two cysteines
        sgs = [r['SG'].coord for r in res if r.get_resname()=='CYS' and 'SG' in r]
        for i in range(len(sgs)):
            for j in range(i+1, len(sgs)):
                if np.linalg.norm(sgs[i]-sgs[j]) < 2.5: is_cyc, reason = True, 'disulfide'
    seq = ''.join(r.get_resname()+'|' for r in res)
    rec = {'entry': os.path.basename(d), 'n_res': len(res), 'cyclic': is_cyc, 'reason': reason,
           'pep_seq_hash': hashlib.sha1(seq.encode()).hexdigest()[:12]}
    entries.append(rec)
    if is_cyc: cyclic.append(rec)
# leak-free split of cyclic subset by peptide-sequence hash
buckets = {}
for r in cyclic: buckets.setdefault(r['pep_seq_hash'], []).append(r['entry'])
keys = sorted(buckets)
test_keys = set(k for k in keys if int(k[:6], 16) % 100 < 15)  # ~15% held out by hash
split = {'train': [e for k in keys if k not in test_keys for e in buckets[k]],
         'test':  [e for k in keys if k in test_keys for e in buckets[k]]}
summary = {'total_peptide_entries': len(entries), 'cyclic_entries': len(cyclic),
           'cyclic_unique_seq_clusters': len(buckets),
           'split_counts': {'train': len(split['train']), 'test': len(split['test'])},
           'cyclic_detection': 'head_to_tail (<2.0A N-C) or disulfide (<2.5A SG-SG); heuristic candidate set',
           'split_policy': 'peptide-sequence-hash disjoint, ~15% test'}
json.dump({'summary': summary, 'entries': entries}, open('pepbdb_cyclic_index.json','w'))
json.dump(split, open('pepbdb_cyclic_split.json','w'), indent=2)
json.dump(summary, open('/opt/cyclic-collect/status/pepbdb_summary.json','w'), indent=2)
print(json.dumps(summary))
PYEOF
  put_verified pepbdb_cyclic_index.json "cyclic_peptide/datasets/pepbdb/20200318/pepbdb_cyclic_index.json" >/dev/null
  put_verified pepbdb_cyclic_split.json "cyclic_peptide/datasets/pepbdb/20200318/pepbdb_cyclic_split.json" >/dev/null
  record pepbdb ok "$SHA"
) || record pepbdb failed_or_partial

################################ 2. RCSB cyclic-peptide index #######################
( set -e
  echo "-- RCSB cyclic index --"
  D="$ROOT/rcsb"; mkdir -p "$D"; cd "$D"
  "$PY" - <<'PYEOF'
import json, requests, time
# Full-text "cyclic peptide" structures that also contain a Protein polymer entity.
query = {
  "query": {"type": "group", "logical_operator": "and", "nodes": [
      {"type": "terminal", "service": "full_text", "parameters": {"value": "cyclic peptide"}},
      {"type": "terminal", "service": "text", "parameters": {
          "attribute": "entity_poly.rcsb_entity_polymer_type", "operator": "exact_match", "value": "Protein"}}
  ]},
  "return_type": "entry",
  "request_options": {"return_all_hits": True}
}
ids = []
try:
    r = requests.post("https://search.rcsb.org/rcsbsearch/v2/query", json=query, timeout=120)
    if r.status_code == 200:
        ids = [x['identifier'] for x in r.json().get('result_set', [])]
except Exception as e:
    print("RCSB query error:", e)
out = {'query': 'full_text "cyclic peptide" AND has Protein entity', 'n_entries': len(ids),
       'note': 'text-based candidate index; cyclicity not structurally verified here',
       'entry_ids': ids}
json.dump(out, open('rcsb_cyclic_index.json','w'), indent=2)
json.dump({'n_entries': len(ids)}, open('/opt/cyclic-collect/status/rcsb_summary.json','w'))
print("RCSB cyclic-peptide candidate entries:", len(ids))
PYEOF
  put_verified rcsb_cyclic_index.json "cyclic_peptide/datasets/rcsb_cyclic_index/$(date -u +%Y%m%d)/rcsb_cyclic_index.json" >/dev/null
  record rcsb_cyclic_index ok
) || record rcsb_cyclic_index failed

################################ 3. BindingDB peptide subset ########################
( set -e
  echo "-- BindingDB peptide subset --"
  D="$ROOT/bindingdb"; mkdir -p "$D"; cd "$D"
  # Resolve the current All-TSV zip from the downloads page.
  URL=$(curl -m 60 -fsS "https://www.bindingdb.org/rwd/bind/downloads.jsp" 2>/dev/null | grep -oiE "https?://[^\"']*BindingDB_All[_0-9A-Za-z]*_tsv\.zip" | head -1)
  [ -z "$URL" ] && URL=$(curl -m 60 -fsS "https://www.bindingdb.org/bind/downloads.jsp" 2>/dev/null | grep -oiE "https?://[^\"']*BindingDB_All[_0-9A-Za-z]*_tsv\.zip" | head -1)
  echo "BindingDB URL: ${URL:-<none found>}"
  [ -z "$URL" ] && { echo "could not resolve BindingDB URL"; exit 1; }
  curl -m 3600 -fsS -o bindingdb.zip "$URL"
  SHA=$(sha256sum bindingdb.zip | awk '{print $1}')
  unzip -o -q bindingdb.zip
  TSV=$(ls -S *.tsv | head -1)
  echo "TSV: $TSV"
  "$PY" - "$TSV" <<'PYEOF'
import sys, csv, json
csv.field_size_limit(10**9)
tsv = sys.argv[1]
kept = []
n = 0
cols = None
def peptidic(smiles, name):
    if not smiles:
        return ('peptide' in (name or '').lower())
    # crude: many amide bonds and moderate size => peptide-like
    amide = smiles.count('C(=O)N') + smiles.count('NC(=O)')
    return amide >= 3 or 'peptide' in (name or '').lower()
with open(tsv, newline='', encoding='utf-8', errors='replace') as fh:
    rd = csv.reader(fh, delimiter='\t')
    header = next(rd)
    idx = {h: i for i, h in enumerate(header)}
    def g(row, key):
        i = idx.get(key);
        return row[i] if (i is not None and i < len(row)) else ''
    smi_key = next((k for k in header if k.strip().lower() in ('ligand smiles','smiles')), None)
    name_key = next((k for k in header if 'name of ligand' in k.lower() or k.lower()=='bindingdb ligand name'), None)
    tgt_key = next((k for k in header if 'target name' in k.lower()), None)
    uni_key = next((k for k in header if 'uniprot' in k.lower() and 'primary' in k.lower()), None)
    for row in rd:
        n += 1
        smi = g(row, smi_key) if smi_key else ''
        nm = g(row, name_key) if name_key else ''
        if not peptidic(smi, nm):
            continue
        rec = {'smiles': smi, 'ligand_name': nm,
               'target': g(row, tgt_key) if tgt_key else '',
               'uniprot': g(row, uni_key) if uni_key else '',
               'Ki_nM': g(row, 'Ki (nM)'), 'Kd_nM': g(row, 'Kd (nM)'),
               'IC50_nM': g(row, 'IC50 (nM)'), 'EC50_nM': g(row, 'EC50 (nM)')}
        kept.append(rec)
with open('bindingdb_peptide_subset.csv','w',newline='') as out:
    w = csv.DictWriter(out, fieldnames=['smiles','ligand_name','target','uniprot','Ki_nM','Kd_nM','IC50_nM','EC50_nM'])
    w.writeheader(); w.writerows(kept)
summary = {'total_rows_scanned': n, 'peptide_subset_rows': len(kept),
           'filter': 'ligand SMILES with >=3 amide motifs or name contains "peptide"',
           'note': 'heuristic peptidic filter; assay protocols not uniform'}
json.dump(summary, open('/opt/cyclic-collect/status/bindingdb_summary.json','w'), indent=2)
print(json.dumps(summary))
PYEOF
  REL=$(date -u +%Y%m)
  put_verified bindingdb_peptide_subset.csv "cyclic_peptide/datasets/bindingdb_peptide/$REL/bindingdb_peptide_subset.csv" >/dev/null
  echo "{\"dataset\":\"bindingdb_peptide\",\"source_url\":\"$URL\",\"zip_sha256\":\"$SHA\",\"release_tag\":\"$REL\"}" > "$STATUS/bindingdb_acquisition.json"
  record bindingdb_peptide ok "$REL"
) || record bindingdb_peptide failed_or_partial

echo "== all datasets attempted; summaries in $STATUS =="
record _collector done
