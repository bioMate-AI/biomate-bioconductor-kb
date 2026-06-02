#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: branchpointer
// Predicts branchpoint probability for sites in intronic branchpoint windows. Queries can be supplied 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/branchpointer/inst/doc/branchpointer.R
// Upstream  : biomaRt
// Downstream: none
//
// Install: BiocManager::install("branchpointer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BRANCHPOINTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-branchpointer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-branchpointer:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-branchpointer:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_branchpointer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_branchpointer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_branchpointer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(branchpointer)
    library(jsonlite)

    # --- Connect to BioMart [] ---
    # Key functions: useMart, makeBranchpointWindowForSNP
    library(biomaRt)
    mart <- useMart("ENSEMBL_MART_SNP", dataset="hsapiens_snp",host="www.ensembl.org")
    querySNP <- makeBranchpointWindowForSNP(c("rs587776767","rs786205083"),
    # --- GtfToExons analysis [] ---
    # Key functions: gtfToExons, readQueryFile, makeBranchpointWindowForExons, predictBranchpoints, plotBranchpointWindow, predictionsToSummary
    queryIntronFromGTF <- makeBranchpointWindowForExons("ENSE00000939171.1",
    head(queryIntronFromGTF)
    queryIntronFromGTF <- makeBranchpointWindowForExons(c("ENSE00000939171.1",

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_branchpointer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_branchpointer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_branchpointer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BRANCHPOINTER:", paste0("    branchpointer: ", packageVersion("branchpointer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_branchpointer_results.csv
    touch ${prefix}_branchpointer_output.rds
    echo "BIOC_BRANCHPOINTER:" > versions.yml
    echo "    branchpointer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BRANCHPOINTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BRANCHPOINTER(ch_input)

    emit:
    results  = BIOC_BRANCHPOINTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BRANCHPOINTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BRANCHPOINTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BRANCHPOINTER.out.versions  // channel: path(versions.yml)
}
