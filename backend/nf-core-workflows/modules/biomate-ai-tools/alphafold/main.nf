// AlphaFold - Structure prediction via API
// FREE access to 200M+ pre-computed structures (EBI database)
// Also supports AlphaFold 3 Server (20 jobs/day)

// Retrieve pre-computed structure from AlphaFold DB
process ALPHAFOLD_DB {
    tag "$meta.id"
    label 'process_low'

    input:
    tuple val(meta), val(uniprot_id)

    output:
    tuple val(meta), path("*.pdb"), emit: pdb
    tuple val(meta), path("*.cif"), emit: cif, optional: true
    tuple val(meta), path("*_confidence.json"), emit: confidence, optional: true
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Download structure from AlphaFold DB
    curl -s "https://alphafold.ebi.ac.uk/files/AF-${uniprot_id}-F1-model_v4.pdb" \\
        -o ${prefix}.pdb

    # Download confidence scores
    curl -s "https://alphafold.ebi.ac.uk/files/AF-${uniprot_id}-F1-confidence_v4.json" \\
        -o ${prefix}_confidence.json || true

    # Check if structure exists
    if ! grep -q "^ATOM" ${prefix}.pdb 2>/dev/null; then
        echo "ERROR: Structure not found for ${uniprot_id}"
        echo "This protein may not be in AlphaFold DB (200M structures)"
        exit 1
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        alphafold_db: "v4"
    END_VERSIONS
    """
}

// Submit to AlphaFold 3 Server (for complexes, new predictions)
// FREE, 20 jobs/day limit
process ALPHAFOLD3_SERVER {
    tag "$meta.id"
    label 'process_low'

    input:
    tuple val(meta), path(fasta)
    path ligand, stageAs: 'ligand.*'  // optional

    output:
    tuple val(meta), path("*_af3_input.json"), emit: input_json
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Format input for AlphaFold 3 Server
    python3 << 'EOF'
import json

# Read FASTA
sequences = []
with open("${fasta}") as f:
    current_seq = ""
    current_name = ""
    for line in f:
        if line.startswith(">"):
            if current_seq:
                sequences.append({"name": current_name, "sequence": current_seq})
            current_name = line[1:].strip().split()[0]
            current_seq = ""
        else:
            current_seq += line.strip()
    if current_seq:
        sequences.append({"name": current_name, "sequence": current_seq})

# Format for AF3 Server
af3_input = {
    "name": "${prefix}",
    "sequences": [{"proteinChain": {"sequence": s["sequence"]}} for s in sequences],
    "modelSeeds": [1]
}

with open("${prefix}_af3_input.json", "w") as f:
    json.dump(af3_input, f, indent=2)

print("Input formatted for AlphaFold 3 Server")
print("Submit at: https://alphafoldserver.com")
print("Free limit: 20 jobs/day")
EOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        alphafold3_server: "1.0"
    END_VERSIONS
    """
}
