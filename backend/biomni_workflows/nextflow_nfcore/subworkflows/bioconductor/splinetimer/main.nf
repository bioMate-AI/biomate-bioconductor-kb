#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: splineTimeR
// This package provides functions for differential gene expression analysis of gene expression time-co
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/splineTimeR/inst/doc/splineTimeR.R
// Upstream  : FIs
// Downstream: none
//
// Install: BiocManager::install("splineTimeR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPLINETIMER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-splinetimer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-splinetimer:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-splinetimer:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_splinetimer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_splinetimer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_splinetimer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(End)
    library(jsonlite)

    # --- Libpaths [] ---
    # Key functions: libPaths
    ## #path1 <- "/Users/hbraselmann/R/Bioc3.4dev/library"
    ## #path2 <- "/Library/Frameworks/R.framework/Versions/3.3/Resources/library"
    ## #.libPaths(c(path1, path2))
    ## #.libPaths()
    # --- Data [] ---
    # Key functions: pData
    library(splineTimeR)
    data(TCsimData)
    head(pData(TCsimData),8)
    # --- Splinediffexprs [] ---
    # Key functions: splineDiffExprs
    diffExprs <- splineDiffExprs(eSetObject = TCsimData, df = 3,
                                 cutoff.adj.pVal = 0.01, reference = "T1",
                                 intercept = TRUE)
    head(diffExprs, 3)
    # --- Splineplot [] ---
    # Key functions: splinePlot
    splinePlot(eSetObject = TCsimData, df = 3,
               reference = "T1", toPlot = c("EEF2","OR5W2"))
    # --- Getgmt [] ---
    # Key functions: getGmt, splineDiffExprs, pathEnrich, End
    ## ## Not run
    ## ## Download .gmt file 'c2.all.v5.0.symbols.gmt' (all curated gene sets,
    ## ## gene symbols) from the Broad,
    ## ## http://www.broad.mit.edu/gsea/downloads.jsp#msigdb, then
    ## geneSets <- getGmt("/path/to/c2.all.v5.0.symbols.gmt")
    # --- Single Igr [] ---
    # Key functions: splineNetRecon
    igr <- splineNetRecon(eSetObject = TCsimData, treatmentType = "T2",
                          probesForNR = rownames(diffExprs),
                          cutoff.ggm = 0.7, method = "dynamic")
    # --- Two Igraphs [] ---
    # Key functions: splineNetRecon
    igr <- splineNetRecon(eSetObject = TCsimData, treatmentType = "T2",
                          probesForNR = rownames(diffExprs),
                          cutoff.ggm = c(0.8,0.9), method = "dynamic")
    # --- Data [] ---
    # Key functions: data
    ## library(FIs)
    ## data(FIs)
    ## names(FIs)
    ## head(FIs$FIs_Reactome)
    ## head(FIs$FIs_BioGRID)
    # --- Splinenetrecon [] ---
    # Key functions: splineNetRecon, networkProperties
    igr <- splineNetRecon(eSetObject = TCsimData, treatmentType = "T2",
                          probesForNR = rownames(diffExprs),
                          cutoff.ggm = c(0.7,0.8,0.9), method = "dynamic")
    scaleFreeProp <- networkProperties(igr)
    head(scaleFreeProp)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_splinetimer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_splinetimer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_splinetimer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPLINETIMER:", paste0("    splinetimer: ", packageVersion("splineTimeR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_splinetimer_results.csv
    touch ${prefix}_splinetimer_output.rds
    echo "BIOC_SPLINETIMER:" > versions.yml
    echo "    splinetimer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPLINETIMER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPLINETIMER(ch_input)

    emit:
    results  = BIOC_SPLINETIMER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPLINETIMER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPLINETIMER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPLINETIMER.out.versions  // channel: path(versions.yml)
}
