#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rsbml
// Links R to libsbml for SBML parsing, validating output, provides an S4 SBML DOM, converts SBML to R 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rsbml/inst/doc/quick-start.R
// Upstream  : none
// Downstream: BiGGR
//
// Install: BiocManager::install("rsbml")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RSBML {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rsbml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rsbml:2.64.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rsbml:2.64.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rsbml_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rsbml_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rsbml_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rsbml)
    library(jsonlite)

    # --- Dom [] ---
    # Key functions: rsbml_dom
    dom <- rsbml_dom(doc)
    # --- Ids [] ---
    # Key functions: species, model
    sapply(species(model(dom)), id)
    # --- Graph [] ---
    # Key functions: rsbml_graph, nodes
    g <- rsbml_graph(doc)
    graph::nodes(g)
    # --- Problems [] ---
    # Key functions: rsbml_read
    tryCatch(rsbml_read("non-existent-file.xml"),
             error = function(err) err$msg)
    # --- Xml [] ---
    # Key functions: rsbml_xml
    xml <- rsbml_xml(doc)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rsbml_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rsbml_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rsbml_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RSBML:", paste0("    rsbml: ", packageVersion("rsbml"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rsbml_results.csv
    touch ${prefix}_rsbml_output.rds
    echo "BIOC_RSBML:" > versions.yml
    echo "    rsbml: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RSBML_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RSBML(ch_input)

    emit:
    results  = BIOC_RSBML.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RSBML.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RSBML.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RSBML.out.versions  // channel: path(versions.yml)
}
