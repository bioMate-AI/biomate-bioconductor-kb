#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CEMiTool
// The CEMiTool package unifies the discovery and the analysis of coexpression gene modules in a fully 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CEMiTool/inst/doc/CEMiTool.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("CEMiTool")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CEMITOOL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cemitool"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cemitool:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cemitool:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cemitool_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cemitool_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cemitool_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CEMiTool)
    library(jsonlite)

    # --- Nmodules [] ---
    # Key functions: nmodules, module_genes
    ---------------------------------------------------------------------
    # inspect modules
    nmodules(cem)
    head(module_genes(cem))
    # --- Write Files [] ---
    # Key functions: write_files
    ---------------------------------------------------------------------
    write_files(cem)
    # --- Save Plots [] ---
    # Key functions: save_plots
    ---------------------------------------------------------------------
    save_plots(cem, "all")
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    # load your sample annotation data
    data(sample_annot)
    head(sample_annot)
    # --- Sample Annotation [] ---
    # Key functions: sample_annotation
    ---------------------------------------------------------------------
    sample_annotation(cem,
                      sample_name_column="SampleName",
                      class_column="Class") <- sample_annot
    # --- Mod Gsea [] ---
    # Key functions: mod_gsea, plot_gsea, show_plot
    ---------------------------------------------------------------------
    # generate heatmap of gene set enrichment analysis
    cem <- mod_gsea(cem)
    cem <- plot_gsea(cem)
    show_plot(cem, "gsea")
    # --- Plot Profile [] ---
    # Key functions: plot_profile, show_plot
    ---------------------------------------------------------------------
    # plot gene expression within each module
    cem <- plot_profile(cem)
    plots <- show_plot(cem, "profile")
    plots[1]
    # --- Mod Ora [] ---
    # Key functions: mod_ora
    ---------------------------------------------------------------------
    # perform over representation analysis
    cem <- mod_ora(cem, gmt_in)
    # --- Plot Ora [] ---
    # Key functions: plot_ora, show_plot
    ---------------------------------------------------------------------
    # plot ora results
    cem <- plot_ora(cem)
    plots <- show_plot(cem, "ora")
    plots[1]
    # --- Interactions Data [] ---
    # Key functions: interactions_data, plot_interactions, show_plot
    ---------------------------------------------------------------------
    # plot interactions
    library(ggplot2)
    interactions_data(cem) <- int_df # add interactions
    cem <- plot_interactions(cem) # generate plot

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cemitool_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cemitool_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cemitool_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CEMITOOL:", paste0("    cemitool: ", packageVersion("CEMiTool"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cemitool_results.csv
    touch ${prefix}_cemitool_output.rds
    echo "BIOC_CEMITOOL:" > versions.yml
    echo "    cemitool: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CEMITOOL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CEMITOOL(ch_input)

    emit:
    results  = BIOC_CEMITOOL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CEMITOOL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CEMITOOL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CEMITOOL.out.versions  // channel: path(versions.yml)
}
