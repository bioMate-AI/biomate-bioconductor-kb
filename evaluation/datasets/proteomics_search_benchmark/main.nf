#!/usr/bin/env nextflow
// ============================================================
// proteomics_search_benchmark — Phase 0 harness
// Search real mzML with Comet + MS-GF+ against an identical target+decoy+entrapment
// FASTA, normalize each engine's output to ONE PSM schema, and score speed +
// match-count + entrapment-FMR on the same runs.
//
// Design : docs/20260907_PROTEOMICS_DB_SEARCH_OPTIMIZATION_SURVEY.md §14
// Build   : docs/20260907_PROTEOMICS_SEARCH_BENCHMARK_PHASE0.md
// Spec    : evaluation/datasets/proteomics_search_benchmark/cases.yaml
//
// DAG:  PREPARE_DB ─┬─> RUN_COMET ─> NORMALIZE(comet) ─┐
//                   └─> RUN_MSGF  ─> NORMALIZE(msgf)  ─┴─> SCORE ─> metrics.json
//
// Every process has a `stub` so `nextflow run main.nf -stub-run` validates the DAG
// with NO engines, NO data, NO Batch cost. Real runs need mzML + FASTA on S3.
// Speed is read from the executor trace (-with-trace), never a tool's own log.
// ============================================================
nextflow.enable.dsl = 2

params.mzml       = null                       // glob of input mzML (real run)
params.target_fasta = null                     // human SwissProt + cRAP
params.entrapment_source = 'shuffled_target'   // shuffled_target | distant_organism
params.entrapment_ratio  = 1.0
params.entrapment_fasta  = null                // for distant_organism
params.claimed_fdr = 0.01
params.precursor_tolerance_ppm = 10
params.fragment_tolerance_da   = 0.02
params.seed       = 42
params.outdir     = './results'

// helper scripts live beside this workflow
params.bindir = "${projectDir}"

process PREPARE_DB {
    tag "db(ratio=${params.entrapment_ratio})"
    label 'process_low'
    container "quay.io/biocontainers/python:3.10"
    publishDir "${params.outdir}/db", mode: 'copy'

    input:
    path target_fasta
    path entrapment_fasta   // may be an empty stub file when source=shuffled_target

    output:
    path "combined.fasta", emit: fasta
    path "db_map.tsv",     emit: dbmap

    script:
    def ent_arg = params.entrapment_source == 'distant_organism' ? "--entrapment-fasta ${entrapment_fasta}" : ''
    """
    python3 ${params.bindir}/prepare_search_db.py \
        --target ${target_fasta} \
        --entrapment-source ${params.entrapment_source} \
        --entrapment-ratio ${params.entrapment_ratio} ${ent_arg} \
        --seed ${params.seed} \
        --out combined.fasta --map db_map.tsv
    """

    stub:
    """
    printf '>sp|P1|A\\nPEPTIDEK\\n>ENT_0_x\\nKEDITPEP\\n>DECOY_sp|P1|A\\nKEDITPEP\\n' > combined.fasta
    printf 'accession\\tlabel\\nsp|P1|A\\ttarget\\nENT_0_x\\tentrapment\\nDECOY_sp|P1|A\\tdecoy\\n' > db_map.tsv
    """
}

process RUN_COMET {
    tag "${mzml.baseName}"
    label 'process_high'
    container "quay.io/biocontainers/comet-ms:2024011--pl5321h4ac6f70_0"
    publishDir "${params.outdir}/comet", mode: 'copy'

    input:
    path mzml
    path fasta

    output:
    tuple val('comet'), path("${mzml.baseName}.comet.pep.xml"), emit: psm
    path "versions.yml", emit: versions

    script:
    """
    # comet.params generated from cases.yaml search settings; database = combined FASTA
    comet -D${fasta} \
        -P<(generate_comet_params.sh ${params.precursor_tolerance_ppm} ${params.fragment_tolerance_da}) \
        ${mzml}
    mv ${mzml.baseName}.pep.xml ${mzml.baseName}.comet.pep.xml
    echo '"RUN_COMET": {comet: 2024.01.1}' > versions.yml
    """

    stub:
    """
    touch ${mzml.baseName}.comet.pep.xml
    echo '"RUN_COMET": {comet: stub}' > versions.yml
    """
}

