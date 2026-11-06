#!/bin/bash
B=s3://biomate-nextflow-work/cyclic_peptide/allatom/k
mkdir -p /w/f2 /w/f3 /w/fa
aws s3 sync $B/k_fetch2_20261029_120357/out /w/f2 --only-show-errors
aws s3 sync $B/k_fetch3_20261029_121656/out /w/f3 --only-show-errors
aws s3 sync $B/k_fetcharxiv_20261029_121720/out /w/fa --only-show-errors
python3.11 tier_audit_context.py knowledge_kb_v1.json /w/f2,/w/f3,/w/fa $OUT/tier_audit_context.json > $OUT/tier_audit_context.log 2>&1; echo "ctx_rc=$?" >> $OUT/steps.log
