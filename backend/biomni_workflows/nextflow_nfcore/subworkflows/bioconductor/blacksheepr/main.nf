#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: blacksheepr
// Blacksheep is a tool designed for outlier analysis in the context of pairwise comparisons in an effo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/blacksheepr/inst/doc/blacksheepr_vignette.R
// Upstream  : SummarizedExperiment, pasilla
// Downstream: none
//
// Install: BiocManager::install("blacksheepr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BLACKSHEEPR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-blacksheepr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-blacksheepr:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-blacksheepr:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_blacksheepr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_blacksheepr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_blacksheepr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(blacksheepr)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Grouping and Outlier Table Creation [] ---
    # Key functions: comparison_groupings, make_outlier_table
    groupings <- comparison_groupings(comptable)
    reftable_out <- make_outlier_table(
        phosphotable,
        analyze_negative_outliers = FALSE
    )
    outliertab <- reftable_out$outliertab


    # --- Outlier Counting [] ---
    # Key functions: count_outliers
    count_outliers_out <- count_outliers(
        groupings = groupings,
        outliertab = outliertab,
        aggregate_features = TRUE,
        feature_delineator = "-"
    )
    grouptablist <- count_outliers_out$grouptablist
    fractiontab <- count_outliers_out$fractiontab


    # --- Outlier Analysis [] ---
    # Key functions: outlier_analysis
    outlier_analysis_out <- outlier_analysis(
        grouptablist = grouptablist,
        fraction_table = fractiontab,
        fraction_samples_cutoff = 0.3
    )


    # --- Visualisation [] ---
    # Key functions: outlier_heatmap
    hm1 <- outlier_heatmap(
        outlier_analysis_out = outlier_analysis_out,
        counttab = fractiontab,
        metatable = comptable,
        fdrcutoffvalue = 0.1
    )


    # --- High-level DEVA Pipeline [] ---
    # Key functions: deva, deva_results
    deva_out <- deva(
        se = blacksheep_SE,
        analyze_negative_outliers = FALSE,
        aggregate_features = TRUE,
        feature_delineator = "-",
        fraction_samples_cutoff = 0.3,
        fdrcutoffvalue = 0.1
    )
    subanalysis_Her2 <- deva_results(
        deva_out,
        ID = "Her2",
        type = "table"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_blacksheepr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_blacksheepr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_blacksheepr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BLACKSHEEPR:", paste0("    blacksheepr: ", packageVersion("blacksheepr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_blacksheepr_results.csv
    touch ${prefix}_blacksheepr_output.rds
    echo "BIOC_BLACKSHEEPR:" > versions.yml
    echo "    blacksheepr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BLACKSHEEPR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BLACKSHEEPR(ch_input)

    emit:
    results  = BIOC_BLACKSHEEPR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BLACKSHEEPR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BLACKSHEEPR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BLACKSHEEPR.out.versions  // channel: path(versions.yml)
}
