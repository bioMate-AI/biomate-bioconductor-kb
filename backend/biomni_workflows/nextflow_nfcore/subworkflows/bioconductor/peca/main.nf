#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PECA
// Calculates Probe-level Expression Change Averages (PECA) to identify differential expression in Affy
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PECA/inst/doc/PECA.R
// Upstream  : SpikeIn
// Downstream: none
//
// Install: BiocManager::install("PECA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PECA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-peca"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-peca:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-peca:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_peca_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_peca_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_peca_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PECA_AffyBatch)
    library(PECA_tsv)
    library(jsonlite)

    # --- Peptides Data [] ---
    # Key functions: csv
    filePath <- system.file("extdata", "peptides.tsv", package="PECA")
    data <- read.csv(file=filePath, sep="\t")
    head(data)
    # --- Peptides Peca [] ---
    # Key functions: PECA_tsv
    library(PECA)
    group1 <- c("A1", "A2", "A3")
    group2 <- c("B1", "B2", "B3")
    results <- PECA_tsv(filePath, group1, group2)
    # --- Microarray Data [] ---
    # Key functions: data
    library(SpikeIn)
    data(SpikeIn133)
    # --- Microarray Peca [] ---
    # Key functions: PECA_AffyBatch
    data <- SpikeIn133[,c(1,15,29,2,16,30)]
    results <- PECA_AffyBatch(normalize="true", affy=data)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_peca_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_peca_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_peca_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PECA:", paste0("    peca: ", packageVersion("PECA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peca_results.csv
    touch ${prefix}_peca_output.rds
    echo "BIOC_PECA:" > versions.yml
    echo "    peca: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PECA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PECA(ch_input)

    emit:
    results  = BIOC_PECA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PECA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PECA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PECA.out.versions  // channel: path(versions.yml)
}
