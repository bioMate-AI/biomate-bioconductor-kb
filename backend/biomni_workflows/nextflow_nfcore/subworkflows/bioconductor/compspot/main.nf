#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: compSPOT
// Clonal cell groups share common mutations within cancer, precancer, and even clinically normal appea
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/compSPOT/inst/doc/compSPOT-vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("compSPOT")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COMPSPOT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-compspot"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-compspot:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-compspot:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_compspot_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_compspot_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_compspot_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(compSPOT)
    library(jsonlite)

    # --- Group Comparison [] ---
    # Key functions: compare_groups
    hotspots <- subset(significant_spots[[1]], type == "Hotspot")
    group_comp <- compare_groups(
        data = compSPOT_example_mutations,
        regions = hotspots,
        pval = 0.05,
        threshold = 0.2,
        name1 = "High-Risk",
        name2 = "Low-Risk",
        include_genes = TRUE
    )
    group_results <- group_comp[[1]]


    # --- Feature Association [] ---
    # Key functions: compare_features
    features <- c("AGE", "SEX", "SMOKING_HISTORY", "TUMOR_VOLUME", "KI_67")
    feature_example <- compare_features(
        data = compSPOT_example_mutations,
        regions = compSPOT_example_regions,
        feature = features
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_compspot_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_compspot_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_compspot_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COMPSPOT:", paste0("    compspot: ", packageVersion("compSPOT"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_compspot_results.csv
    touch ${prefix}_compspot_output.rds
    echo "BIOC_COMPSPOT:" > versions.yml
    echo "    compspot: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COMPSPOT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_COMPSPOT(ch_input)

    emit:
    results  = BIOC_COMPSPOT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COMPSPOT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COMPSPOT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COMPSPOT.out.versions  // channel: path(versions.yml)
}
