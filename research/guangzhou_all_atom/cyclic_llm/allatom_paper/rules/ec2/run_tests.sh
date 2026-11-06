#!/bin/bash
# runs on the dev box: fetch code, run the U1 tests, upload the log
B=s3://biomate-nextflow-work/cyclic_peptide/allatom/u1/${RUN:-dev2}
rm -rf /w/code && mkdir -p /w/code && cd /w && aws s3 cp $B/code.tgz /w/code.tgz --only-show-errors && tar xzf /w/code.tgz -C /w/code 2>/dev/null
cd /w/code/allatom_paper && CHEMFM_TOK=/w/tok/tokenizer.json python3.11 -m pytest -x -q -s -p no:cacheprovider rules/test_rules.py "$@" > /w/pytest_u1.log 2>&1; echo "rc=$?" >> /w/pytest_u1.log
aws s3 cp /w/pytest_u1.log $B/pytest_u1_$(date +%H%M%S).log --only-show-errors; tail -60 /w/pytest_u1.log
