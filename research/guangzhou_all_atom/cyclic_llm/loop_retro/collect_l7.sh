#!/bin/bash
# Collect every L7 result prefix from S3 and aggregate. usage: collect_l7.sh [OUTDIR]  (default: results/l7_collect)
B=s3://biomate-nextflow-work/cyclic_peptide/loop_retro; O=${1:-results/l7_collect}; mkdir -p $O/small $O/llm
for p in $(aws s3 ls $B/ | awk '/PRE res7[af]_/{print $2}' | tr -d '/'); do mkdir -p $O/small/$p; aws s3 sync $B/$p/ $O/small/$p/ --exclude "*.log" --exclude "*.flag" --only-show-errors; done
aws s3 sync $B/res7a_llm/ $O/llm/ --only-show-errors
SMALL=$(ls -d $O/small/*/ | tr '\n' ',' | sed 's/,$//')
python3 aggregate_l7.py results/l7_aggregate.json --small "$SMALL" --llm $O/llm --rounds-llm 5
