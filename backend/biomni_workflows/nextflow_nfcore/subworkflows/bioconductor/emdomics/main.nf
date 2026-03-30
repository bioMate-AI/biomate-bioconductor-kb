#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: EMDomics
// The EMDomics algorithm is used to perform a supervised multi-class analysis to measure the magnitude
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/EMDomics/inst/doc/EMDomics.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("EMDomics")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EMDOMICS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-emdomics"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-emdomics:2.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-emdomics:2.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_emdomics_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_emdomics_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_emdomics_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(EMDomics)
    library(jsonlite)

    # --- Rnorm [] ---
    # Key functions: rnorm
    ---------------------------------------------------------------------
    exp_data <- rnorm(100)
    names(exp_data) <- paste("sample", 1:100)
    groupA.labels <- rep("A",50)
    groupB.labels <- rep("B",20)
    # --- Frame [] ---
    # Key functions: frame, ggplot, aes, geom_density
    ---------------------------------------------------------------------
    library(ggplot2)
    df <- as.data.frame(exp_data)
    df$group[1:50] <- "A"
    df$group[51:70] <- "B"
    # --- Calculate Emd Gene [] ---
    # Key functions: calculate_emd_gene
    ---------------------------------------------------------------------
    library(EMDomics)
    calculate_emd_gene(exp_data, labels, names(exp_data))
    # --- Sample [] ---
    # Key functions: sample
    ---------------------------------------------------------------------
    exp_data2 <- exp_data
    mod_vec <- sample(c(2,-2), 50, replace=TRUE)
    exp_data2[1:50] <- exp_data2[1:50] + mod_vec
    # --- Frame [] ---
    # Key functions: frame, ggplot, aes, geom_density, calculate_emd_gene
    ---------------------------------------------------------------------
    df <- as.data.frame(exp_data2)
    df$group[1:50] <- "A"
    df$group[51:70] <- "B"
    df$group[71:100] <- "C"
    # --- Matrix [] ---
    # Key functions: rnorm
    ---------------------------------------------------------------------
    data <- matrix(rnorm(10000), nrow=100, ncol=100)
    rownames(data) <- paste("gene", 1:100, sep="")
    colnames(data) <- paste("sample", 1:100, sep="")
    groupA.labels <- rep("A",50)
    # --- Order [] ---
    # Key functions: plot_emd_density
    ---------------------------------------------------------------------
    emd3 <- emd[(order(emd[,"emd"])),]
    smallest_gene <- rownames(emd3)[1]
    biggest_gene <- rownames(emd3)[nrow(emd3)]
    plot_emd_density(results, smallest_gene)
    # --- Plot Emdnull [] ---
    # Key functions: plot_emdnull
    ---------------------------------------------------------------------
    plot_emdnull(results)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_emdomics_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_emdomics_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_emdomics_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EMDOMICS:", paste0("    emdomics: ", packageVersion("EMDomics"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_emdomics_results.csv
    touch ${prefix}_emdomics_output.rds
    echo "BIOC_EMDOMICS:" > versions.yml
    echo "    emdomics: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EMDOMICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EMDOMICS(ch_input)

    emit:
    results  = BIOC_EMDOMICS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EMDOMICS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EMDOMICS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EMDOMICS.out.versions  // channel: path(versions.yml)
}