process RUN_MSGF {
    tag "${mzml.baseName}"
    label 'process_high'
    container "quay.io/biocontainers/msgf_plus:2024.03.26--hdfd78af_0"
    publishDir "${params.outdir}/msgf", mode: 'copy'

    input:
    path mzml
    path fasta

    output:
    tuple val('msgf'), path("${mzml.baseName}.msgf.mzid"), emit: psm
    path "versions.yml", emit: versions

    script:
    """
    msgf_plus -s ${mzml} -d ${fasta} \
        -t ${params.precursor_tolerance_ppm}ppm -tda 0 -o ${mzml.baseName}.msgf.mzid
    echo '"RUN_MSGF": {msgf_plus: 2024.03.26}' > versions.yml
    """

    stub:
    """
    touch ${mzml.baseName}.msgf.mzid
    echo '"RUN_MSGF": {msgf_plus: stub}' > versions.yml
    """
}

process NORMALIZE {
    tag "${engine}:${psm.baseName}"
    label 'process_low'
    container "quay.io/biocontainers/pyteomics:4.7.2--pyhdfd78af_0"
    publishDir "${params.outdir}/normalized", mode: 'copy'

    input:
    tuple val(engine), path(psm)
    path dbmap

    output:
    tuple val(engine), path("${psm.baseName}.psms.tsv"), emit: table

    script:
    """
    python3 ${params.bindir}/normalize_psms.py \
        --engine ${engine} --input ${psm} --dbmap ${dbmap} \
        --out ${psm.baseName}.psms.tsv
    """

    stub:
    """
    printf 'spectrum_id\\tpeptide\\tprotein\\tscore\\tlabel\\nf:1\\tPEPTIDEK\\tsp|P1|A\\t9.9\\ttarget\\n' > ${psm.baseName}.psms.tsv
    """
}

process SCORE {
    tag "score"
    label 'process_low'
    container "quay.io/biocontainers/python:3.10"
    publishDir "${params.outdir}", mode: 'copy'

    input:
    path psm_tables
    path trace_file

    output:
    path "metrics.json"
    path "calibration.tsv"
    path "pareto.tsv"

    script:
    """
    python3 ${params.bindir}/../../../scripts/score_proteomics_search_benchmark.py \
        --psms ${psm_tables} \
        --trace ${trace_file} \
        --claimed-fdr ${params.claimed_fdr} \
        --entrapment-ratio ${params.entrapment_ratio} \
        --out .
    """

    stub:
    """
    echo '[]' > metrics.json
    printf 'method\\tclaimed_fdr\\tmeasured_fmr\\ttarget_ids\\tentrapment_ids\\n' > calibration.tsv
    printf 'method\\twall_clock_s\\tpeptides_at_1pct\\tmeasured_fmr\\tcalibrated\\n' > pareto.tsv
    """
}

workflow {
    // entrapment_fasta is optional; use an empty placeholder when shuffling targets
    ch_target = Channel.fromPath(params.target_fasta ?: "${projectDir}/cases.yaml")
    ch_ent    = params.entrapment_fasta ? Channel.fromPath(params.entrapment_fasta)
                                        : Channel.fromPath("${projectDir}/no_entrapment.placeholder")  // distinct placeholder (shuffled_target ignores it)

    PREPARE_DB(ch_target, ch_ent)
    // Broadcast the DB to every engine/file: .first() -> value channel (else the
    // single-item queue channel is consumed by the first consumer, starving the rest).
    ch_fasta = PREPARE_DB.out.fasta.first()
    ch_dbmap = PREPARE_DB.out.dbmap.first()

    ch_mzml = Channel.fromPath(params.mzml ?: "${projectDir}/cases.yaml")  // queue: one item per mzML

    RUN_COMET(ch_mzml, ch_fasta)
    RUN_MSGF (ch_mzml, ch_fasta)

    ch_psm = RUN_COMET.out.psm.mix(RUN_MSGF.out.psm)
    NORMALIZE(ch_psm, ch_dbmap)

    SCORE(NORMALIZE.out.table.map { it[1] }.collect(),
          Channel.fromPath("${projectDir}/cases.yaml"))  // trace passed via -with-trace on real runs
}
