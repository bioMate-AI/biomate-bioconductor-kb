#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CRISPRseek
// The package includes functions to find potential guide RNAs for the CRISPR editing system including 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CRISPRseek/inst/doc/CRISPRseek.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CRISPRseek")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CRISPRSEEK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-crisprseek"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-crisprseek:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-crisprseek:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_crisprseek_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_crisprseek_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_crisprseek_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CRISPRseek)
    library(jsonlite)

    # --- Target Sequence Comparison [] ---
    # Key functions: compare2Sequences
    seqFile1 <- system.file("extdata", "seq1.fa", package = "CRISPRseek")
    seqFile2 <- system.file("extdata", "seq2.fa", package = "CRISPRseek")
    comparison <- CRISPRseek::compare2Sequences(
        seqFile1,
        seqFile2,
        outputDir = tempdir(),
        overwrite = TRUE
    )


    # --- gRNA Filtering [] ---
    # Key functions: filtergRNAs
    all_gRNAs <- Biostrings::DNAStringSet(
        c("ATCGATCGATCGATCGATCG", "GCTAGCTAGCTAGCTAGCTA")
    )
    filtered <- CRISPRseek::filtergRNAs(
        all_gRNAs,
        pairgRNA = FALSE,
        constraint = "GG"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_crisprseek_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_crisprseek_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_crisprseek_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CRISPRSEEK:", paste0("    crisprseek: ", packageVersion("CRISPRseek"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_crisprseek_results.csv
    touch ${prefix}_crisprseek_output.rds
    echo "BIOC_CRISPRSEEK:" > versions.yml
    echo "    crisprseek: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CRISPRSEEK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CRISPRSEEK(ch_input)

    emit:
    results  = BIOC_CRISPRSEEK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CRISPRSEEK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CRISPRSEEK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CRISPRSEEK.out.versions  // channel: path(versions.yml)
}
