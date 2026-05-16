// scFv-pMPNN - AI-powered antibody sequence design
// Uses ProteinMPNN for sequence design, optionally AF2 for structure validation

// [Phase A] Antibody Sequence Design
process SCFV_DESIGN {
    tag "$meta.id"
    label 'process_gpu'
    label 'process_high_memory'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/scfv-pmpnn:nextflow'

    input:
    tuple val(meta), path(target_pdb)  // Target antigen structure

    output:
    tuple val(meta), path("*_designed.fasta"), emit: sequences
    tuple val(meta), path("*_scores.csv"), emit: scores
    tuple val(meta), path("*_structures/*.pdb"), emit: structures, optional: true
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def num_designs = task.ext.num_designs ?: 100
    def temperature = task.ext.temperature ?: 0.1
    """
    mkdir -p ${prefix}_structures

    python /opt/scfv-pmpnn/run_design.py \\
        --target ${target_pdb} \\
        --output_fasta ${prefix}_designed.fasta \\
        --output_scores ${prefix}_scores.csv \\
        --output_structures ${prefix}_structures/ \\
        --num_designs ${num_designs} \\
        --temperature ${temperature}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scfv_pmpnn: "latest"
        proteinmpnn: "1.0"
    END_VERSIONS
    """
}

// [Phase B] Structure Prediction and Confidence
process SCFV_PREDICT {
    tag "$meta.id"
    label 'process_gpu'
    label 'process_high_memory'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/scfv-pmpnn:nextflow'

    input:
    tuple val(meta), path(scfv_fasta)  // Designed antibody sequences

    output:
    tuple val(meta), path("predictions/*.pdb"), emit: structures
    tuple val(meta), path("*_confidence.csv"), emit: confidence
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    mkdir -p predictions

    python /opt/scfv-pmpnn/run_predict.py \\
        --input ${scfv_fasta} \\
        --output predictions/ \\
        --confidence ${prefix}_confidence.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scfv_pmpnn: "latest"
        alphafold2: "2.3"
    END_VERSIONS
    """
}
