#!/bin/bash
# DEPRECATED (2026-10-04): the JSP-scrape URL resolution here is brittle and produced a
# stub status marker. Use `collect_binding_affinity.py` instead -- it fetches BindingDB
# via the stable dated-zip URL (or the verified S3 copy), adds the ChEMBL peptide pull,
# applies RDKit structural peptide/cyclic classification, and merges into one labeled table.
# Focused BindingDB peptide-subset collector (the one dataset that failed URL resolution
# in the first collect_cyclic_datasets.sh run). Self-contained: installs AWS CLI v2 + deps,
# resolves the current All-TSV, extracts a heuristic peptidic subset, uploads verified.
set -uo pipefail
export AWS_DEFAULT_REGION=us-west-2
export DEBIAN_FRONTEND=noninteractive
ROOT=/opt/bindingdb-collect
BUCKET=knowledge-datasets-1759951976
STATUS="$ROOT/status"
mkdir -p "$ROOT" "$STATUS"
exec > >(tee -a "$STATUS/bindingdb.log") 2>&1
echo "== bindingdb collector start $(date -u +%FT%TZ) =="
systemd-run --unit=bdb-deadline --on-active="${MAX_RUNTIME:-3h}" /sbin/shutdown -h now || true
sync_status() { aws s3 sync "$STATUS" "s3://$BUCKET/cyclic_peptide/datasets/_collect_status/" --only-show-errors || true; }
trap 'rc=$?; echo "== exit rc=$rc =="; sync_status; shutdown -h now; exit $rc' EXIT

for a in 1 2 3 4 5; do apt-get -o DPkg::Lock::Timeout=300 update -qq && break; sleep 10; done
apt-get -o DPkg::Lock::Timeout=300 install -y -qq python3-venv unzip curl
command -v aws >/dev/null 2>&1 || { curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip; (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
python3 -m venv "$ROOT/venv"; PY="$ROOT/venv/bin/python"
"$ROOT/venv/bin/pip" install -q --disable-pip-version-check 'pip==25.0.1'

cd "$ROOT"
REL_PATH=$(curl -m 60 -fsSL "https://www.bindingdb.org/rwd/bind/chemsearch/marvin/Download.jsp" 2>/dev/null | grep -oiE "/rwd/bind/downloads/BindingDB_All_[0-9]+_tsv\.zip" | head -1)
[ -z "$REL_PATH" ] && { echo "URL unresolved"; echo '{"dataset":"bindingdb_peptide","status":"failed","detail":"url_unresolved"}' > "$STATUS/bindingdb_peptide.json"; exit 1; }
URL="https://www.bindingdb.org${REL_PATH}"
REL=$(echo "$REL_PATH" | grep -oE "[0-9]+")
echo "BindingDB URL: $URL (release $REL)"
curl -m 5400 -fsS -o bindingdb.zip "$URL"
ZSHA=$(sha256sum bindingdb.zip | awk '{print $1}')
unzip -o -q bindingdb.zip
TSV=$(ls -S *.tsv | head -1); echo "TSV: $TSV"

"$PY" - "$TSV" <<'PYEOF'
import sys, csv, json
csv.field_size_limit(10**9)
tsv = sys.argv[1]
kept, n = [], 0
def peptidic(smiles, name):
    if not smiles: return 'peptide' in (name or '').lower()
    return (smiles.count('C(=O)N') + smiles.count('NC(=O)')) >= 3 or 'peptide' in (name or '').lower()
with open(tsv, newline='', encoding='utf-8', errors='replace') as fh:
    rd = csv.reader(fh, delimiter='\t'); header = next(rd)
    idx = {h: i for i, h in enumerate(header)}
    def g(row, key):
        i = idx.get(key); return row[i] if (i is not None and i < len(row)) else ''
    smi_key = next((k for k in header if k.strip().lower() in ('ligand smiles','smiles')), None)
    name_key = next((k for k in header if 'name of ligand' in k.lower() or k.lower()=='bindingdb ligand name'), None)
    tgt_key = next((k for k in header if 'target name' in k.lower()), None)
    uni_key = next((k for k in header if 'uniprot' in k.lower() and 'primary' in k.lower()), None)
    for row in rd:
        n += 1
        smi = g(row, smi_key) if smi_key else ''; nm = g(row, name_key) if name_key else ''
        if not peptidic(smi, nm): continue
        kept.append({'smiles': smi, 'ligand_name': nm,
                     'target': g(row, tgt_key) if tgt_key else '', 'uniprot': g(row, uni_key) if uni_key else '',
                     'Ki_nM': g(row,'Ki (nM)'), 'Kd_nM': g(row,'Kd (nM)'), 'IC50_nM': g(row,'IC50 (nM)'), 'EC50_nM': g(row,'EC50 (nM)')})
with open('bindingdb_peptide_subset.csv','w',newline='') as out:
    w = csv.DictWriter(out, fieldnames=['smiles','ligand_name','target','uniprot','Ki_nM','Kd_nM','IC50_nM','EC50_nM'])
    w.writeheader(); w.writerows(kept)
json.dump({'total_rows_scanned': n, 'peptide_subset_rows': len(kept),
           'filter':'ligand SMILES with >=3 amide motifs or name contains "peptide"',
           'note':'heuristic peptidic filter; assay protocols not uniform'},
          open('/opt/bindingdb-collect/status/bindingdb_summary.json','w'), indent=2)
print('scanned', n, 'kept', len(kept))
PYEOF

SHA=$(sha256sum bindingdb_peptide_subset.csv | awk '{print $1}')
aws s3 cp bindingdb_peptide_subset.csv "s3://$BUCKET/cyclic_peptide/datasets/bindingdb_peptide/$REL/bindingdb_peptide_subset.csv" --only-show-errors
aws s3 cp "s3://$BUCKET/cyclic_peptide/datasets/bindingdb_peptide/$REL/bindingdb_peptide_subset.csv" /tmp/rb.csv --only-show-errors
[ "$SHA" = "$(sha256sum /tmp/rb.csv | awk '{print $1}')" ] || { echo "READBACK MISMATCH"; exit 1; }
echo "{\"dataset\":\"bindingdb_peptide\",\"source_url\":\"$URL\",\"release\":\"$REL\",\"zip_sha256\":\"$ZSHA\",\"subset_sha256\":\"$SHA\"}" > "$STATUS/bindingdb_acquisition.json"
echo '{"dataset":"bindingdb_peptide","status":"ok","release":"'"$REL"'"}' > "$STATUS/bindingdb_peptide.json"
sync_status
echo "== bindingdb done =="
