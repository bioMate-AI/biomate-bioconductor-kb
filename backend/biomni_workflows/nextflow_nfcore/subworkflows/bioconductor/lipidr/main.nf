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

    # --- Rowdata [] ---
    # Key functions: rowData, colData
    ---------------------------------------------------------------------
    d_subset = d[1:10, 1:10]
    rowData(d_subset)
    colData(d)
    # --- Rowdata [] ---
    # Key functions: rowData
    ---------------------------------------------------------------------
    lipid_classes = rowData(d)$Class %in% c("Cer", "PC", "LPC")
    groups = d$BileAcid != "DCA"
    d = d[lipid_classes, groups]
    #QC sample subset
    # --- Summarize Transitions [] ---
    # Key functions: summarize_transitions
    ---------------------------------------------------------------------
    d_summarized = summarize_transitions(d, method = "average")
    # --- Mva [] ---
    # Key functions: mva, plot_mva
    ---------------------------------------------------------------------
    mvaresults = mva(d_normalized, method = "OPLS-DA", group_col = "Diet", groups=c("HighFat", "Normal"))
    plot_mva(mvaresults, color_by="group")
    # --- Top Lipids [] ---
    # Key functions: top_lipids
    ---------------------------------------------------------------------
    top_lipids(mvaresults, top.n=10)
    # --- De Analysis [] ---
    # Key functions: de_analysis, significant_molecules
    ---------------------------------------------------------------------
    # --- Lsea [] ---
    # Key functions: lsea, significant_lipidsets
    ---------------------------------------------------------------------
    enrich_results = lsea(de_results, rank.by = "logFC")
    significant_lipidsets(enrich_results)

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
