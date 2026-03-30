#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: planttfhunter
// planttfhunter is used to identify plant transcription factors (TFs) from protein sequence data and c
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/planttfhunter/inst/doc/vignette_planttfhunter.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("planttfhunter")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PLANTTFHUNTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-planttfhunter"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-planttfhunter:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-planttfhunter:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_planttfhunter_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_planttfhunter_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_planttfhunter_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(planttfhunter)
    library(jsonlite)

    # --- kable [] ---
    # Key functions: kable
    data(classification_scheme)
    knitr::kable(classification_scheme)
    # --- identifying tfs [] ---
    # Key functions: annotate_pfam
    data(gsu_annotation)
    if(hmmer_is_installed()) {
    gsu_annotation <- annotate_pfam(gsu)
    # --- classifying tfs [] ---
    # Key functions: classify_tfs
    gsu_families <- classify_tfs(gsu_annotation)
    head(gsu_families)
    table(gsu_families$Family)
    # --- get tf counts [] ---
    # Key functions: get_tf_counts, assay, colData
    data(tf_counts)
    if(hmmer_is_installed()) {
    tf_counts <- get_tf_counts(proteomes, species_metadata)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_planttfhunter_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_planttfhunter_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_planttfhunter_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PLANTTFHUNTER:", paste0("    planttfhunter: ", packageVersion("planttfhunter"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_planttfhunter_results.csv
    touch ${prefix}_planttfhunter_output.rds
    echo "BIOC_PLANTTFHUNTER:" > versions.yml
    echo "    planttfhunter: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PLANTTFHUNTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PLANTTFHUNTER(ch_input)

    emit:
    results  = BIOC_PLANTTFHUNTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PLANTTFHUNTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PLANTTFHUNTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PLANTTFHUNTER.out.versions  // channel: path(versions.yml)
}
