#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CRImage
// CRImage provides functionality to process and analyze images, in particular to classify cells in bio
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CRImage/inst/doc/CRImage.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CRImage")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CRIMAGE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-crimage"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-crimage:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-crimage:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_crimage_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_crimage_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_crimage_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CRImage)
    library(jsonlite)

    # --- Create [] ---
    # Key functions: create, processAperio
    ## dir.create("AperiOutput")
    ## f = system.file("extdata",  package="CRImage")
    ## processAperio(classifier=classifier,inputFolder=f,outputFolder="AperiOutput",identifier="Da",numSections=2,cancerIdentifier="c",maxShape=800,minShape=40,failureRegion=2000)
    # --- Plotcorrectedcn [] ---
    # Key functions: plotCorrectedCN
    ## 	plotCorrectedCN(res, chr=1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_crimage_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_crimage_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_crimage_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CRIMAGE:", paste0("    crimage: ", packageVersion("CRImage"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_crimage_results.csv
    touch ${prefix}_crimage_output.rds
    echo "BIOC_CRIMAGE:" > versions.yml
    echo "    crimage: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CRIMAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CRIMAGE(ch_input)

    emit:
    results  = BIOC_CRIMAGE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CRIMAGE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CRIMAGE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CRIMAGE.out.versions  // channel: path(versions.yml)
}
