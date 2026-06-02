#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iCheck
// QC pipeline and data analysis tools for high-dimensional Illumina mRNA expression data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iCheck/inst/doc/iCheck.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("iCheck")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ICHECK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-icheck"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-icheck:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-icheck:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_icheck_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_icheck_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_icheck_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(R2PlotFunc)
    library(jsonlite)

    # --- Plotqccurves [] ---
    # Key functions: plotQCCurves
    plotQCCurves(
             esQC=es.QC,
             probes = c("biotin"), #"cy3_hyb", "housekeeping"),
               #"low_stringency_hyb"),
             labelVariable = "subjID",
    # --- R2 Plot Func [] ---
    # Key functions: R2PlotFunc, greenred

    # --- Table [] ---
    # Key functions: dims
    print(table(es.raw$Tissue_Descr, useNA="ifany"))
    # for different data sets, the label for GC arrays might
    # be different.
    pos.del<-which(es.raw$Tissue_Descr == "Human Hela Cell")
    cat("No. of GC arrays=", length(pos.del), "\n")
    # --- R2 Plot Func [] ---
    # Key functions: R2PlotFunc, greenred

    # --- Densityplots [] ---
    # Key functions: densityPlots

    # --- Quantileplot [] ---
    # Key functions: quantilePlot, exprs, n

    # --- plot Samplep95p05 [] ---
    # Key functions: plotSamplep95p05

    # --- Quantile [] ---
    # Key functions: exprs
    p95<-quantile(exprs(es.raw), prob=0.95)
    p05<-quantile(exprs(es.raw), prob=0.05)
    r<-p95/p05
    pos.del<-which(r<6)
    print(pos.del)
    # --- Getpcafunc [] ---
    # Key functions: getPCAFunc
    pcaObj<-getPCAFunc(es=es.raw,
                    labelVariable = "subjID",
                    requireLog2 = FALSE,
                    corFlag = FALSE
         )
    # --- pca2 D Plot [] ---
    # Key functions: pca2DPlot, pcas

    # --- Lumin [] ---
    # Key functions: lumiN
    tt <- es.raw
    es.q<-lumiN(tt, method="quantile")
    # --- Getpcafunc [] ---
    # Key functions: getPCAFunc, pca2DPlot, pcas, n
    pcaObj<-getPCAFunc(es=es.q,
                    labelVariable = "subjID",
                    requireLog2 = FALSE,
                    corFlag = FALSE
         )
    # --- Lmfitwrapper [] ---
    # Key functions: lmFitWrapper, factor

    # --- Glmwrapper [] ---
    # Key functions: glmWrapper, factor

    # --- Lkhrwrapper [] ---
    # Key functions: lkhrWrapper, factor


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_icheck_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_icheck_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_icheck_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ICHECK:", paste0("    icheck: ", packageVersion("iCheck"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_icheck_results.csv
    touch ${prefix}_icheck_output.rds
    echo "BIOC_ICHECK:" > versions.yml
    echo "    icheck: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ICHECK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ICHECK(ch_input)

    emit:
    results  = BIOC_ICHECK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ICHECK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ICHECK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ICHECK.out.versions  // channel: path(versions.yml)
}
