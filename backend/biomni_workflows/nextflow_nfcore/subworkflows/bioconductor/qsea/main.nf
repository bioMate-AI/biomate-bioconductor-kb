#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: qsea
// qsea (quantitative sequencing enrichment analysis) was developed as the successor of the MEDIPS pack
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/qsea/inst/doc/qsea_tutorial.R
// Upstream  : BSgenome, BiocParallel, GenomicRanges
// Downstream: none
//
// Install: BiocManager::install("qsea")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QSEA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-qsea"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-qsea:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-qsea:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_qsea_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_qsea_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_qsea_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(qsea)
    library(jsonlite)

    # --- addEnrichmentParameters blind [] ---
    # Key functions: getRegions
    wd=which(getRegions(qseaSet)$CpG_density>1 &
    getRegions(qseaSet)$CpG_density<15)
    signal=(15-getRegions(qseaSet)$CpG_density[wd])*.55/15+.25
    # --- get Offset [] ---
    # Key functions: getOffset
    getOffset(qseaSet, scale="fraction")
    # --- plot E Pmatrix [] ---
    # Key functions: plotEPmatrix
    plotEPmatrix(qseaSet)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_qsea_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_qsea_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_qsea_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QSEA:", paste0("    qsea: ", packageVersion("qsea"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qsea_results.csv
    touch ${prefix}_qsea_output.rds
    echo "BIOC_QSEA:" > versions.yml
    echo "    qsea: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QSEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_QSEA(ch_input)

    emit:
    results  = BIOC_QSEA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QSEA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QSEA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QSEA.out.versions  // channel: path(versions.yml)
}
