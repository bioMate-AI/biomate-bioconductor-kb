#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: EBSEA
// Calculates differential expression of genes based on exon counts of genes obtained from RNA-seq sequ
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/EBSEA/inst/doc/EBSEA.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("EBSEA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EBSEA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ebsea"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ebsea:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ebsea:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ebsea_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ebsea_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ebsea_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(EBSEA)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    library(EBSEA)
    data("exonCounts")
    head(exonCounts)
    # --- Filtercounts [] ---
    # Key functions: filterCounts
    ---------------------------------------------------------------------
    filtCounts <- filterCounts(exonCounts)
    # --- Frame [] ---
    # Key functions: frame, factor, EBSEA
    ---------------------------------------------------------------------
    group <- data.frame('group' = as.factor(c('G1', 'G1', 'G1', 'G2', 'G2', 'G2', 'G2')))
    row.names(group) <- colnames(filtCounts)
    design <- ~group
    ebsea.out <- EBSEA(filtCounts, group, design)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ebsea_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ebsea_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ebsea_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EBSEA:", paste0("    ebsea: ", packageVersion("EBSEA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ebsea_results.csv
    touch ${prefix}_ebsea_output.rds
    echo "BIOC_EBSEA:" > versions.yml
    echo "    ebsea: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EBSEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EBSEA(ch_input)

    emit:
    results  = BIOC_EBSEA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EBSEA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EBSEA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EBSEA.out.versions  // channel: path(versions.yml)
}
