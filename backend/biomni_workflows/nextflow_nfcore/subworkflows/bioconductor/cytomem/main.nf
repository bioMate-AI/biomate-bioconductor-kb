#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cytoMEM
// MEM, Marker Enrichment Modeling, automatically generates and displays quantitative labels for cell p
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cytoMEM/inst/doc/Intro_to_Marker_Enrichment_Modeling_Analysis.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("cytoMEM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CYTOMEM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cytomem"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cytomem:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cytomem:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cytomem_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cytomem_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cytomem_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cytoMEM)
    library(MEM)
    library(MEM_RMSD)
    library(jsonlite)

    # --- Heatmap Generation [] ---
    # Key functions: build_heatmaps
    build_heatmaps(
        MEM_values,
        cluster.MEM = "both",
        cluster.medians = "none",
        cluster.IQRs = "none",
        display.thresh = 1,
        output.files = FALSE,
        labels = FALSE,
        only.MEMheatmap = FALSE
    )


    # --- Root Mean Square Deviation Analysis [] ---
    # Key functions: MEM_RMSD
    rmsd_res <- MEM_RMSD(
        MEM_values[[5]][[1]],
        format = NULL,
        output.matrix = FALSE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cytomem_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cytomem_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cytomem_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CYTOMEM:", paste0("    cytomem: ", packageVersion("cytoMEM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cytomem_results.csv
    touch ${prefix}_cytomem_output.rds
    echo "BIOC_CYTOMEM:" > versions.yml
    echo "    cytomem: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CYTOMEM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CYTOMEM(ch_input)

    emit:
    results  = BIOC_CYTOMEM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CYTOMEM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CYTOMEM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CYTOMEM.out.versions  // channel: path(versions.yml)
}
