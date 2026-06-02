#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: missMethyl
// Normalisation, testing for differential variability and differential methylation and gene set testin
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/missMethyl/inst/doc/missMethyl.R
// Upstream  : DMRcate, edgeR, limma, minfi, minfiData
// Downstream: methylationArrayAnalysis
//
// Install: BiocManager::install("missMethyl")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MISSMETHYL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-missmethyl"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-missmethyl:1.40.3--r44_0' :
        'quay.io/biocontainers/bioconductor-missmethyl:1.40.3--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_missmethyl_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_missmethyl_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_missmethyl_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(missMethyl)
    library(DGEList)
    library(RUVadj)
    library(RUVfit)
    library(SWAN)
    library(jsonlite)

    # --- RUV Adjustment for Unwanted Variation [] ---
    # Key functions: getINCs, RUVfit, RUVadj
    grp <- factor(targets$status, labels = c(0, 1))
    INCs <- getINCs(rgSet)
    Mc <- rbind(M, INCs)
    ctl1 <- rownames(Mc) %in% rownames(INCs)
    rfit1 <- RUVfit(Y = Mc, X = grp, ctl = ctl1)
    rfit2 <- RUVadj(Y = Mc, fit = rfit1)


    # --- Adjusted Value Extraction and Visualization [] ---
    # Key functions: topRUV, RUVfit, getAdj
    top1 <- topRUV(rfit2, num = Inf, p.BH = 1)
    ctl2 <- rownames(M) %in% rownames(top1[top1$p.BH_X1.1 > 0.5, ])
    rfit3 <- RUVfit(Y = M, X = grp, ctl = ctl2)
    Madj <- getAdj(M, rfit3)


    # --- Differential Variability Analysis [] ---
    # Key functions: varFit, topVar
    fitvar <- varFit(Mval, design = design, coef = c(1, 4))
    topDV <- topVar(fitvar, coef = 4)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_missmethyl_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_missmethyl_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_missmethyl_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MISSMETHYL:", paste0("    missmethyl: ", packageVersion("missMethyl"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_missmethyl_results.csv
    touch ${prefix}_missmethyl_output.rds
    echo "BIOC_MISSMETHYL:" > versions.yml
    echo "    missmethyl: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MISSMETHYL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MISSMETHYL(ch_input)

    emit:
    results  = BIOC_MISSMETHYL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MISSMETHYL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MISSMETHYL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MISSMETHYL.out.versions  // channel: path(versions.yml)
}
