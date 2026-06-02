#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: OMICsPCA
// OMICsPCA is an analysis pipeline designed to integrate multi OMICs experiments done on various subje
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/OMICsPCA/inst/doc/vignettes.R
// Upstream  : MultiAssayExperiment, OMICsPCAdata, cluster, factoextra, ggplot2
// Downstream: none
//
// Install: BiocManager::install("OMICsPCA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OMICSPCA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-omicspca"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-omicspca:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-omicspca:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_omicspca_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_omicspca_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_omicspca_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(OMICsPCA)
    library(jsonlite)

    # --- Group Creation and Descriptive Analysis [] ---
    # Key functions: create_group, descriptor
    groupinfo <- create_group(name = multi_assay, 
                              group_names = c("WE", "RE", "NE", "IntE"),
                              grouping_factor = "CAGE",
                              comparison = c(">=", "%in%", "==", "%in%"),
                              condition = c("25", "1:5", "0", "6:24"))
    descriptor(name = multi_assay, 
               factors = c("H2az", "H3k4me1", "H3k9ac"),
               groups = c("WE", "RE"), choice = 1, 
               title = "Distribution of cell types", 
               groupinfo = groupinfo)


    # --- Correlation Analysis and Integration [] ---
    # Key functions: chart_correlation, integrate_variables
    chart_correlation(name = multi_assay, Assay = "H2az",
                      groups = "WE", choice = "scatter", 
                      groupinfo = groupinfo)
    PCAlist <- integrate_variables(Assays = c("H2az", "H3k4me1", "H3k9ac"), 
                                   name = multi_assay,
                                   groups = c("WE", "RE", "NE", "IntE"), 
                                   groupinfo = groupinfo,
                                   scale.unit = FALSE, graph = FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_omicspca_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_omicspca_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_omicspca_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OMICSPCA:", paste0("    omicspca: ", packageVersion("OMICsPCA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_omicspca_results.csv
    touch ${prefix}_omicspca_output.rds
    echo "BIOC_OMICSPCA:" > versions.yml
    echo "    omicspca: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OMICSPCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OMICSPCA(ch_input)

    emit:
    results  = BIOC_OMICSPCA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OMICSPCA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OMICSPCA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OMICSPCA.out.versions  // channel: path(versions.yml)
}
