#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PAA
// PAA imports single color (protein) microarray data that has been saved in gpr file format - esp. Pro
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PAA/inst/doc/PAA_vignette.R
// Upstream  : BiocManager, limma
// Downstream: none
//
// Install: BiocManager::install("PAA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PAA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-paa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-paa:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-paa:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_paa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_paa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_paa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PAA)
    library(jsonlite)

    # --- Targets [] ---
    # Key functions: files
    targets <- read.table(file=list.files(system.file("extdata", package="PAA"),
     pattern = "^targets", full.names = TRUE), header=TRUE)
    print(targets[1:3,])
    # --- Loadgpr [] ---
    # Key functions: files, loadGPR
    gpr <- system.file("extdata", package="PAA")
    targets <- list.files(system.file("extdata", package="PAA"),
       pattern = "dummy_targets", full.names=TRUE)
    dummy.elist <- loadGPR(gpr.path=gpr, targets.path=targets,
       array.type="ProtoArray")
    # --- Plotarray1 [] ---
    # Key functions: plotArray
    plotArray(elist=elist, idx=3, data.type="bg", log=FALSE, normalized=FALSE,
      aggregation="min", colpal="topo.colors")
    # --- Plotarray2 [] ---
    # Key functions: plotArray
    plotArray(elist=elist, idx=3, data.type="fg", log=FALSE, normalized=FALSE,
      aggregation="min", colpal="topo.colors")
    # --- Batchfilter [] ---
    # Key functions: batchFilter
    lot1 <- elist$targets[elist$targets$Batch=='Batch1','ArrayID']
    lot2 <- elist$targets[elist$targets$Batch=='Batch2','ArrayID']
    elist.bF <- batchFilter(elist=elist, lot1=lot1, lot2=lot2, log=FALSE,
     p.thresh=0.001, fold.thresh=3)
    # --- Batchfilteranova [] ---
    # Key functions: anova
    elist.bF.a <- batchFilter.anova(elist=elist, log=FALSE, p.thresh=0.001,
     fold.thresh=3)
    elist <- elist.bF
    # --- Plotnormmethods [] ---
    # Key functions: plotNormMethods
    ## plotNormMethods(elist=elist)
    # --- Plotmaplots [] ---
    # Key functions: plotMAPlots
    plotMAPlots(elist=elist, idx=10)
    # --- Normalizearrays [] ---
    # Key functions: normalizeArrays
    elist <- normalizeArrays(elist=elist, method="cyclicloess",
    cyclicloess.method="fast")
    # --- Batchadjust [] ---
    # Key functions: batchAdjust
    elist <- batchAdjust(elist=elist, log=TRUE)
    # --- Plotarray3 [] ---
    # Key functions: plotArray
    plotArray(elist=elist, idx=3, data.type="fg", log=TRUE, normalized=TRUE,
      aggregation="min", colpal="topo.colors")
    # --- Volcanoplot1 [] ---
    # Key functions: volcanoPlot
    c1 <- paste(rep("AD",20), 1:20, sep="")
    c2 <- paste(rep("NDC",20), 1:20, sep="")
    # --- Volcanoplot2 [] ---
    # Key functions: mMsMatrix, volcanoPlot
    ## mMs.matrix1 <- mMs.matrix2 <- mMsMatrix(x=20, y=20)
    ## volcanoPlot(elist=elist.unlog, group1=c1, group2=c2, log=FALSE, method="mMs",
    ## p.thresh=0.01, fold.thresh=2, mMs.matrix1=mMs.matrix1,
    ## mMs.matrix2=mMs.matrix2, above=1500, between=400)
    # --- Pvalueplot1 [] ---
    # Key functions: pvaluePlot
    pvaluePlot(elist=elist, group1=c1, group2=c2, log=TRUE, method="tTest")
    # --- Pvalueplot2 [] ---
    # Key functions: mMsMatrix, pvaluePlot
    ## mMs.matrix1 <- mMs.matrix2 <- mMsMatrix(x=20, y=20)
    ## pvaluePlot(elist=elist.unlog, group1=c1, group2=c2, log=FALSE, method="mMs",
    ## mMs.matrix1=mMs.matrix1, mMs.matrix2=mMs.matrix2, above=1500,
    ## between=400)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_paa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_paa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_paa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PAA:", paste0("    paa: ", packageVersion("PAA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_paa_results.csv
    touch ${prefix}_paa_output.rds
    echo "BIOC_PAA:" > versions.yml
    echo "    paa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PAA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PAA(ch_input)

    emit:
    results  = BIOC_PAA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PAA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PAA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PAA.out.versions  // channel: path(versions.yml)
}
