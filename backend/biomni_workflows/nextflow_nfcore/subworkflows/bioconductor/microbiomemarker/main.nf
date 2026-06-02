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

    # --- Normalisation [] ---
    # Key functions: normalize, norm_tss
    data(enterotypes_arumugam, package = "microbiomeMarker")
    ps_norm_tss <- norm_tss(enterotypes_arumugam)
    ps_norm_cpm <- normalize(enterotypes_arumugam, method = "CPM")


    # --- LEfSe Marker Discovery [] ---
    # Key functions: run_lefse, marker_table
    data(kostic_crc, package = "microbiomeMarker")
    kostic_sub <- phyloseq::subset_taxa(
        kostic_crc,
        Phylum %in% c("Firmicutes")
    )
    mm_lefse <- run_lefse(
        kostic_sub,
        wilcoxon_cutoff = 0.01,
        group = "DIAGNOSIS",
        kw_cutoff = 0.01,
        multigrp_strat = TRUE,
        lda_cutoff = 4
    )
    lefse_markers <- marker_table(mm_lefse)


    # --- Differential Abundance Analysis [] ---
    # Key functions: run_edger, run_limma_voom, marker_table
    data(pediatric_ibd, package = "microbiomeMarker")
    mm_edger <- run_edger(
        pediatric_ibd,
        group = "Class",
        pvalue_cutoff = 0.1,
        p_adjust = "fdr"
    )
    mm_limma <- run_limma_voom(
        pediatric_ibd,
        group = "Class",
        pvalue_cutoff = 0.1,
        p_adjust = "fdr"
    )
    edger_markers <- marker_table(mm_edger)


    # --- Machine Learning Marker Selection [] ---
    # Key functions: run_sl, marker_table
    data(enterotypes_arumugam, package = "microbiomeMarker")
    ps_small <- phyloseq::subset_taxa(
        enterotypes_arumugam,
        Phylum %in% c("Firmicutes", "Bacteroidetes")
    )
    mm_lr <- run_sl(
        ps_small,
        group = "Gender",
        nfolds = 2,
        nrepeats = 1,
        taxa_rank = "Genus",
        top_n = 15,
        norm = "TSS",
        method = "LR"
    )
    sl_markers <- marker_table(mm_lr)


    # --- Visualisation [] ---
    # Key functions: plot_abundance, plot_heatmap, plot_ef_bar, plot_ef_dot
    p_abundance <- plot_abundance(mm_lefse, group = "DIAGNOSIS")
    p_heatmap <- plot_heatmap(mm_edger, transform = "log10p", group = "Class")
    p_ef_bar <- plot_ef_bar(mm_lefse)
    p_ef_dot <- plot_ef_dot(mm_lefse)

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
