#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tilingArray
// The package provides functionality that can be useful for the analysis of high-density tiling microa
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tilingArray/inst/doc/findsegments.R
// Upstream  : none
// Downstream: davidTiling
//
// Install: BiocManager::install("tilingArray")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TILINGARRAY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tilingarray"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tilingarray:1.84.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tilingarray:1.84.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tilingarray_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tilingarray_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tilingarray_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(tilingArray)
    library(jsonlite)

    # --- Defgendata [] ---
    # Key functions: sample
    genData = function(lenx, nrSeg, nrRep=1, stddev=0.1) {
      x  = matrix(as.numeric(NA), nrow=lenx, ncol=nrRep)
      cp = sort(sample(1:floor(lenx/15), nrSeg-1) * 15)
      cpb = c(1, cp, lenx+1)
      s  = 0
    # --- Plotdata [] ---
    # Key functions: genData
    set.seed(4711)
    lenx = 1000
    nrSeg = 10
    gd = genData(lenx, nrSeg)
    plot(gd$x, pch=".")
    # --- Findsegments [] ---
    # Key functions: segment
    maxseg = 12
    maxk = 500
    seg  = segment(gd$x, maxk=maxk, maxseg=maxseg)
    seg
    seg@breakpoints[nrSeg+(-1:1)]
    # --- Testcp [] ---
    # Key functions: genData, segment
    for(i in 1:20){
      gd  = genData(lenx, nrSeg)
      seg = segment(gd$x, maxk=maxk, maxseg=maxseg)
      stopifnot(seg@breakpoints[[nrSeg]][, "estimate"] == gd$cp)
    }
    # --- Modelselect1 [] ---
    # Key functions: genData, segment
    nrSeg = 22
    gd = genData(lenx, nrSeg, nrRep=2, stddev=1/3)
    s = segment(gd$x, maxk=lenx, maxseg=as.integer(nrSeg * 2.5))
    # --- Plotsimseg [] ---
    # Key functions: row
    par(mai=c(1,1,0.1,0.01))
    plot(row(gd$x), gd$x, pch=".")
    # --- Penllsim [] ---
    # Key functions: plotPenLL
    par(mai=c(1,1,0.1,0.01))
    plotPenLL(s)
    # --- Printmaxima [] ---
    # Key functions: logLik
    which.max(logLik(s, penalty="AIC"))
    which.max(logLik(s, penalty="BIC"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tilingarray_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tilingarray_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tilingarray_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TILINGARRAY:", paste0("    tilingarray: ", packageVersion("tilingArray"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tilingarray_results.csv
    touch ${prefix}_tilingarray_output.rds
    echo "BIOC_TILINGARRAY:" > versions.yml
    echo "    tilingarray: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TILINGARRAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TILINGARRAY(ch_input)

    emit:
    results  = BIOC_TILINGARRAY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TILINGARRAY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TILINGARRAY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TILINGARRAY.out.versions  // channel: path(versions.yml)
}
