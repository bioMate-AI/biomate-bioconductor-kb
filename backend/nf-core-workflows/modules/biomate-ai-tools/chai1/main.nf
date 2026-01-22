// Chai-1 - Multi-modal biomolecular structure prediction
// Supports: proteins, DNA, RNA, ligands, glycans
// Requires: GPU with 24-80GB VRAM

process CHAI1 {
    tag "$meta.id"
    label 'process_gpu'
    label 'process_high_memory'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/chai1:latest'

    input:
    tuple val(meta), path(fasta)
    path ligand, stageAs: 'ligand.*'  // optional: SDF or SMILES

    output:
    tuple val(meta), path("output/*.pdb"), emit: pdb
    tuple val(meta), path("output/*.cif"), emit: cif, optional: true
    tuple val(meta), path("output/scores*.json"), emit: scores, optional: true
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def ligand_arg = ligand ? "--ligand ${ligand}" : ""
    """
    mkdir -p output

    python -m chai_lab.main \\
        --fasta ${fasta} \\
        ${ligand_arg} \\
        --output output/

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        chai1: \$(pip show chai_lab 2>/dev/null | grep Version | cut -d' ' -f2 || echo "0.6.1")
    END_VERSIONS
    """
}
