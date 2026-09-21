#!/bin/bash
# Build the FULL prepared mid-training corpus on a disk box, then stage to S3.
# Corrects the under-built corpus: (1) includes wkg_corpus (was staged AFTER the last concat),
# (2) recovers internal_corpus's workflow+skill text (the old concat dropped ALL of internal to
# avoid tool dupes, losing workflow/skill knowledge too), (3) adds the external literature
# (peS2o bio slice — peS2o already subsumes PMC OA), (4) builds the general-replay corpus for the
# 25/75 anti-forgetting mixture. Per-source token accounting -> manifest. Best-effort per external
# source (one failure never kills the build). Self-terminating via the launcher's shutdown.
set -uo pipefail
SCRATCH=${SCRATCH:-/opt/dlami/nvme}
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
MC="$SCRATCH/midtrain_corpus"; mkdir -p "$MC"
PES2O_DOCS=${PES2O_DOCS:-600000}      # bio-filtered OA papers (~1-2B tok)
REPLAY_DOCS=${REPLAY_DOCS:-550000}    # FineWeb-Edu general replay (~3x domain, for 25/75 mix)

echo "[build] $(date) pull staged prepared corpora from S3"
# everything staged EXCEPT the old combined file and the raw internal (handled specially below)
aws s3 sync "$S3/midtrain_corpus/" "$MC/" --exclude "midtrain_all.jsonl" --quiet

echo "[build] recover internal workflow+skill text (drop internal's tool rows — superseded by tools_corpus)"
python3 - "$MC/internal_corpus.jsonl" "$MC/internal_wf_skill.jsonl" <<'PYEOF'
import sys, json
src, dst = sys.argv[1], sys.argv[2]
kept = 0
try:
    with open(src) as f, open(dst, "w") as g:
        for line in f:
            try: r = json.loads(line)
            except: continue
            if r.get("source") in ("workflow", "skill"):
                g.write(json.dumps({"text": r.get("text", "")}) + "\n"); kept += 1
    print("internal_wf_skill docs:", kept)
except FileNotFoundError:
    print("internal_corpus.jsonl absent — skipping"); open(dst, "w").close()
PYEOF
rm -f "$MC/internal_corpus.jsonl"   # exclude the raw combined internal from the concat (dupes tools)

echo "[build] fetch peS2o bio slice (best-effort; peS2o subsumes PMC OA)"
python3 - "$MC/pes2o_bio.jsonl" "$PES2O_DOCS" <<'PYEOF' || echo "[build] peS2o fetch failed — continuing without it"
import sys, json, re
from datasets import load_dataset
out, cap = sys.argv[1], int(sys.argv[2])
BIO = re.compile(r"\b(genom|transcriptom|rna-seq|scrna|single-cell|variant|proteom|metabolom|"
                 r"bioinformatic|sequenc|crispr|epigenom|microbiom|gwas|nextflow|bioconductor|"
                 r"chip-seq|atac|methyl|phylogen|immunolog|pharmacokinet|admet|docking)\b", re.I)
ds = None
for cfg in ("v2", "v3", "default", None):
    try:
        ds = load_dataset("allenai/peS2o", cfg, split="train", streaming=True) if cfg \
             else load_dataset("allenai/peS2o", split="train", streaming=True)
        print("peS2o config:", cfg); break
    except Exception as e:
        print("peS2o config", cfg, "failed:", str(e)[:120])
if ds is None: raise SystemExit("no working peS2o config")
n = 0
with open(out, "w") as f:
    for r in ds:
        t = r.get("text", "")
        if len(t) > 500 and BIO.search(t[:2000]):
            f.write(json.dumps({"text": t[:16000]}) + "\n"); n += 1
        if n >= cap: break
print("peS2o bio docs:", n)
PYEOF

echo "[build] fetch general-replay (FineWeb-Edu, ODC-BY) for the 25/75 mixture"
python3 - "$MC/general_replay.jsonl" "$REPLAY_DOCS" <<'PYEOF' || echo "[build] replay fetch failed — continuing"
import sys, json
from datasets import load_dataset
out, cap = sys.argv[1], int(sys.argv[2])
ds = load_dataset("HuggingFaceFW/fineweb-edu", "sample-10BT", split="train", streaming=True)
n = 0
with open(out, "w") as f:
    for r in ds:
        t = r.get("text", "")
        if len(t) > 300: f.write(json.dumps({"text": t[:16000]}) + "\n"); n += 1
        if n >= cap: break
print("general_replay docs:", n)
PYEOF

echo "[build] concat + global dedup DOMAIN corpus (replay stays separate) -> midtrain_all.jsonl + manifest"
python3 - "$MC" <<'PYEOF'
import os, sys, glob, json, hashlib
D = sys.argv[1]
REPLAY = "general_replay.jsonl"   # NOT part of the domain corpus; used at train time via --replay
out = os.path.join(D, "midtrain_all.jsonl")
man = {}; seen = set(); total_docs = total_tok = 0
with open(out, "w") as fo:
    for p in sorted(glob.glob(os.path.join(D, "*.jsonl"))):
        b = os.path.basename(p)
        if b in ("midtrain_all.jsonl", REPLAY): continue
        src = b.replace("_corpus.jsonl", "").replace(".jsonl", "")
        nd = nt = 0
        for line in open(p):
            try: t = json.loads(line).get("text", "")
            except: continue
            if len(t) < 80: continue
            h = hashlib.sha256(t.encode()).hexdigest()[:16]
            if h in seen: continue
            seen.add(h); fo.write(json.dumps({"text": t}) + "\n")
            nd += 1; nt += len(t) // 4
        man[src] = {"docs": nd, "~tok": nt}; total_docs += nd; total_tok += nt
        print(f"  {src:22s} {nd:>8d} docs  ~{nt/1e6:6.2f}M tok")
man["TOTAL"] = {"docs": total_docs, "~tok": total_tok}
json.dump(man, open(os.path.join(D, "manifest.json"), "w"), indent=2)
print(f"midtrain_all.jsonl: {total_docs} docs, ~{total_tok/1e6:.1f}M tokens")
PYEOF

echo "[build] stage full corpus + new pieces + manifest to S3"
aws s3 cp "$MC/midtrain_all.jsonl" "$S3/midtrain_corpus/midtrain_all.jsonl" --quiet
aws s3 cp "$MC/manifest.json"      "$S3/midtrain_corpus/manifest.json" --quiet
for f in pes2o_bio.jsonl general_replay.jsonl internal_wf_skill.jsonl; do
  [ -s "$MC/$f" ] && aws s3 cp "$MC/$f" "$S3/midtrain_corpus/$f" --quiet
done
echo "BUILD_FULL_CORPUS_DONE"
