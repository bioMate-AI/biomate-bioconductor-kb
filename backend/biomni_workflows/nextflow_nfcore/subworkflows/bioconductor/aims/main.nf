#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AIMS
// This package contains the AIMS implementation. It contains necessary functions to assign the five in
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/AIMS/inst/doc/AIMS.R
// Upstream  : breastCancerVDX
// Downstream: none
//
// Install: BiocManager::install("AIMS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AIMS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-aims"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-aims:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-aims:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_aims_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_aims_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_aims_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ExpressionSet)
    library(jsonlite)

    # --- Loadpackages [] ---
    # Key functions: data
    library(AIMS)
    data(mcgillExample)
    # --- Showmcgill [] ---
    # Key functions: ExpressionSet
    dim(mcgillExample$D)
    ## convert the expression matrix to an ExpressionSet (Biobase)
    mcgillExample$D <- ExpressionSet(assayData=mcgillExample$D)
    head(mcgillExample$D[,1:5])
    head(mcgillExample$EntrezID)
    # --- Assignsubtypetomcgill [] ---
    # Key functions: applyAIMS
    mcgill.subtypes <- applyAIMS(mcgillExample$D,
                                 mcgillExample$EntrezID)
    names(mcgill.subtypes)
    head(mcgill.subtypes$cl)
    head(mcgill.subtypes$prob)
    # --- Assignesampleonesubtypemcgill [] ---
    # Key functions: applyAIMS
    mcgill.first.sample.subtype <- applyAIMS(mcgillExample$D[,1,drop=FALSE],
                                             mcgillExample$EntrezID)
    names(mcgill.first.sample.subtype)
    head(mcgill.first.sample.subtype$cl)
    head(mcgill.first.sample.subtype$prob)
    # --- Assignsubtypetovdx [] ---
    # Key functions: featureNames, applyAIMS
    library(breastCancerVDX)
    library(hgu133a.db)
    data(vdx)
    hgu133a.entrez <- as.character(as.list(hgu133aENTREZID)[featureNames(vdx)])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_aims_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_aims_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_aims_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AIMS:", paste0("    aims: ", packageVersion("AIMS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_aims_results.csv
    touch ${prefix}_aims_output.rds
    echo "BIOC_AIMS:" > versions.yml
    echo "    aims: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AIMS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_AIMS(ch_input)

    emit:
    results  = BIOC_AIMS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AIMS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AIMS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AIMS.out.versions  // channel: path(versions.yml)
}
