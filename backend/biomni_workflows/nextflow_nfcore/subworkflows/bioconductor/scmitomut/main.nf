#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scMitoMut
// This package is designed for calling lineage-informative mitochondrial mutations using single-cell s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scMitoMut/inst/doc/Analysis_colon_cancer_dataset.R
// Upstream  : knitr
// Downstream: none
//
// Install: BiocManager::install("scMitoMut")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCMITOMUT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scmitomut"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scmitomut:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scmitomut:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scmitomut_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scmitomut_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scmitomut_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scMitoMut)
    library(jsonlite)

    # --- Cell Subsetting [] ---
    # Key functions: subset_cell
    f_ann <- system.file(
        "extdata",
        "mini_dataset_cell_ann.csv",
        package = "scMitoMut"
    )
    cell_ann <- read.csv(f_ann, row.names = 1)
    x <- subset_cell(x, rownames(cell_ann))


    # --- Model Fitting [] ---
    # Key functions: run_model_fit
    run_model_fit(x, mc.cores = 1)


    # --- Mutation Filtering [] ---
    # Key functions: filter_loc
    x <- filter_loc(
        mtmutObj = x,
        min_cell = 2,
        model = "bb",
        p_threshold = 0.01,
        p_adj_method = "fdr"
    )


    # --- Visualization [] ---
    # Key functions: plot_heatmap
    colors <- c("Cancer Epi" = "#f28482", Blood = "#f6bd60")
    ann_colors <- list("SeuratCellTypes" = colors)
    plot_heatmap(
        x,
        cell_ann = cell_ann,
        ann_colors = ann_colors,
        type = "binary",
        percent_interp = 0.2,
        n_interp = 3
    )


    # --- Data Export [] ---
    # Key functions: export_df, export_af, export_pval, export_binary
    m_df <- export_df(x)
    m_af <- export_af(x)
    m_pval <- export_pval(x)
    m_bin <- export_binary(x)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scmitomut_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scmitomut_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scmitomut_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCMITOMUT:", paste0("    scmitomut: ", packageVersion("scMitoMut"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scmitomut_results.csv
    touch ${prefix}_scmitomut_output.rds
    echo "BIOC_SCMITOMUT:" > versions.yml
    echo "    scmitomut: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCMITOMUT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCMITOMUT(ch_input)

    emit:
    results  = BIOC_SCMITOMUT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCMITOMUT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCMITOMUT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCMITOMUT.out.versions  // channel: path(versions.yml)
}
