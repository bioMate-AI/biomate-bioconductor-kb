#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: chimeraviz
// chimeraviz manages data from fusion gene finders and provides useful visualization tools.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/chimeraviz/inst/doc/chimeraviz-vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("chimeraviz")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHIMERAVIZ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chimeraviz"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chimeraviz:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-chimeraviz:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chimeraviz_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chimeraviz_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chimeraviz_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(chimeraviz)
    library(jsonlite)

    # --- Write Fusion Reference [] ---
    # Key functions: write_fusion_reference
    ---------------------------------------------------------------------
    referenceFilename <- "reference.fa"
    write_fusion_reference(fusion = fusion, filename = referenceFilename)
    # --- Add Fusion Reads Alignment [] ---
    # Key functions: add_fusion_reads_alignment
    ---------------------------------------------------------------------
    # Add bamfile of fusion reads to the fusion oject
    fusion <- add_fusion_reads_alignment(fusion, bamfile5267)
    # --- Get Fusion By Gene Name [] ---
    # Key functions: get_fusion_by_gene_name
    ---------------------------------------------------------------------
    # See if we can find any fusions involving RCC1
    get_fusion_by_gene_name(fusions, "RCC1")
    # --- Get Fusion By Id [] ---
    # Key functions: get_fusion_by_id
    ---------------------------------------------------------------------
    # Extract the specific fusion
    fusion <- get_fusion_by_id(fusions, 5267)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chimeraviz_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chimeraviz_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chimeraviz_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHIMERAVIZ:", paste0("    chimeraviz: ", packageVersion("chimeraviz"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chimeraviz_results.csv
    touch ${prefix}_chimeraviz_output.rds
    echo "BIOC_CHIMERAVIZ:" > versions.yml
    echo "    chimeraviz: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHIMERAVIZ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHIMERAVIZ(ch_input)

    emit:
    results  = BIOC_CHIMERAVIZ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHIMERAVIZ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHIMERAVIZ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHIMERAVIZ.out.versions  // channel: path(versions.yml)
}
