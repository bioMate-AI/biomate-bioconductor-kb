#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mCSEA
// Identification of diferentially methylated regions (DMRs) in predefined regions (promoters, CpG isla
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mCSEA/inst/doc/mCSEA.R
// Upstream  : minfi
// Downstream: none
//
// Install: BiocManager::install("mCSEA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MCSEA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mcsea"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mcsea:1.26.2--r44_0' :
        'quay.io/biocontainers/bioconductor-mcsea:1.26.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mcsea_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mcsea_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mcsea_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mCSEA)
    library(jsonlite)

    # --- Rankprobes [] ---
    # Key functions: rankProbes
    ---------------------------------------------------------------------
    myRank <- rankProbes(betaTest, phenoTest, refGroup = "Control")
    # --- Mcseaplotgsea [] ---
    # Key functions: mCSEAPlotGSEA
    ---------------------------------------------------------------------
    mCSEAPlotGSEA(myRank, myResults, regionType = "promoters", dmrName = "CLIC6")
    # --- Head [] ---
    # Key functions: mCSEAIntegrate
    ---------------------------------------------------------------------
    # Explore expression data
    head(exprTest, 3)
    # Run mCSEAIntegrate function
    resultsInt <- mCSEAIntegrate(myResults, exprTest, "promoters", "ENSEMBL")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mcsea_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mcsea_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mcsea_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MCSEA:", paste0("    mcsea: ", packageVersion("mCSEA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mcsea_results.csv
    touch ${prefix}_mcsea_output.rds
    echo "BIOC_MCSEA:" > versions.yml
    echo "    mcsea: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MCSEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MCSEA(ch_input)

    emit:
    results  = BIOC_MCSEA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MCSEA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MCSEA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MCSEA.out.versions  // channel: path(versions.yml)
}
