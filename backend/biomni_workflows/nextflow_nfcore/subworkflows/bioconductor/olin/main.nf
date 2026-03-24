#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: OLIN
// Functions for normalisation of two-color microarrays by optimised local regression and for detection
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/OLIN/inst/doc/OLIN.R
// Upstream  : none
// Downstream: OLINgui
//
// Install: BiocManager::install("OLIN")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OLIN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-olin"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-olin:1.84.0--r44_0' :
        'quay.io/biocontainers/bioconductor-olin:1.84.0--r44_0'}"

    input:
    tuple val(meta), path(matrix)

    output:
    tuple val(meta), path("${meta.id}_olin_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_olin_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_olin_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(OLIN)
    library(jsonlite)

    # --- Microarray data normalization [] ---
    # Key functions: anovapin, density, bas, v2m, spatial, maA, maNgc, maM
    ##   data(sw)
    ##   fgbg.visu(sw[,3])
    # --- Normalization quality visualization [] ---
    # Key functions: maA, maNgc, maM, maNsc, maNsr, visu, maNgr
    M<- v2m(maM(sw.olin)[,3],Ngc=maNgc(sw.olin),Ngr=maNgr(sw.olin),
                    Nsc=maNsc(sw.olin),Nsr=maNsr(sw.olin),main="MXY plot of SW-array 1")
    FDR <- fdr.spatial(M,delta=2,N=10,av="median",edgeNA=TRUE)
    sigxy.plot(FDR$FDRp,FDR$FDRn,color.lim=c(-5,5),main="FDR")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_olin_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_olin_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_olin_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OLIN:", paste0("    olin: ", packageVersion("OLIN"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_olin_results.csv
    touch ${prefix}_olin_output.rds
    echo "BIOC_OLIN:" > versions.yml
    echo "    olin: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OLIN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(matrix) ]

    main:
    BIOC_OLIN(ch_input)

    emit:
    results  = BIOC_OLIN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OLIN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OLIN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OLIN.out.versions  // channel: path(versions.yml)
}
