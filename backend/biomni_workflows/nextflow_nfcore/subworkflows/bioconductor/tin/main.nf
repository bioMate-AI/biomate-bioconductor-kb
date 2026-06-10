#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TIN
// The TIN package implements a set of tools for transcriptome instability analysis based on exon expre
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TIN/inst/doc/TIN.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("TIN")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_TIN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tin"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tin_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tin_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tin_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TIN)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    data(splicingFactors)
    data(geneSets)
    data(geneAnnotation)
    # --- Firmaanalysis [] ---
    # Key functions: firmaAnalysis
    fs <- firmaAnalysis(useToyData=TRUE)
    # --- Readgenesummaries [] ---
    # Key functions: readGeneSummaries
    gs <- readGeneSummaries(useToyData=TRUE)
    # --- Aberrantexonusage [] ---
    # Key functions: aberrantExonUsage
    tra <- aberrantExonUsage(1.0, sampleSetFirmaScores)
    # --- Probesetpermutations [] ---
    # Key functions: probesetPermutations
    aberrantExonsPerms <- probesetPermutations(sampleSetFirmaScores, quantiles)
    # --- Correlation [] ---
    # Key functions: correlation
    corr <- correlation(splicingFactors, sampleSetGeneSummaries, tra)
    # --- Genesetcorrelation [] ---
    # Key functions: geneSetCorrelation
    gsc <- geneSetCorrelation(geneSets, geneAnnotation, sampleSetGeneSummaries,
        tra, 100)
    # --- Clusterplot [] ---
    # Key functions: clusterPlot
    clusterPlot(sampleSetGeneSummaries, tra, "euclidean", "complete",
        "TIN-cluster.pdf")
    # --- Scatterplot [] ---
    # Key functions: scatterPlot
    scatterPlot("TIN-scatter.pdf", TRUE, aberrantExons, aberrantExonsPerms)
    # --- Correlationplot [] ---
    # Key functions: correlationPlot
    correlationPlot("TIN-correlation.pdf", tra, sampleSetGeneSummaries,
        splicingFactors, 1000, 1000)
    # --- Posnegcorrplot [] ---
    # Key functions: posNegCorrPlot
    posNegCorrPlot("TIN-posNegCorrPlot.pdf", tra, sampleSetGeneSummaries,
        splicingFactors, 1000, 1000)

    # --- Save outputs ---
    .objs <- setdiff(ls(), c("args", "prefix", ".objs"))
    .cells <- function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                            if (is.data.frame(x) || is.matrix(x)) prod(dim(x)) else -1 }
    .dfs  <- Filter(function(v) is.data.frame(tryCatch(get(v), error = function(e) NULL)), .objs)
    .tabs <- Filter(function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                                  is.data.frame(x) || is.matrix(x) }, .objs)
    .cand <- if (length(.dfs) > 0) .dfs else .tabs
    if (length(.cand) > 0) {
        .main <- get(.cand[[ which.max(sapply(.cand, .cells)) ]])
        write.csv(as.data.frame(.main), "${prefix}_tin_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_tin_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_tin_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_TIN:", paste0("    tin: ", as.character(packageVersion("TIN")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tin_results.csv
    touch ${prefix}_tin_output.rds
    echo "BIOC_TIN:" > versions.yml
    echo "    tin: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TIN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TIN(ch_input)

    emit:
    results  = BIOC_TIN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TIN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TIN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TIN.out.versions  // channel: path(versions.yml)
}
