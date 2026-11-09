#!/bin/bash
# Radiology radiomics: build the image, run the tests, verify against PyRadiomics' baselines and the IBSI phantom,
# run the Nextflow workflow end to end on two real cases, and push the image ONLY if everything passes.
# SPOT, self-terminating, log streamed to S3. Estimated: c5.2xlarge spot about 25 minutes.
set -uxo pipefail
( sleep 5400; shutdown -h now ) &
LOG=/var/log/radiology_verify.log; exec > >(tee -a "$LOG") 2>&1
export AWS_DEFAULT_REGION=us-west-2
B=knowledge-datasets-1759951976
SRC=s3://$B/biomate_workflow_verification/radiology_20261101/code/
OUT=s3://$B/biomate_workflow_verification/radiology_20261101/results/
REPO=399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-radiology
cleanup(){ aws s3 cp "$LOG" "${OUT}run.log" 2>/dev/null || true; shutdown -h now; }
trap cleanup EXIT
( while true; do aws s3 cp "$LOG" "${OUT}run.log" 2>/dev/null; sleep 45; done ) &
W=/opt/rad; mkdir -p $W/out $W/data /tmp/refs
dnf install -y docker java-17-amazon-corretto-headless git >/dev/null 2>&1; systemctl start docker
curl -s https://get.nextflow.io | bash && mv nextflow /usr/local/bin/ && chmod +x /usr/local/bin/nextflow
aws s3 sync "$SRC" $W/ --quiet
echo "=== $(date -u) BUILD"
docker build --platform linux/amd64 -t rad:test $W/docker 2>&1 | tail -15; BUILD_RC=${PIPESTATUS[0]}
echo "build_rc=$BUILD_RC" > $W/out/status.txt
echo "=== $(date -u) UNIT TESTS"
docker run --rm rad:test python -m pytest -q /opt/biomate/test_radiomics_extract.py --maxfail=100 -p no:cacheprovider 2>&1 | tee $W/out/tests.log | tail -60; TEST_RC=${PIPESTATUS[0]}
echo "test_rc=$TEST_RC" >> $W/out/status.txt
echo "=== $(date -u) REFERENCE VERIFICATION"
docker run --rm -v /tmp/refs:/tmp/refs -v $W/out:/out rad:test python /opt/biomate/verify_against_references.py --work /tmp/refs --out /out/verification_results.json 2>&1 | tee $W/out/verify.log | tail -40; VER_RC=${PIPESTATUS[0]}
echo "verify_rc=$VER_RC" >> $W/out/status.txt
echo "=== $(date -u) NEXTFLOW END-TO-END (2 real cases)"
cp /tmp/refs/brain1_image.nrrd /tmp/refs/brain1_label.nrrd /tmp/refs/lung1_image.nrrd /tmp/refs/lung1_label.nrrd $W/data/ 2>/dev/null
printf 'patient_id,image,mask,modality\nbrain1,%s/data/brain1_image.nrrd,%s/data/brain1_label.nrrd,MR\nlung1,%s/data/lung1_image.nrrd,%s/data/lung1_label.nrrd,CT\n' $W $W $W $W > $W/data/samplesheet.csv
cat > $W/override.config <<'CFG'
process {
  withName: 'RADIOLOGY_RADIOMICS_EXTRACTION' { container = 'rad:test' }
  withName: 'RADIOLOGY_RADIOMICS_MERGE' { container = 'rad:test' }
}
CFG
cd $W && nextflow run $W/workflow/main.nf -c $W/override.config -profile docker --samplesheet $W/data/samplesheet.csv --outdir $W/out/nf -ansi-log false 2>&1 | tee $W/out/nextflow.log | tail -25; NF_RC=${PIPESTATUS[0]}
echo "nextflow_rc=$NF_RC" >> $W/out/status.txt
# the workflow output must equal a direct run of the tool with the same inputs
docker run --rm -v $W/data:/d -v $W/out:/o rad:test python /opt/biomate/radiomics_extract.py --samplesheet /d/samplesheet.csv --outdir /o/direct 2>&1 | tail -3
python3 - <<'PY' > $W/out/nf_vs_direct.json 2>&1; echo "nf_compare_rc=$?" >> $W/out/status.txt
import csv, json, math
def load(p):
    return {r["patient_id"]: r for r in csv.DictReader(open(p))}
a = load("/opt/rad/out/nf/merged/features_wide_all.csv"); b = load("/opt/rad/out/direct/features_wide.csv")
res = {"patients_nf": sorted(a), "patients_direct": sorted(b), "n_mismatch": 0, "n_compared": 0}
for pid in b:
    for k, v in b[pid].items():
        if k == "patient_id": continue
        res["n_compared"] += 1
        x, y = float(a[pid][k]), float(v)
        if not (x == y or (math.isnan(x) and math.isnan(y)) or abs(x - y) <= 1e-9 * max(1.0, abs(y))): res["n_mismatch"] += 1
print(json.dumps(res)); raise SystemExit(0 if res["n_mismatch"] == 0 and res["patients_nf"] == res["patients_direct"] and res["n_compared"] > 0 else 1)
PY
cat $W/out/nf_vs_direct.json
echo "=== $(date -u) DECISION"
PASS=0
. <(sed 's/=/="/; s/$/"/' $W/out/status.txt)
if [ "$build_rc" = 0 ] && [ "$test_rc" = 0 ] && [ "$verify_rc" = 0 ] && [ "$nextflow_rc" = 0 ] && [ "$nf_compare_rc" = 0 ]; then PASS=1; fi
echo "ALL_PASSED=$PASS" >> $W/out/status.txt
if [ "$PASS" = 1 ]; then
  aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 399683337364.dkr.ecr.us-west-2.amazonaws.com
  docker tag rad:test $REPO:1.0 && docker push $REPO:1.0; echo "push_rc=$?" >> $W/out/status.txt
fi
docker image inspect rad:test --format '{{.Id}}' >> $W/out/status.txt
aws s3 cp $W/out/ "$OUT" --recursive --quiet
cat $W/out/status.txt
