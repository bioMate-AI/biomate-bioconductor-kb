#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: qusage
// This package is an implementation the Quantitative Set Analysis for Gene Expression (QuSAGE) method 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/qusage/inst/doc/qusage.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("qusage")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QUSAGE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-qusage"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-qusage:2.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-qusage:2.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_qusage_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_qusage_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_qusage_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(qusage)
    library(jsonlite)

    # --- Gene Set Enrichment Analysis ---
    # Key functions: qusage, pdf.pVal, qsTable
    labels <- c(rep("t0", 17), rep("t1", 17))
    contrast <- "t1-t0"
    qs.results <- qusage(eset, labels, contrast, ISG.geneSet)
    p.vals <- pdf.pVal(qs.results)
    q.vals <- p.adjust(p.vals, method = "fdr")
    res.table <- qsTable(qs.results, number = 10)

    # --- Linear Mixed Modeling ---
    # Key functions: qgen, qsTable
    fixedeffects <- ~Hours + Condition + Condition * Hours + Age + Gender
    qusage.result.random <- qgen(
        eset.full,
        flu.meta,
        fixed = fixedeffects,
        contrast.factor = "Condition",
        contrast = "sx77 - sx0",
        geneSets = ISG.geneSet,
        random = ~1 | Subject,
        design.sampleid = "SampleID"
    )
    res.table.random <- qsTable(qusage.result.random)

    # --- Meta-Analysis and PDF Combination ---
    # Key functions: qusage, combinePDFs, pdf.pVal
    qs.results.list <- lapply(c("GSE59635", "GSE59654"), function(n) {
        eset <- fluVaccine$esets[[n]]
        phenoData <- fluVaccine$phenoData[[n]]
        labels <- paste(phenoData$responder, phenoData$bloodDrawDay, sep = ".")
        qusage(eset, labels, "(high.d7-high.d0)-(low.d7-low.d0)",
               BTM.geneSets, pairVector = phenoData$subjectId, n.points = 2^14)
    })
    combined <- combinePDFs(qs.results.list)
    combined.pvals <- pdf.pVal(combined)

    # --- Visualisation of Pathway Activation ---
    # Key functions: plotDensityCurves, plotGeneSetDistributions, calcBayesCI, plotCIsGenes
    plotDensityCurves(qs.results, path.index = 1:5, col = 1:5, lwd = 2)
    plotGeneSetDistributions(qs.results)
    ci.vals <- calcBayesCI(qs.results, low = 0.001)
    plotCIsGenes(qs.results, path.index = 1)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_qusage_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_qusage_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_qusage_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QUSAGE:", paste0("    qusage: ", packageVersion("qusage"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qusage_results.csv
    touch ${prefix}_qusage_output.rds
    echo "BIOC_QUSAGE:" > versions.yml
    echo "    qusage: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QUSAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_QUSAGE(ch_input)

    emit:
    results  = BIOC_QUSAGE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QUSAGE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QUSAGE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QUSAGE.out.versions  // channel: path(versions.yml)
}
