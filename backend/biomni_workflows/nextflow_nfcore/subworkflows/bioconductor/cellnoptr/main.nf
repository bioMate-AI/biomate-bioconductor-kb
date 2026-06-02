#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CellNOptR
// This package does optimisation of boolean logic networks of signalling pathways based on a previous 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CellNOptR/inst/doc/CellNOptR-vignette.R
// Upstream  : doParallel, stringr
// Downstream: CNORdt, CNORfeeder, CNORfuzzy, CNORode
//
// Install: BiocManager::install("CellNOptR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CELLNOPTR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cellnoptr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cellnoptr:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cellnoptr:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cellnoptr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cellnoptr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cellnoptr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CellNOptR)
    library(jsonlite)

    # --- Preprocessing analysis [] ---
    # Key functions: install_github, preprocessing, gaBinaryT1, cutAndPlot, dir, readMIDAS, makeCNOlist, plotCNOlistPDF
    Option 1: copy the SIF and MIDAS files (followed by readMIDAS, makeCNOlist and readSIF)
    cpfile<-dir(system.file("DREAMModel",package="CellNOptR"),full=TRUE)
    file.copy(from=cpfile,to=getwd(),overwrite=TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cellnoptr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cellnoptr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cellnoptr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CELLNOPTR:", paste0("    cellnoptr: ", packageVersion("CellNOptR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cellnoptr_results.csv
    touch ${prefix}_cellnoptr_output.rds
    echo "BIOC_CELLNOPTR:" > versions.yml
    echo "    cellnoptr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CELLNOPTR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CELLNOPTR(ch_input)

    emit:
    results  = BIOC_CELLNOPTR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CELLNOPTR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CELLNOPTR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CELLNOPTR.out.versions  // channel: path(versions.yml)
}
