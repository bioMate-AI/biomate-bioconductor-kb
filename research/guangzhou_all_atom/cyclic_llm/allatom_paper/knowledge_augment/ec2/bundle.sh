#!/bin/bash
# tar + upload only (no compute). usage: bundle.sh RUN_ID
set -e
RUN=${1:-dev1}; B=s3://biomate-nextflow-work/cyclic_peptide/allatom/ka/$RUN
cd "$(git rev-parse --show-toplevel)/research/guangzhou_all_atom/cyclic_llm"
COPYFILE_DISABLE=1 tar czf /tmp/ka_code_$RUN.tgz allatom_paper kb_audit/peptide_sar_rules_v1.json v4_eval/monomer_dictionary_v5.json generation_pilot/gen_pilot.py ihlm/symbolic.py ihlm/__init__.py stratification/data/annotations.csv.gz
aws s3 cp /tmp/ka_code_$RUN.tgz $B/code.tgz --only-show-errors && echo uploaded $B/code.tgz
