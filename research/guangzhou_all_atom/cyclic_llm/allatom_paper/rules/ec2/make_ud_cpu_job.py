#!/usr/bin/env python3
"""Generic one-shot CPU job (spot): fetch code + tokenizer + CycPeptMPDB, run a command, upload /w/result, terminate. usage: make_ud_cpu_job.py OUT.sh RUN_ID CAP_MIN 'command run from allatom_paper/rules'"""
import sys
out, run, cap, cmd = sys.argv[1:5]
B = f"s3://biomate-nextflow-work/cyclic_peptide/allatom/u1/{run}"
open(out, "w").write(f'''#!/bin/bash
B={B}
exec > /var/log/ud.log 2>&1; set -x
shutdown -h +{cap}
( while true; do aws s3 cp /var/log/ud.log $B/boot.log --only-show-errors; aws s3 sync /w/result $B/result/ --only-show-errors; sleep 20; done ) &
SYNC=$!
dnf install -y python3.11 python3.11-pip python3.11-devel gcc >/dev/null 2>&1
python3.11 -m pip install -q numpy scipy scikit-learn rdkit pytest 2>&1 | tail -1
mkdir -p /w/result /w/data /w/tok /w/code && cd /w
aws s3 cp $B/code.tgz /w/code.tgz --only-show-errors && tar xzf /w/code.tgz -C /w/code 2>/dev/null
aws s3 cp s3://biomate-nextflow-work/cyclic_peptide/allatom/u1/dev2/tok/ /w/tok/ --recursive --only-show-errors
aws s3 cp s3://biomate-nextflow-work/cyclic_peptide/loop_retro/data/CycPeptMPDB_Peptide_All.csv /w/data/ --only-show-errors
export CPM_CSV=/w/data/CycPeptMPDB_Peptide_All.csv MONO_JSON=/w/code/v4_eval/monomer_dictionary_v5.json CHEMFM_TOK=/w/tok/tokenizer.json PYTHONHASHSEED=0
cd /w/code/allatom_paper/rules
{cmd} > /w/result/job.log 2>&1; echo "rc=$?" >> /w/result/job.log
aws s3 sync /w/result $B/result/ --only-show-errors; echo DONE > /w/done.flag; aws s3 cp /w/done.flag $B/done.flag --only-show-errors
kill $SYNC; aws s3 cp /var/log/ud.log $B/boot_final.log --only-show-errors; shutdown -h now
''')
print("wrote", out)
