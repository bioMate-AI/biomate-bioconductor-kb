#!/usr/bin/env bash
# Streams GSE49712 / SRP028705 paired-end FASTQs from ENA directly into
# s3://biomate-workflow-inputs/tutorial-gold/transcriptomics/GSE49712/fastq/
# without staging locally. 10 PE samples, ~170 GB compressed total.
set -euo pipefail

DEST_BUCKET=s3://biomate-workflow-inputs/tutorial-gold/transcriptomics/GSE49712
LOG_DIR=/tmp/gse49712_mirror
mkdir -p "$LOG_DIR"

# (SRR, sample_id, condition)
SAMPLES=(
  "SRR950078 A_rep1 A"
  "SRR950080 A_rep2 A"
  "SRR950082 A_rep3 A"
  "SRR950084 A_rep4 A"
  "SRR950086 A_rep5 A"
  "SRR950079 B_rep1 B"
  "SRR950081 B_rep2 B"
  "SRR950083 B_rep3 B"
  "SRR950085 B_rep4 B"
  "SRR950087 B_rep5 B"
)

stream_one() {
  local srr=$1 sample=$2
  for mate in 1 2; do
    local url="https://ftp.sra.ebi.ac.uk/vol1/fastq/${srr:0:6}/${srr}/${srr}_${mate}.fastq.gz"
    local key="${DEST_BUCKET}/fastq/${sample}_${mate}.fastq.gz"
    echo "[$(date +%H:%M:%S)] $sample mate $mate -> $key" | tee -a "$LOG_DIR/${sample}.log"
    # ENA serves redirects; -L follows; pipe straight into s3.
    curl -sSL --retry 5 --retry-delay 5 "$url" \
      | aws s3 cp --quiet --expected-size 11000000000 - "$key"
    echo "[$(date +%H:%M:%S)] done $sample mate $mate" | tee -a "$LOG_DIR/${sample}.log"
  done
}

# Write samplesheet (nf-core/rnaseq format) + contrasts CSV
SS=/tmp/gse49712_samplesheet.csv
CT=/tmp/gse49712_contrasts.csv
cat > "$SS" <<'EOF'
sample,fastq_1,fastq_2,strandedness,condition
EOF
for row in "${SAMPLES[@]}"; do
  read -r srr sample cond <<<"$row"
  echo "${sample},${DEST_BUCKET}/fastq/${sample}_1.fastq.gz,${DEST_BUCKET}/fastq/${sample}_2.fastq.gz,auto,${cond}" >> "$SS"
done
cat > "$CT" <<'EOF'
id,variable,reference,target,blocking
B_vs_A,condition,A,B,
EOF
aws s3 cp "$SS" "${DEST_BUCKET}/samplesheet.csv"
aws s3 cp "$CT" "${DEST_BUCKET}/contrasts.csv"
echo "[$(date +%H:%M:%S)] samplesheet + contrasts uploaded"

# Stream samples in parallel (5 at a time keeps a single 1-2 Gbps link saturated)
N_PARALLEL=4
pids=()
for row in "${SAMPLES[@]}"; do
  read -r srr sample cond <<<"$row"
  stream_one "$srr" "$sample" &
  pids+=($!)
  while (( $(jobs -rp | wc -l) >= N_PARALLEL )); do
    sleep 5
  done
done
wait "${pids[@]}"
echo "[$(date +%H:%M:%S)] ALL DONE — verify with: aws s3 ls ${DEST_BUCKET}/fastq/ --recursive --human-readable"
