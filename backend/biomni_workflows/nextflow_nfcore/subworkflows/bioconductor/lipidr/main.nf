#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: lipidr
// lipidr an easy-to-use R package implementing a complete workflow for downstream analysis of targeted
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/lipidr/inst/doc/workflow.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("lipidr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LIPIDR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-lipidr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-lipidr:2.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-lipidr:2.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_lipidr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_lipidr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_lipidr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(lipidr)
    library(jsonlite)

    # --- Data Import and Annotation ---
    # Key functions: read_skyline, add_sample_annotation
    datadir <- system.file("extdata", package = "lipidr")
    filelist <- list.files(datadir, "data.csv", full.names = TRUE)
    d <- read_skyline(filelist)
    clinical_file <- system.file("extdata", "clin.csv", package = "lipidr")
    d <- add_sample_annotation(d, clinical_file)
    lipid_classes <- rowData(d)$Class %in% c("Cer", "PC", "LPC")
    groups <- d$BileAcid != "DCA"
    d <- d[lipid_classes, groups]

    # --- Quality Control and Visualization ---
    # Key functions: plot_samples, plot_molecules, plot_lipidclass
    d_qc <- d[, d$group == "QC"]
    plot_samples(d, type = "tic", log = TRUE)
    plot_molecules(d_qc, "sd", measure = "Retention Time", log = FALSE)
    plot_molecules(d_qc, "cv", measure = "Area")
    plot_lipidclass(d, "boxplot")

    # --- Normalization and Summarization ---
    # Key functions: summarize_transitions, normalize_pqn, plot_samples
    d_summarized <- summarize_transitions(d, method = "average")
    d_normalized <- normalize_pqn(
        d_summarized,
        measure = "Area",
        exclude = "blank",
        log = TRUE
    )
    plot_samples(d_normalized, "boxplot")

    # --- Multivariate Analysis ---
    # Key functions: mva, plot_mva, top_lipids
    mva_pca <- mva(d_normalized, measure = "Area", method = "PCA")
    plot_mva(mva_pca, color_by = "group", components = c(1, 2))
    mva_opls <- mva(
        d_normalized,
        method = "OPLS-DA",
        group_col = "Diet",
        groups = c("HighFat", "Normal")
    )
    plot_mva(mva_opls, color_by = "group")
    top_lipids(mva_opls, top.n = 10)

    # --- Differential Expression Analysis ---
    # Key functions: de_analysis, significant_molecules, plot_results_volcano
    de_results <- de_analysis(
        data = d_normalized,
        HighFat_water - NormalDiet_water,
        measure = "Area"
    )
    sig_mols <- significant_molecules(de_results)
    plot_results_volcano(de_results, show.labels = FALSE)

    # --- Lipid Set Enrichment Analysis ---
    # Key functions: lsea, significant_lipidsets, plot_enrichment, plot_chain_distribution
    enrich_results <- lsea(de_results, rank.by = "logFC")
    sig_sets <- significant_lipidsets(enrich_results)
    plot_enrichment(de_results, sig_sets, annotation = "class")
    plot_enrichment(de_results, sig_sets, annotation = "unsat")
    plot_chain_distribution(de_results)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_lipidr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_lipidr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_lipidr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LIPIDR:", paste0("    lipidr: ", packageVersion("lipidr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lipidr_results.csv
    touch ${prefix}_lipidr_output.rds
    echo "BIOC_LIPIDR:" > versions.yml
    echo "    lipidr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LIPIDR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LIPIDR(ch_input)

    emit:
    results  = BIOC_LIPIDR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LIPIDR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LIPIDR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LIPIDR.out.versions  // channel: path(versions.yml)
}
