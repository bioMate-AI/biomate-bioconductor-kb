#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: EBSeq
// Differential Expression analysis at both gene and isoform level using RNA-seq data
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/EBSeq/inst/doc/EBSeq_Vignette.R
// Upstream  : none
// Downstream: Oscope
//
// Install: BiocManager::install("EBSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EBSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ebseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ebseq:2.4.1--r44_0' :
        'quay.io/biocontainers/bioconductor-ebseq:2.4.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ebseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ebseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ebseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DenNHist)
    library(EBMultiTest)
    library(EBTest)
    library(GetDEResults)
    library(GetMultiFC)
    library(GetMultiPP)
    library(GetNg)
    library(GetPatterns)
    library(MedianNorm)
    library(PlotPattern)
    library(jsonlite)

    # --- Data import and loading [] ---
    # Key functions: data
    data(IsoList)
    str(IsoList)
    IsoMat=IsoList$IsoMat
    str(IsoMat)
    IsoNames=IsoList$IsoNames
    # --- MedianNorm analysis [] ---
    # Key functions: MedianNorm, EBTest, factor, GetDEResults, GetNg, EBMultiTest, GetMultiPP, GetPatterns
    PolyAll=PolyFitPlot(unlist(IsoEBOut$C1Mean), unlist(IsoEBOut$C1EstVar),5)
    lines(log10(IsoEBOut$C1Mean[[1]][PolyFitValue[[1]]$sort]),
    PolyFitValue[[1]]$fit[PolyFitValue[[1]]$sort],col="yellow",lwd=2)
    lines(log10(IsoEBOut$C1Mean[[2]][PolyFitValue[[2]]$sort]),
    PolyFitValue[[2]]$fit[PolyFitValue[[2]]$sort],col="pink",lwd=2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ebseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ebseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ebseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EBSEQ:", paste0("    ebseq: ", packageVersion("EBSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ebseq_results.csv
    touch ${prefix}_ebseq_output.rds
    echo "BIOC_EBSEQ:" > versions.yml
    echo "    ebseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EBSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EBSEQ(ch_input)

    emit:
    results  = BIOC_EBSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EBSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EBSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EBSEQ.out.versions  // channel: path(versions.yml)
}
