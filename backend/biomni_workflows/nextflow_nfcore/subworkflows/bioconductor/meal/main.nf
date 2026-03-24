#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MEAL
// Package to integrate methylation and expression data. It can also perform methylation or expression 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MEAL/inst/doc/MEAL.R
// Upstream  : GenomicRanges, MultiDataSet, brgedata, ggplot2, minfi
// Downstream: none
//
// Install: BiocManager::install("MEAL")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MEAL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-meal"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-meal:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-meal:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_meal_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_meal_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_meal_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(jsonlite)

    # --- subset Methy [] ---
    # Key functions: mapToGenome, rowData, dropMethylationLoci, dropLociWithSnps
    meth <- mapToGenome(ratioConvert(MsetEx))
    rowData(meth) <- getAnnotation(meth)[, -c(1:3)]
    meth <- dropMethylationLoci(meth)
    # --- Pipeline [] ---
    # Key functions: runPipeline
    res <- runPipeline(set = meth, variable_names = "status")
    # --- Pipeline Adj [] ---
    # Key functions: runPipeline
    resAdj <- runPipeline(set = meth, variable_names = "status",
    covariable_names = "age", analyses = c("DiffMean", "DiffVar"))
    names(resAdj)
    # --- get Gene Vals [] ---
    # Key functions: getGeneVals
    getGeneVals(resAdj, "ARMS2", genecol = "UCSC_RefGene_Name", fNames = c("chromosome", "start"))
    # --- Manhattan 1 [] ---
    # Key functions: GRanges
    targetRange <- GRanges("23:13000000-23000000")
    plot(resAdj, rid = "DiffMean", type = "manhattan", highlight = targetRange)
    plot(resAdj, rid = "DiffMean", type = "manhattan", subset = targetRange)
    # --- Plot Features [] ---
    # Key functions: plotFeature, ggtitle
    plotFeature(set = meth, feat = "cg09383816", variables = "status") +
    ggtitle("Diff Means")
    plotFeature(set = meth, feat = "cg11847929", variables = "status") +
    # --- Regional plot 1 [] ---
    # Key functions: GRanges, plotRegion
    targetRange <- GRanges("chrX:13000000-14000000")
    plotRegion(resAdj, targetRange)
    # --- Regional plot 2 [] ---
    # Key functions: plotRegion
    plotRegion(resAdj, targetRange, results = c("DiffMean"), tPV = 10)
    # --- run Diff Mean Analysis [] ---
    # Key functions: runDiffMeanAnalysis
    resDM <- runDiffMeanAnalysis(set = meth, model = ~ status)
    # --- run Diff Var Analysis [] ---
    # Key functions: runDiffVarAnalysis
    resDV <- runDiffVarAnalysis(set = meth, model = ~ status, coefficient = 2)
    # --- Create GenomicRanges object [] ---
    # Key functions: GRanges, runRDA
    targetRange <- GRanges("chrX:13000000-23000000")
    resRDA <- runRDA(set = meth, model = ~ status, range = targetRange)
    # --- RDA res [] ---
    # Key functions: getAssociation
    getAssociation(resRDA, rid = "RDA")
    # --- get R D Aresults [] ---
    # Key functions: getRDAresults
    getRDAresults(resRDA)
    # --- plot R D A [] ---
    # Key functions: plotRDA
    plotRDA(object = resRDA, pheno = colData(meth)[, "status", drop = FALSE])
    # --- plotRDA 2 [] ---
    # Key functions: plotRDA
    plotRDA(object = resRDA, pheno = colData(meth)[, "status", drop = FALSE])
    abline(h = -1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_meal_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_meal_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_meal_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MEAL:", paste0("    meal: ", packageVersion("MEAL"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_meal_results.csv
    touch ${prefix}_meal_output.rds
    echo "BIOC_MEAL:" > versions.yml
    echo "    meal: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MEAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MEAL(ch_input)

    emit:
    results  = BIOC_MEAL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MEAL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MEAL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MEAL.out.versions  // channel: path(versions.yml)
}
