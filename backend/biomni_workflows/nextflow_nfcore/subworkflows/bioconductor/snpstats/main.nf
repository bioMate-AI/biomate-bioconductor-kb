#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: snpStats
// Classes and statistical methods for large SNP association studies. This extends the earlier snpMatri
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/snpStats/inst/doc/Fst-vignette.R
// Upstream  : hexbin
// Downstream: MAGAR
//
// Install: BiocManager::install("snpStats")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SNPSTATS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-snpstats"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-snpstats:1.56.0--r44_0' :
        'quay.io/biocontainers/bioconductor-snpstats:1.56.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_snpstats_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_snpstats_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_snpstats_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Fst)
    library(jsonlite)

    # --- Pairwise [] ---
    # Key functions: Fst
    data(for.exercise)
    f1 <- Fst(snps.10, subject.support$stratum, pairwise=TRUE)
    weighted.mean(f1$Fst, f1$weight)
    # --- Aov [] ---
    # Key functions: Fst
    f2 <- Fst(snps.10, subject.support$stratum, pairwise=FALSE)
    weighted.mean(f2$Fst, f2$weight)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_snpstats_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_snpstats_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_snpstats_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SNPSTATS:", paste0("    snpstats: ", packageVersion("snpStats"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_snpstats_results.csv
    touch ${prefix}_snpstats_output.rds
    echo "BIOC_SNPSTATS:" > versions.yml
    echo "    snpstats: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SNPSTATS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SNPSTATS(ch_input)

    emit:
    results  = BIOC_SNPSTATS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SNPSTATS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SNPSTATS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SNPSTATS.out.versions  // channel: path(versions.yml)
}
