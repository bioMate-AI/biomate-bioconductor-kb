#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scry
// Many modern biological datasets consist of small counts that are not well fit by standard linear-Gau
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scry/inst/doc/bigdata.R
// Upstream  : DuoClustering2018, SingleCellExperiment, TENxPBMCData, ggplot2
// Downstream: none
//
// Install: BiocManager::install("scry")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCRY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scry"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scry:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scry:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(input_file)

    output:
    tuple val(meta), path("${meta.id}_scry_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scry_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scry_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Matrix)
    library(TENxPBMCData)
    library(jsonlite)

    # --- Tenxpbmcdata [] ---
    # Key functions: TENxPBMCData, counts, rowSums, time, devianceFeatureSelection
    ---------------------------------------------------------------------
    sce<-TENxPBMCData(dataset="pbmc3k")
    h5counts<-counts(sce)
    seed(h5counts) #print information about object
    h5counts<-h5counts[rowSums(h5counts)>0,]
    # --- Matrix [] ---
    # Key functions: time, devianceFeatureSelection
    ---------------------------------------------------------------------
    denseCounts<-as.matrix(h5counts)
    system.time(denseDevs<-devianceFeatureSelection(denseCounts)) # 5 sec
    max(abs(denseDevs-h5devs)) #should be close to zero
    # --- Mean [] ---
    # Key functions: Matrix, time, devianceFeatureSelection
    ---------------------------------------------------------------------
    mean(denseCounts>0) #shows that the data are mostly zeros so sparsity useful
    sparseCounts<-Matrix::Matrix(denseCounts,sparse=TRUE)
    system.time(sparseDevs<-devianceFeatureSelection(sparseCounts)) #1.6 sec
    max(abs(sparseDevs-h5devs)) #should be close to zero

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scry_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scry_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scry_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCRY:", paste0("    scry: ", packageVersion("scry"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scry_results.csv
    touch ${prefix}_scry_output.rds
    echo "BIOC_SCRY:" > versions.yml
    echo "    scry: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCRY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input_file) ]

    main:
    BIOC_SCRY(ch_input)

    emit:
    results  = BIOC_SCRY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCRY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCRY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCRY.out.versions  // channel: path(versions.yml)
}
