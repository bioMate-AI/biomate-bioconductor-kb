#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TDbasedUFE
// This is a comprehensive package to perform Tensor decomposition based unsupervised feature extractio
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TDbasedUFE/inst/doc/QuickStart.R
// Upstream  : GenomicRanges, MOFAdata, rTensor, readr, tximport
// Downstream: none
//
// Install: BiocManager::install("TDbasedUFE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TDBASEDUFE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tdbasedufe"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tdbasedufe:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tdbasedufe:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tdbasedufe_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tdbasedufe_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tdbasedufe_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PrepareSummarizedExperimentTensor)
    library(PrepareSummarizedExperimentTensorSquare)
    library(jsonlite)

    # --- Preparesummarizedexperimenttensor [] ---
    # Key functions: PrepareSummarizedExperimentTensor, array, attr, computeHosvd
    ---------------------------------------------------------------------
    Z <- PrepareSummarizedExperimentTensor(matrix(samples$sample,c(3,2)),
        rownames(txi$abundance),array(txi$counts,c(dim(txi$counts)[1],3,2)))
    dim(attr(Z,"value"))
    HOSVD <- computeHosvd(Z)
    # --- Selectsingularvaluevectorsmall [] ---
    # Key functions: selectSingularValueVectorSmall
    ---------------------------------------------------------------------
    input_all <- selectSingularValueVectorSmall(HOSVD,input_all= c(1,2)) #batch mode
    # --- Selectfeature [] ---
    # Key functions: selectFeature
    ---------------------------------------------------------------------
    index <- selectFeature(HOSVD,input_all)
    # --- Head [] ---
    # Key functions: tableFeatures
    ---------------------------------------------------------------------
    head(tableFeatures(Z,index))
    # --- Preparesummarizedexperimenttensorsquare [] ---
    # Key functions: PrepareSummarizedExperimentTensorSquare, convertSquare, computeHosvdSqure
    ---------------------------------------------------------------------
    # --- Table [] ---
    # Key functions: attr
    ---------------------------------------------------------------------
    table(CLL_covariates[,1])
    cond <- list(attr(Z,"sampleData")[[1]],attr(Z,"sampleData")[[1]],seq_len(4))
    # --- Selectsingularvaluevectorlarge [] ---
    # Key functions: selectSingularValueVectorLarge
    ---------------------------------------------------------------------
    input_all <- selectSingularValueVectorLarge(HOSVD,cond,input_all=c(8,1))
    # --- Selectfeaturesquare [] ---
    # Key functions: selectFeatureSquare
    ---------------------------------------------------------------------
    index <- selectFeatureSquare(HOSVD,input_all,CLL_data,
        de=c(0.3,0.03,0.1,0.1),interact=FALSE) #for batch mode

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tdbasedufe_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tdbasedufe_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tdbasedufe_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TDBASEDUFE:", paste0("    tdbasedufe: ", packageVersion("TDbasedUFE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tdbasedufe_results.csv
    touch ${prefix}_tdbasedufe_output.rds
    echo "BIOC_TDBASEDUFE:" > versions.yml
    echo "    tdbasedufe: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TDBASEDUFE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TDBASEDUFE(ch_input)

    emit:
    results  = BIOC_TDBASEDUFE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TDBASEDUFE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TDBASEDUFE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TDBASEDUFE.out.versions  // channel: path(versions.yml)
}
