#!/usr/bin/env python3
"""EC2 user-data generator for Track E (stage-0). usage: make_ud_e.py STAGE OUT.sh [--cap-min N] [--itype ...]
STAGE: prep  (pytest + source groups + smoke)      -> prefix .../allatom/E/<run>/prep
       main  (prep checks, then tune -> eval -> controls; sequential, no bare wait) -> prefix .../allatom/E/<run>/main
One writer per S3 prefix. Spot only; the instance shuts itself down at the end or at the wall-clock cap."""
import argparse, sys
B = "s3://biomate-nextflow-work/cyclic_peptide/allatom/E"
HEAD = """#!/bin/bash
P=__B__/__RUN__/__STAGE__
exec > /var/log/ud.log 2>&1; set -x
shutdown -h +__CAP__
( while true; do aws s3 cp /var/log/ud.log $P/boot.log --only-show-errors; sleep 20; done ) &
BOOT=$!
dnf install -y python3.11 python3.11-pip python3.11-devel gcc >/dev/null 2>&1
python3.11 -m pip install numpy scipy scikit-learn rdkit pandas pytest selfies 2>&1 | tail -2
mkdir -p /w/out /w/code && cd /w
aws s3 cp __B__/__RUN__/code.tgz /w/code.tgz --only-show-errors && tar xzf /w/code.tgz -C /w/code
export ANN_CSV=/w/code/cyclic_llm/stratification/data/annotations.csv.gz PYTHONHASHSEED=0 OMP_NUM_THREADS=1
cd /w/code/cyclic_llm/allatom_paper
( while true; do aws s3 sync /w/out $P/out --only-show-errors; sleep 30; done ) &
SYNC=$!
python3.11 -m pytest -q -p no:cacheprovider test_pmo_harness.py > /w/out/pytest.log 2>&1; echo "pytest rc=$?" >> /w/out/pytest.log
python3.11 track_e/make_groups.py > /w/out/groups.log 2>&1; echo "groups rc=$?" >> /w/out/groups.log; cp track_e/source_groups.json /w/out/ 2>/dev/null
python3.11 track_e/run_stage0.py smoke /w/out/smoke_run --workers 8 --n-ref 5 > /w/out/smoke.log 2>&1; SMOKE=$?; echo "smoke rc=$SMOKE" >> /w/out/smoke.log
"""
QUAL = """python3.11 track_e/make_groups.py v2 > /w/out/groups_v2.log 2>&1; echo "groups_v2 rc=$?" >> /w/out/groups_v2.log; cp track_e/source_groups_v2.json /w/out/ 2>/dev/null
python3.11 track_e/verifier_quality.py /w/out/verifier_quality_v2.json v2 > /w/out/vq_v2.log 2>&1; echo "vq rc=$?" >> /w/out/vq_v2.log
"""
MAIN = """if [ $SMOKE -eq 0 ]; then
  python3.11 track_e/run_stage0.py tune /w/out/run --budget 1000 --seeds 100-102 > /w/out/tune.log 2>&1; echo "tune rc=$?" >> /w/out/tune.log
  python3.11 track_e/run_stage0.py eval /w/out/run --budget 1000 --seeds 0-9 > /w/out/eval.log 2>&1; echo "eval rc=$?" >> /w/out/eval.log
  python3.11 track_e/run_stage0.py controls /w/out/run --budget 1000 --seeds 0-4 > /w/out/controls.log 2>&1; echo "controls rc=$?" >> /w/out/controls.log
else echo SMOKE_FAILED > /w/out/SMOKE_FAILED; fi
"""
TUNE = """if [ $SMOKE -eq 0 ]; then
  python3.11 track_e/run_stage0.py tune /w/out/run --budget 1000 --seeds 100-102 > /w/out/tune.log 2>&1; echo "tune rc=$?" >> /w/out/tune.log
  python3.11 - <<'PY' > /w/out/tuned_write.log 2>&1
import json, sys
sys.path.insert(0, 'track_e'); sys.argv = ['x', 'tune', '/w/out/run']
import run_stage0 as R
t = R.best_cfgs('/w/out/run'); json.dump(t, open('/w/out/tuned.json', 'w'), indent=1); print('tuned written', {f: len(v) for f, v in t.items()})
PY
else echo SMOKE_FAILED > /w/out/SMOKE_FAILED; fi
"""
EVAL = """cd /w/code/cyclic_llm/allatom_paper
python3.11 -m pytest -q -p no:cacheprovider test_pmo_harness.py > /w/out/pytest.log 2>&1; PT=$?; echo "pytest rc=$PT" >> /w/out/pytest.log
if [ $PT -ne 0 ]; then echo PYTEST_FAILED > /w/out/PYTEST_FAILED; else
cp track_e/tuned.json /w/out/tuned_used.json
python3.11 track_e/run_stage0.py eval /w/out/run --budget 1000 --seeds 0-9 --cfg track_e/tuned.json --groups __GROUPS__ --n-ref 20 --max-seconds 14400 > /w/out/eval.log 2>&1; echo "eval rc=$?" >> /w/out/eval.log
python3.11 track_e/run_stage0.py controls /w/out/run --budget 1000 --seeds 0-4 --cfg track_e/tuned.json --groups __GROUPS__ --n-ref 20 --max-seconds 14400 > /w/out/controls.log 2>&1; echo "controls rc=$?" >> /w/out/controls.log
fi
SMOKE=0
"""
BW = """python3.11 track_e/bw_psa.py /w/out/bw_psa.jsonl --deadline-min 95 --n-conf 60 > /w/out/bw_psa.log 2>&1; echo "bw rc=$?" >> /w/out/bw_psa.log
curl -sL -o /w/out/CycPeptMPDB-4D.csv "https://zenodo.org/records/21274695/files/CycPeptMPDB-4D.csv?download=1"; md5sum /w/out/CycPeptMPDB-4D.csv > /w/out/4d_md5.txt
python3.11 track_e/bw_eval.py /w/out/bw_psa.jsonl /w/out/bw_eval.json /w/out/CycPeptMPDB-4D.csv > /w/out/bw_eval.log 2>&1; echo "eval rc=$?" >> /w/out/bw_eval.log
SMOKE=0
"""
TUNE2 = """mkdir -p /w/out/run
aws s3 sync s3://biomate-nextflow-work/cyclic_peptide/allatom/E/__RESUME_FROM__/tune/out/run /w/out/run --only-show-errors
rm -f /w/out/run/tune/F1/edit_ga#* /w/out/run/tune/F2/edit_ga#*            # produced under the buggy (non-terminating) edit_ga: redo under the fixed code
echo "resumed tune files: $(find /w/out/run/tune -name '*.json' | wc -l)" > /w/out/resume.log
python3.11 track_e/run_stage0.py tune /w/out/run --budget 1000 --seeds 100-102 > /w/out/tune.log 2>&1; echo "tune rc=$?" >> /w/out/tune.log
python3.11 - <<'PY' > /w/out/tuned_write.log 2>&1
import json, sys
sys.path.insert(0, 'track_e'); sys.argv = ['x', 'tune', '/w/out/run']
import run_stage0 as R
t = R.best_cfgs('/w/out/run'); json.dump(t, open('/w/out/tuned.json', 'w'), indent=1); print('tuned written', {f: len(v) for f, v in t.items()})
PY
SMOKE=0
"""
TAIL = """echo DONE > /w/out/done.flag
aws s3 sync /w/out $P/out --only-show-errors
kill $SYNC $BOOT
aws s3 cp /var/log/ud.log $P/boot.log --only-show-errors
shutdown -h now
"""
if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("stage", choices=["prep", "main", "quality", "tune", "eval", "bw", "tune2"]); ap.add_argument("out"); ap.add_argument("--run", default="r1"); ap.add_argument("--cap-min", type=int, default=240); ap.add_argument("--groups", default="v2"); ap.add_argument("--resume-from", default="r8")
    a = ap.parse_args()
    if a.stage == "quality":
        head = HEAD.split("python3.11 -m pytest")[0]
        s = head + QUAL + "SMOKE=0\n" + TAIL
    elif a.stage == "tune":
        s = HEAD + TUNE + TAIL
    elif a.stage == "tune2":
        head = HEAD.split("python3.11 -m pytest")[0]
        s = head + TUNE2.replace("__RESUME_FROM__", a.resume_from) + TAIL
    elif a.stage == "bw":
        head = HEAD.split("python3.11 -m pytest")[0]
        s = head + BW + TAIL
    elif a.stage == "eval":
        head = HEAD.split("python3.11 -m pytest")[0]
        s = head + EVAL.replace("__GROUPS__", a.groups) + TAIL
    else:
        s = HEAD + (MAIN if a.stage == "main" else "") + TAIL
    s = s.replace("__B__", B).replace("__RUN__", a.run).replace("__STAGE__", a.stage).replace("__CAP__", str(a.cap_min))
    open(a.out, "w").write(s); print("wrote", a.out)
