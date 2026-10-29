#!/bin/bash
# EC2 job: merge the three fetch outputs, build + verify the KB, run the unit tests, run the group-A direction check.
B=s3://biomate-nextflow-work/cyclic_peptide/allatom/k
mkdir -p /w/f2 /w/f3 /w/fa
aws s3 sync $B/k_fetch2_20261029_120357/out /w/f2 --only-show-errors
aws s3 sync $B/k_fetch3_20261029_121656/out /w/f3 --only-show-errors
aws s3 sync $B/k_fetcharxiv_20261029_121720/out /w/fa --only-show-errors
PY=python3.11
$PY build_kb.py /w/f2,/w/f3,/w/fa $OUT > $OUT/build.log 2>&1; echo "build_rc=$?" >> $OUT/steps.log
FETCH_DIR=/w/f2,/w/f3,/w/fa KB_PATH=$OUT/knowledge_kb_v1.json $PY -m unittest -v test_knowledge > $OUT/unittest.log 2>&1; echo "unittest_rc=$?" >> $OUT/steps.log
if [ -f annotations.csv.gz ] && [ -f source_groups_v2.json ]; then
  $PY direction_check.py $OUT/knowledge_kb_v1.json annotations.csv.gz source_groups_v2.json $OUT > $OUT/direction_check.log 2>&1; echo "direction_rc=$?" >> $OUT/steps.log
fi
