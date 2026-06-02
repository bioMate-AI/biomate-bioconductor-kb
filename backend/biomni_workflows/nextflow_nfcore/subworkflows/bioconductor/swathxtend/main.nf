#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SwathXtend
// Contains utility functions for integrating spectral libraries for SWATH and statistical data analysi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SwathXtend/inst/doc/SwathXtend_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SwathXtend")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SWATHXTEND {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-swathxtend"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-swathxtend:2.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-swathxtend:2.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_swathxtend_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_swathxtend_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_swathxtend_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SwathXtend)
    library(jsonlite)

    # --- Cleanlib [] ---
    # Key functions: cleanLib
    ## Lib2 <- cleanLib(Lib2, intensity.cutoff = 5, conf.cutoff = 0.99,
    ## 			nomod = FALSE, nomc = FALSE)
    ## Lib3 <- cleanLib(Lib3, intensity.cutoff = 5, conf.cutoff = 0.99,
    ## 			nomod = FALSE, nomc = FALSE)
    # --- Plotrtcor [] ---
    # Key functions: plotRTCor
    plotRTCor(Lib2, Lib3, "Lib2", "Lib3")
    # --- Plotrtresd [] ---
    # Key functions: plotRTResd
    plotRTResd(Lib2, Lib3)
    # --- Plotriicor [] ---
    # Key functions: plotRIICor
    plotRIICor(Lib2, Lib3)
    # --- Buildspectralibpair [] ---
    # Key functions: buildSpectraLibPair

    # --- Outputlib [] ---
    # Key functions: outputLib
    ## outputLib(Lib2_3, filename="Lib2_3.txt", format="peakview")
    # --- Readworkbook [] ---
    # Key functions: readWorkbook
    fdr.seed = readWorkbook(fswaths[1], sheet='FDR')
    fdr.ext = readWorkbook(fswaths[2], sheet='FDR')
    # --- Crit [] ---
    # Key functions: crit
    fdr.seed = fdr.crit(fdr.seed)
    fdr.ext = fdr.crit(fdr.ext)
    head(fdr.ext[,c(1:2,ncol(fdr.ext))])
    # --- Readworkbook [] ---
    # Key functions: readWorkbook
    ## swa.seed = readWorkbook(fswaths[1], 2)
    ## swa.ext = readWorkbook(fswaths[2], 2)
    # --- Accuracy [] ---
    # Key functions: accuracy
    ## fdr.seed = fdr.seed[fdr.seed$nfdr.pass > 0,]
    ## fdr.ext = fdr.ext[fdr.ext$nfdr.pass > 0,]
    ##
    ## res = quantification.accuracy(swa.seed[fdr.seed$nfdr.pass >= 1,],
    ## 	swa.ext[fdr.ext$nfdr.pass >= 1,], method="cv")[[1]]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_swathxtend_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_swathxtend_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_swathxtend_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SWATHXTEND:", paste0("    swathxtend: ", packageVersion("SwathXtend"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_swathxtend_results.csv
    touch ${prefix}_swathxtend_output.rds
    echo "BIOC_SWATHXTEND:" > versions.yml
    echo "    swathxtend: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SWATHXTEND_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SWATHXTEND(ch_input)

    emit:
    results  = BIOC_SWATHXTEND.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SWATHXTEND.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SWATHXTEND.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SWATHXTEND.out.versions  // channel: path(versions.yml)
}
