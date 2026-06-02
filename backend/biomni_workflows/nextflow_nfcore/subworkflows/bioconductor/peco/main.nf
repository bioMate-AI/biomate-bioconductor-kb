#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: peco
// Our approach provides a way to assign continuous cell cycle phase using scRNA-seq data, and conseque
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/peco/inst/doc/vignette.html
// Upstream  : SingleCellExperiment, devtools, doParallel, foreach
// Downstream: none
//
// Install: BiocManager::install("peco")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PECO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-peco"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-peco:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-peco:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_peco_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_peco_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_peco_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(peco)
    library(jsonlite)

    # --- Code Block 1 [] ---
    # Key functions: packages, install_github
    install.packages("devtools")
    library(devtools)
    install_github("jhsiao999/peco")
    # --- Code Block 3 [] ---
    # Key functions: data_transform_quantile, assays
    sce_top101genes <- data_transform_quantile(sce_top101genes)
    #> computing on 2 cores
    assays(sce_top101genes)
    #> List of length 3
    #> names(3): counts cpm cpm_quantNormed
    # --- Code Block 4 [] ---
    # Key functions: cycle_npreg_outsample
    pred_top101genes <- cycle_npreg_outsample(
        Y_test=sce_top101genes,
        sigma_est=training_human$sigma[rownames(sce_top101genes),],
        funs_est=training_human$cellcycle_function[rownames(sce_top101genes)],
        method.trend="trendfilter",
    # --- Code Block 5 [] ---
    # Key functions: colData
    head(colData(pred_top101genes$Y)$cellcycle_peco)
    #> 20170905-A01 20170905-A02 20170905-A03 20170905-A06 20170905-A07 20170905-A08
    #>     1.099557     4.680973     2.544690     4.303982     4.052655     1.350885
    # --- Code Block 6 [] ---
    # Key functions: colData, assay, fit_cyclical_many, rowData
    # predicted cell time in the input data
    theta_predict = colData(pred_top101genes$Y)$cellcycle_peco
    names(theta_predict) = rownames(colData(pred_top101genes$Y))
    # expression values of 10 genes in the input data
    yy_input = assay(pred_top101genes$Y,"cpm_quantNormed")[1:6,]
    # --- Code Block 7 [] ---
    # Key functions: 1, namespace
    sessionInfo()
    #> R version 4.4.1 (2024-06-14)
    #> Platform: x86_64-pc-linux-gnu
    #> Running under: Ubuntu 24.04.1 LTS
    #>

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_peco_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_peco_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_peco_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PECO:", paste0("    peco: ", packageVersion("peco"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peco_results.csv
    touch ${prefix}_peco_output.rds
    echo "BIOC_PECO:" > versions.yml
    echo "    peco: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PECO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PECO(ch_input)

    emit:
    results  = BIOC_PECO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PECO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PECO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PECO.out.versions  // channel: path(versions.yml)
}
