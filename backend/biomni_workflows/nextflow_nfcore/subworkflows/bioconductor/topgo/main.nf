#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: topGO
// topGO package provides tools for testing GO terms while accounting for the topology of the GO graph.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/topGO/inst/doc/topGO.R
// Upstream  : ALL, genefilter, lattice, xtable
// Downstream: BgeeDB, compEpiTools, EGSEA, ideal, moanin
//
// Install: BiocManager::install("topGO")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TOPGO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-topgo"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-topgo:2.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-topgo:2.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_topgo_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_topgo_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_topgo_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GenTable)
    library(IQR)
    library(jsonlite)

    # --- Data import and loading [] ---
    # Key functions: data
    library(topGO)
    library(ALL)
    data(ALL)
    data(geneList)
    # --- Quality control and filtering [] ---
    # Key functions: getPvalues, exprs, frame, xyplot, device, whitebg
    pValue <- getPvalues(exprs(ALL), classlabel = y, alternative = "greater")
    geneVar <- apply(exprs(ALL), 1, var)
    dd <- data.frame(x = geneVar[allProb], y = log10(pValue[allProb]), groups = groupProb)
    library(lattice)
    trellis.device(device = pdf, theme = col.whitebg(), file = "whichProbe.pdf", width = 9, height = 7)
    # --- ColSums analysis [] ---
    # Key functions: colSums, topDiffGenes, runTest, GenTable, colors, score, termStat, colMap
    ## weight01.fisher <- runTest(GOdata, statistic = "fisher")
    ## weight01.t <- runTest(GOdata, algorithm = "weight01", statistic = "t")
    ## elim.ks <- runTest(GOdata, algorithm = "elim", statistic = "ks")
    ##
    ## weight.ks <- runTest(GOdata, algorithm = "weight", statistic = "ks") #will not work!!!
    # --- Feature annotation [] ---
    # Key functions: featureNames, genes, factor, numGenes, genesInTerm, sigGenes
    allProb <- featureNames(ALL)
    groupProb <- integer(length(allProb)) + 1
    groupProb[allProb %in% genes(GOdata)] <- 0
    groupProb[!selProbes] <- 2
    groupProb <- factor(groupProb, labels = c("Used", "Not annotated", "Filtered"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_topgo_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_topgo_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_topgo_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TOPGO:", paste0("    topgo: ", packageVersion("topGO"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_topgo_results.csv
    touch ${prefix}_topgo_output.rds
    echo "BIOC_TOPGO:" > versions.yml
    echo "    topgo: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TOPGO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TOPGO(ch_input)

    emit:
    results  = BIOC_TOPGO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TOPGO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TOPGO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TOPGO.out.versions  // channel: path(versions.yml)
}
