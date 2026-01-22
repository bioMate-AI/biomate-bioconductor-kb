// Boltz-2 - Protein-ligand structure prediction with binding affinity
// Requires: GPU with 16-40GB VRAM

process BOLTZ {
    tag "$meta.id"
    label 'process_gpu'
    label 'process_high_memory'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/boltz:latest'

    input:
    tuple val(meta), path(fasta)
    path ligand_sdf, stageAs: 'ligand.sdf'  // optional

    output:
    tuple val(meta), path("output/*.pdb"), emit: pdb
    tuple val(meta), path("output/*.cif"), emit: cif, optional: true
    tuple val(meta), path("output/affinity*.json"), emit: affinity, optional: true
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def ligand_arg = ligand_sdf ? "--ligand ${ligand_sdf}" : ""
    """
    mkdir -p output

    boltz predict \\
        --fasta ${fasta} \\
        ${ligand_arg} \\
        --output output/ \\
        --num_workers ${task.cpus}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        boltz: \$(boltz --version 2>&1 | grep -oP '\\d+\\.\\d+\\.\\d+' || echo "2.2.1")
    END_VERSIONS
    """
}
