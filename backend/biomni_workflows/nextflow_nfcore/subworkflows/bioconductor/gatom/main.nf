#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gatom
// This package implements a metabolic network analysis pipeline to identify an active metabolic module
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gatom/inst/doc/gatom-tutorial.R
// Upstream  : igraph, mwcsr
// Downstream: none
//
// Install: BiocManager::install("gatom")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GATOM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gatom"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gatom:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gatom:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gatom_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gatom_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gatom_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(gatom)
    library(E)
    library(jsonlite)

    # --- Graph Scoring [] ---
    # Key functions: scoreGraph
    gs <- scoreGraph(
        g = g,
        k.gene = 25,
        k.met = 25
    )


    # --- Subgraph Optimization [] ---
    # Key functions: rnc_solver, solve_mwcsp
    solver <- rnc_solver()
    res <- solve_mwcsp(
        solver = solver,
        g = gs
    )
    m <- res$graph


    # --- Module Export and Visualization [] ---
    # Key functions: saveModuleToHtml, saveModuleToPdf, saveModuleToDot, createShinyCyJSWidget
    html_path <- file.path(tempdir(), "M0.vs.M1.html")
    pdf_path <- file.path(tempdir(), "M0.vs.M1.pdf")
    dot_path <- file.path(tempdir(), "M0.vs.M1.dot")
    saveModuleToHtml(
        module = m,
        file = html_path,
        name = "M0.vs.M1"
    )
    saveModuleToDot(
        module = m,
        file = dot_path,
        name = "M0.vs.M1"
    )
    saveModuleToPdf(
        module = m,
        file = pdf_path,
        name = "M0.vs.M1",
        n_iter = 100,
        force = 1e-5
    )
    widget <- createShinyCyJSWidget(m)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gatom_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gatom_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gatom_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GATOM:", paste0("    gatom: ", packageVersion("gatom"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gatom_results.csv
    touch ${prefix}_gatom_output.rds
    echo "BIOC_GATOM:" > versions.yml
    echo "    gatom: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GATOM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GATOM(ch_input)

    emit:
    results  = BIOC_GATOM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GATOM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GATOM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GATOM.out.versions  // channel: path(versions.yml)
}
