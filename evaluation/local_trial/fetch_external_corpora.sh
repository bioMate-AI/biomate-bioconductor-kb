#!/bin/bash
# Fetch commercial-safe EXTERNAL domain corpora into the mid-training set. Run on a disk-equipped
# box (NOT the 8GB dev mac). Outputs JSONL {text,source,id} to $OUT and syncs to S3.
set -e
OUT=${OUT:-/opt/dlami/nvme/midtrain_corpus}; mkdir -p "$OUT"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912/midtrain_corpus
PY=${PY:-python3}

# 1) peS2o (ODC-BY, ~40M OA papers / ~42B tok) — bio-relevant slice via HuggingFace
#    pip install datasets; filter to bio venues/keywords to keep a few B tokens.
$PY - <<'EOF'
from datasets import load_dataset; import json,re
BIO=re.compile(r"\b(genom|transcriptom|rna-seq|scrna|variant|proteom|bioinformatic|sequenc|crispr|epigenom|microbiom|gwas|nextflow|bioconductor|single-cell|chip-seq|atac|methyl)\b",re.I)
ds=load_dataset("allenai/peS2o", split="train", streaming=True)  # V2
n=0; f=open("/opt/dlami/nvme/midtrain_corpus/pes2o_bio.jsonl","w")
for r in ds:
    t=r.get("text","")
    if len(t)>500 and BIO.search(t[:2000]):
        f.write(json.dumps({"text":t[:16000],"source":"pes2o","id":r.get("id")})+"\n"); n+=1
    if n>=400000: break   # ~few B tokens
print("peS2o bio docs:",n)
EOF

# 2) PMC OA — oa_comm (commercial) ONLY. NCBI AWS open bucket, no requester-pays.
aws s3 sync s3://pmc-oa-opendata/oa_comm/txt/ "$OUT/pmc_oa_comm/" --no-sign-request --exclude "*" --include "*.txt" || true
# then pack the .txt into jsonl (bio filter optional; oa_comm is already OA/commercial)

# 3) nf-core upstream docs (MIT) — pipeline READMEs/docs
#    git clone --depth 1 --filter=blob:none https://github.com/nf-core/<pipeline> ; extract docs/*.md README.md

# 4) Biostars (CC-BY-4.0) — bulk via API or a published dump; attribute author/site at scale.
#    (Large; stage as a separate pull.)

aws s3 sync "$OUT/" "$S3/" --exclude "*" --include "*.jsonl"
echo "external corpora staged -> $S3"

# 5) PROTOCOL COLLECTIONS (train-safe = CC-BY only). Real protocols = gold decomposition + QC data.
#    Bio-protocol: OA since 2023; keep CC-BY (drop CC-BY-NC). protocols.io: API, per-protocol license,
#    keep CC-BY. STAR Protocols (Cell Press, CC-BY). Protocol Exchange (Nature OPEN repo, CC-BY).
#    DO NOT train on: Nature Protocols (Springer, copyrighted), Current Protocols (Wiley), JoVE.
#    protocols.io API: GET https://www.protocols.io/api/v3/protocols?filter=public  (check license field)
#    -> verbalize steps -> jsonl {text,source=protocol,id}; also emit decomposition SFT (ordered steps).
