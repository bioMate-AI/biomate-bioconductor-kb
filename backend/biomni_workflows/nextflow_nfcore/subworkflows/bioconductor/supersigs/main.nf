#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: supersigs
// Generate SuperSigs (supervised mutational signatures) from single nucleotide variants in the cancer 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/supersigs/inst/doc/supersigs.R
// Upstream  : VariantAnnotation, dplyr, ggplot2
// Downstream: none
//
// Install: BiocManager::install("supersigs")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SUPERSIGS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-supersigs"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-supersigs:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-supersigs:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_supersigs_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_supersigs_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_supersigs_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SMOKING)
    library(jsonlite)

    # --- Make Matrix [] ---
    # Key functions: make_matrix
    ---------------------------------------------------------------------
    input_dt <- make_matrix(example_dt)
    head(input_dt)
    # --- Simplify Signature [] ---
    # Key functions: simplify_signature
    ---------------------------------------------------------------------
    features <- simplify_signature(object = supersig, iupac = FALSE)
    features_iupac <- simplify_signature(object = supersig, iupac = TRUE)
    # --- Frame [] ---
    # Key functions: frame, ggplot, aes, geom_col, theme_minimal
    ---------------------------------------------------------------------
    library(ggplot2)
    data.frame(features = names(features_iupac),
               differences = features_iupac) %>%
      ggplot(aes(x = features, y = differences)) +
    # --- Predict Signature [] ---
    # Key functions: predict_signature, select
    ---------------------------------------------------------------------
    newdata = predict_signature(supersig, newdata = input_dt, factor = "Smoking")
    newdata %>%
      select(X1, score)
    # --- Predict Signature [] ---
    # Key functions: predict_signature, SMOKING, select
    ---------------------------------------------------------------------
    # Use pre-trained signature
    newdata = predict_signature(supersig_ls[["SMOKING (LUAD)"]],
                                newdata = input_dt, factor = "Smoking")
    newdata %>%
    # --- Partial Signature [] ---
    # Key functions: partial_signature
    ---------------------------------------------------------------------
    adjusted_dt <- partial_signature(data = input_dt, object = supersig)
    head(adjusted_dt)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_supersigs_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_supersigs_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_supersigs_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SUPERSIGS:", paste0("    supersigs: ", packageVersion("supersigs"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_supersigs_results.csv
    touch ${prefix}_supersigs_output.rds
    echo "BIOC_SUPERSIGS:" > versions.yml
    echo "    supersigs: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SUPERSIGS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SUPERSIGS(ch_input)

    emit:
    results  = BIOC_SUPERSIGS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SUPERSIGS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SUPERSIGS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SUPERSIGS.out.versions  // channel: path(versions.yml)
}
