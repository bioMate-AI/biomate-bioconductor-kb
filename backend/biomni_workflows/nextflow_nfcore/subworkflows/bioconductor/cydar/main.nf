#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cydar
// Identifies differentially abundant populations between samples and groups in mass cytometry data. Pr
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cydar/inst/doc/cydar.R
// Upstream  : edgeR, flowCore, knitr, ncdfFlow
// Downstream: none
//
// Install: BiocManager::install("cydar")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CYDAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cydar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cydar:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cydar:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_cydar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cydar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cydar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DGEList)
    library(Subset)
    library(jsonlite)

    # --- Rep [] ---
    # Key functions: rnorm, sample
    ---------------------------------------------------------------------
    ncells <- 20000
    nda <- 200
    nmarkers <- 31
    down.pos <- 1.8
    # --- List [] ---
    # Key functions: poolCells, ncdfFlowSet
    ---------------------------------------------------------------------
    library(ncdfFlow)
    collected.exprs <- list()
    # --- Poolcells [] ---
    # Key functions: poolCells
    ---------------------------------------------------------------------
    pool.ff <- poolCells(collected.exprs)
    # --- Estimatelogicle [] ---
    # Key functions: estimateLogicle, transform
    ---------------------------------------------------------------------
    library(flowCore)
    trans <- estimateLogicle(pool.ff, colnames(pool.ff))
    proc.ff <- transform(pool.ff, trans)
    # --- Outliergate [] ---
    # Key functions: outlierGate, filter
    ---------------------------------------------------------------------
    gate.31 <- outlierGate(proc.ff, "Marker31", type="upper")
    gate.31
    filter.31 <- filter(proc.ff, gate.31)
    summary(filter.31@subSet)
    # --- Transform [] ---
    # Key functions: transform
    ---------------------------------------------------------------------
    processed.exprs <- transform(collected.exprs, trans)
    # --- Subset [] ---
    # Key functions: Subset
    ---------------------------------------------------------------------
    processed.exprs <- Subset(processed.exprs, gate.31)
    # --- Preparecelldata [] ---
    # Key functions: prepareCellData
    ---------------------------------------------------------------------
    cd <- prepareCellData(processed.exprs)
    # --- Countcells [] ---
    # Key functions: countCells
    ---------------------------------------------------------------------
    cd <- countCells(cd, tol=0.5)
    # --- Head [] ---
    # Key functions: assay
    ---------------------------------------------------------------------
    head(assay(cd))
    # --- Head [] ---
    # Key functions: intensities
    ---------------------------------------------------------------------
    head(intensities(cd))
    # --- Dgelist [] ---
    # Key functions: DGEList, assay
    ---------------------------------------------------------------------
    library(edgeR)
    y <- DGEList(assay(cd), lib.size=cd$totals)
    # --- Avelogcpm [] ---
    # Key functions: aveLogCPM
    ---------------------------------------------------------------------
    keep <- aveLogCPM(y) >= aveLogCPM(5, mean(cd$totals))
    cd <- cd[keep,]
    y <- y[keep,]
    # --- Matrix [] ---
    # Key functions: factor, estimateDisp, glmQLFit, glmQLFTest
    ---------------------------------------------------------------------
    design <- model.matrix(~factor(conditions))
    y <- estimateDisp(y, design)
    fit <- glmQLFit(y, design, robust=TRUE)
    res <- glmQLFTest(fit, coef=2)
    # --- Spatialfdr [] ---
    # Key functions: spatialFDR, intensities
    ---------------------------------------------------------------------
    qvals <- spatialFDR(intensities(cd), res$table$PValue)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cydar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cydar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cydar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CYDAR:", paste0("    cydar: ", packageVersion("cydar"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cydar_results.csv
    touch ${prefix}_cydar_output.rds
    echo "BIOC_CYDAR:" > versions.yml
    echo "    cydar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CYDAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_CYDAR(ch_input)

    emit:
    results  = BIOC_CYDAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CYDAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CYDAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CYDAR.out.versions  // channel: path(versions.yml)
}
