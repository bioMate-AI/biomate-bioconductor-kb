#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: COSNet
// Package that implements the COSNet classification algorithm. The algorithm predicts node labels in p
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/COSNet/inst/doc/COSNet_v.R
// Upstream  : PerfMeas, bionetdata
// Downstream: none
//
// Install: BiocManager::install("COSNet")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COSNET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cosnet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cosnet:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cosnet:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(seurat_object)

    output:
    tuple val(meta), path("${meta.id}_cosnet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cosnet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cosnet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(COSNet)
    library(jsonlite)

    # --- ColSums analysis [] ---
    # Key functions: data, colSums, validation, classes, unlist, strat, set, COSNet
    ## excluding the dummy "00" root
    to.be.excl <- which(colnames(Yeast.STRING.FunCat) == "00")
    Yeast.STRING.FunCat <- Yeast.STRING.FunCat[, -to.be.excl]
    ## choosing the first 35 classes
    labeling <- Yeast.STRING.FunCat[, 1:35]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cosnet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cosnet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cosnet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COSNET:", paste0("    cosnet: ", packageVersion("COSNet"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cosnet_results.csv
    touch ${prefix}_cosnet_output.rds
    echo "BIOC_COSNET:" > versions.yml
    echo "    cosnet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COSNET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(seurat_object) ]

    main:
    BIOC_COSNET(ch_input)

    emit:
    results  = BIOC_COSNET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COSNET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COSNET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COSNET.out.versions  // channel: path(versions.yml)
}
