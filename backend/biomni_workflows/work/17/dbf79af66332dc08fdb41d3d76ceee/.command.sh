#!/bin/bash -ue
echo '{"n_features":4,"features":[]}' > pharmacophore_model.json
cat <<-END_VERSIONS > versions.yml
"PHARMACOPHORE_FILTERING:PHARMACOPHORE_GENERATE":
    rdkit: "2023.09.4"
    python: "3.10.0"
END_VERSIONS
