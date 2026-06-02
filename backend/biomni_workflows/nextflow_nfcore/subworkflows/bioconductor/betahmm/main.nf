#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: betaHMM
// A novel approach utilizing a homogeneous hidden Markov model. And effectively model untransformed be
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/betaHMM/inst/doc/betaHMM.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("betaHMM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BETAHMM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-betahmm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-betahmm:1.2.1--r44_0' :
        'quay.io/biocontainers/bioconductor-betahmm:1.2.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_betahmm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_betahmm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_betahmm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AUC)
    library(jsonlite)

    # --- Estimate Model Parameters [] ---
    # Key functions: betaHMM
    betaHMM_out <- betaHMM(pca_methylation_data,
    treatment_group = c("Benign","Tumour"))
    # --- Extract Model Parameters [] ---
    # Key functions: phi
    A(betaHMM_out)
    phi(betaHMM_out)
    head(hidden_states(betaHMM_out)[["chr 7"]])
    # --- Identify DMCs [] ---
    # Key functions: dmc_identification, assay
    dmc_out <- dmc_identification(betaHMM_out)
    dmc_df <- assay(dmc_out)
    head(dmc_df)
    # --- A U C [] ---
    # Key functions: AUC
    AUC_chr <- AUC(dmc_out)
    plot(betaHMM_out, chromosome = "7", what = "fitted density", AUC = AUC_chr)
    # --- Identify DMRs [] ---
    # Key functions: dmr_identification, assay
    dmr_out <- dmr_identification(dmc_out, parallel_process = FALSE)
    dmr_df <- assay(dmr_out)
    head(dmr_df)
    # --- Identify Thresholds [] ---
    # Key functions: threshold_identification, threshold


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_betahmm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_betahmm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_betahmm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BETAHMM:", paste0("    betahmm: ", packageVersion("betaHMM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_betahmm_results.csv
    touch ${prefix}_betahmm_output.rds
    echo "BIOC_BETAHMM:" > versions.yml
    echo "    betahmm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BETAHMM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BETAHMM(ch_input)

    emit:
    results  = BIOC_BETAHMM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BETAHMM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BETAHMM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BETAHMM.out.versions  // channel: path(versions.yml)
}
