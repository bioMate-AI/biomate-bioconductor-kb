#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: microbiomeMarker
// To date, a number of methods have been developed for microbiome marker discovery based on metagenomi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/microbiomeMarker/inst/doc/microbiomeMarker-vignette.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("microbiomeMarker")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MICROBIOMEMARKER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-microbiomemarker"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-microbiomemarker:1.12.2--r44_0' :
        'quay.io/biocontainers/bioconductor-microbiomemarker:1.12.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_microbiomemarker_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_microbiomemarker_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_microbiomemarker_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(microbiomeMarker)
    library(jsonlite)

    # --- Data import and preprocessing [] ---
    # Key functions: import_dada2
    seq_tab <- readRDS(
    system.file(
    tax_tab <- readRDS(
    # --- Subset taxa by criteria [] ---
    # Key functions: subset_taxa, run_lefse, run_sl, marker_table
    set.seed(2021)
    ps_small <- phyloseq::subset_taxa(
    Phylum %in% c("Firmicutes", "Bacteroidetes")
    # --- Data normalization [] ---
    # Key functions: install_github, import_qiime2, norm_tss, normalize, run_lefse, run_test_two_groups, subset_samples, run_test_multiple_groups
    pht <- run_posthoc_test(ps, group = "Enterotype")
    markers <- marker_table(mg_anova)$feature
    extract_posthoc_res(pht, "p__Bacteroidetes|g__Bacteroides")[[1]]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_microbiomemarker_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_microbiomemarker_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_microbiomemarker_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MICROBIOMEMARKER:", paste0("    microbiomemarker: ", packageVersion("microbiomeMarker"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microbiomemarker_results.csv
    touch ${prefix}_microbiomemarker_output.rds
    echo "BIOC_MICROBIOMEMARKER:" > versions.yml
    echo "    microbiomemarker: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MICROBIOMEMARKER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MICROBIOMEMARKER(ch_input)

    emit:
    results  = BIOC_MICROBIOMEMARKER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MICROBIOMEMARKER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MICROBIOMEMARKER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MICROBIOMEMARKER.out.versions  // channel: path(versions.yml)
}
