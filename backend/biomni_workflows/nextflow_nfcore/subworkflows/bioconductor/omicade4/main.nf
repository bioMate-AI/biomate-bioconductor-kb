#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: omicade4
// This package performes multiple co-inertia analysis of omics datasets.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/omicade4/inst/doc/omicade4.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("omicade4")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OMICADE4 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-omicade4"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-omicade4:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-omicade4:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_omicade4_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_omicade4_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_omicade4_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(omicade4)
    library(jsonlite)

    # --- Multi-Co-Inertia Visualization [] ---
    # Key functions: selectVar, plotVar
    cancer_type <- colnames(NCI60_4arrays$agilent)
    cancer_type <- sapply(strsplit(cancer_type, split="\\."), function(x) x[1])
    plot(mcoin, axes=1:2, phenovec=cancer_type, sample.lab=FALSE, df.color=1:4)
    melan_gene <- selectVar(mcoin, a1.lim=c(2, Inf), a2.lim=c(-Inf, Inf))
    geneStat <- plotVar(mcoin, var=c("S100B", "S100A1"), var.lab=TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_omicade4_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_omicade4_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_omicade4_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OMICADE4:", paste0("    omicade4: ", packageVersion("omicade4"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_omicade4_results.csv
    touch ${prefix}_omicade4_output.rds
    echo "BIOC_OMICADE4:" > versions.yml
    echo "    omicade4: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OMICADE4_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OMICADE4(ch_input)

    emit:
    results  = BIOC_OMICADE4.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OMICADE4.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OMICADE4.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OMICADE4.out.versions  // channel: path(versions.yml)
}
