#!/bin/bash -ue
touch filtered_compounds.smi
    echo '{}' > pharmacophore_model.json
    printf 'compound_id	smiles	features_matched	feature_types_matched	pass
' > match_report.tsv
    echo '{"n_passed_filter":0}' > summary.json
    cat <<-END_VERSIONS > versions.yml
    "PHARMACOPHORE_FILTERING:PHARMACOPHORE_REPORT":
        python: "3.10.0"
    END_VERSIONS
