#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MotifDb
// More than 9900 annotated position frequency matrices from 14 public sources, for multiple organisms.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MotifDb/inst/doc/MotifDb.R
// Upstream  : seqLogo
// Downstream: motifbreakR, generegulation
//
// Install: BiocManager::install("MotifDb")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOTIFDB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-motifdb"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-motifdb:1.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-motifdb:1.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_motifdb_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_motifdb_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_motifdb_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MotifDb)
    library(jsonlite)

    # --- Motif Querying [MotifDb] ---
    # Key functions: query
    ctcf_motifs <- query(
        MotifDb,
        andStrings = c("CTCF", "hsapiens"),
        orStrings = c("jaspar2018", "hocomocov11-core-A"),
        notStrings = "ctcfl"
    )
    motif_names <- names(ctcf_motifs)

    # --- Metadata Extraction [MotifDb] ---
    # Key functions: values
    motif_metadata <- values(ctcf_motifs)
    selected_metadata <- motif_metadata[, c(
        "organism",
        "dataSource",
        "geneSymbol"
    )]

    # --- Consensus Sequence Generation [MotifDb] ---
    # Key functions: consensusString
    consensus_seqs <- sapply(
        ctcf_motifs,
        consensusString
    )
    consensus_summary <- data.frame(
        Motif = names(ctcf_motifs),
        Consensus = consensus_seqs,
        stringsAsFactors = FALSE
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_motifdb_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_motifdb_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_motifdb_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOTIFDB:", paste0("    motifdb: ", packageVersion("MotifDb"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_motifdb_results.csv
    touch ${prefix}_motifdb_output.rds
    echo "BIOC_MOTIFDB:" > versions.yml
    echo "    motifdb: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOTIFDB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOTIFDB(ch_input)

    emit:
    results  = BIOC_MOTIFDB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOTIFDB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOTIFDB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOTIFDB.out.versions  // channel: path(versions.yml)
}
