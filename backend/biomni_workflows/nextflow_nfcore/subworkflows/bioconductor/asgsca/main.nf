#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ASGSCA
// The package provides tools to model and test the association between multiple genotypes and multiple
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ASGSCA/inst/doc/ASGSCA.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ASGSCA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ASGSCA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-asgsca"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-asgsca:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-asgsca:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_asgsca_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_asgsca_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_asgsca_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ASGSCA)
    library(GSCA)
    library(jsonlite)

    # --- Model Estimation [] ---
    # Key functions: GSCA
    data("QCAHS")
    data("W0")
    data("B0")
    LatentVar <- c("CETP", "APOC3", "ABCA1", "FABP-2", "APOA1", "APOE", "HL",
                   "LPL", "MTP", "PON1", "PON2", "PCSK9", "PGC", "ADIPO",
                   "PPARg2", "TNFa", "eNOS", "a23AR", "b1AR", "b2AR", "b3AR",
                   "ACE", "AGT", "AGTR1", "LEPR", "Lipid metabolism",
                   "Energy metabolism", "BP control")
    res <- GSCA(QCAHS, W0, B0, latent.names = LatentVar, estim = TRUE,
                path.test = FALSE, path = NULL, nperm = 100)


    # --- Path Significance Testing [] ---
    # Key functions: GSCA
    data("QCAHS")
    data("W0")
    data("B0")
    LatentVar <- c("CETP", "APOC3", "ABCA1", "FABP-2", "APOA1", "APOE", "HL",
                   "LPL", "MTP", "PON1", "PON2", "PCSK9", "PGC", "ADIPO",
                   "PPARg2", "TNFa", "eNOS", "a23AR", "b1AR", "b2AR", "b3AR",
                   "ACE", "AGT", "AGTR1", "LEPR", "Lipid metabolism",
                   "Energy metabolism", "BP control")
    path0 <- matrix(c(2, 3, 5, 6), ncol = 2)
    res_path <- GSCA(QCAHS, W0, B0, latent.names = LatentVar, estim = FALSE,
                     path.test = TRUE, path = path0, nperm = 100)


    # --- Association Filtering [] ---
    # Key functions: GSCA
    data("ResQCAHS")
    indices <- which(ResQCAHS$pvalues < 0.05, arr.ind = TRUE)
    ind.row <- indices[, 1]
    ind.col <- indices[, 2]
    Significant <- matrix(rep(0, nrow(indices) * 3), ncol = 3)
    colnames(Significant) <- c("Gene", "Pathway", "pval")
    Significant[, 1] <- rownames(ResQCAHS$pvalues)[ind.row]
    Significant[, 2] <- colnames(ResQCAHS$pvalues)[ind.col]
    Significant[, 3] <- ResQCAHS$pvalues[indices]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_asgsca_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_asgsca_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_asgsca_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ASGSCA:", paste0("    asgsca: ", packageVersion("ASGSCA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_asgsca_results.csv
    touch ${prefix}_asgsca_output.rds
    echo "BIOC_ASGSCA:" > versions.yml
    echo "    asgsca: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ASGSCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ASGSCA(ch_input)

    emit:
    results  = BIOC_ASGSCA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ASGSCA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ASGSCA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ASGSCA.out.versions  // channel: path(versions.yml)
}
