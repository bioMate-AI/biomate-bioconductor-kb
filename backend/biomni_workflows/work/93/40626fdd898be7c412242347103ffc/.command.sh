#!/bin/bash -ue
printf 'compound_id	smiles	features_matched	feature_types_matched	pass
' > match_report.tsv
    echo '{"n_screened":10,"n_passed":5}' > screened_scores.json
    cat <<-END_VERSIONS > versions.yml
    "PHARMACOPHORE_FILTERING:PHARMACOPHORE_SCREEN":
        rdkit: "2023.09.4"
        python: "3.10.0"
    END_VERSIONS
