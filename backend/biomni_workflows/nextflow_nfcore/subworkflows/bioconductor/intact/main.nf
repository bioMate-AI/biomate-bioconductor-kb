#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: INTACT
// This package integrates colocalization probabilities from colocalization analysis with transcriptome
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/INTACT/inst/doc/INTACT.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("INTACT")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_INTACT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-intact"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-intact:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-intact:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_intact_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_intact_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_intact_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(INTACT)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: intact
    ---------------------------------------------------------------------
    library(INTACT)
    data(simdat)
    rst <- INTACT::intact(GLCP_vec=simdat$GLCP,
                          z_vec=simdat$TWAS_z)
    # --- Intact [] ---
    # Key functions: intact
    ---------------------------------------------------------------------
    rst1 <- INTACT::intact(GLCP_vec=simdat$GLCP,
                           prior_fun=INTACT::expit,
                           z_vec = simdat$TWAS_z,
                           t = 0.02,D = 0.09)
    # --- Fdr Rst [] ---
    # Key functions: fdr_rst
    ---------------------------------------------------------------------
    fdr_example <- fdr_rst(rst1, alpha = 0.05)
    head(fdr_example)
    # --- Data [] ---
    # Key functions: intactGSE
    ---------------------------------------------------------------------
    data(gene_set_list)
    INTACT::intactGSE(gene_data = simdat,gene_sets = gene_set_list)
    # --- Intactgse [] ---
    # Key functions: intactGSE
    ---------------------------------------------------------------------
    INTACT::intactGSE(gene_data = simdat,prior_fun = INTACT::step,
                      t = 0.45,gene_sets = gene_set_list)
    INTACT::intactGSE(gene_data = simdat,prior_fun = INTACT::expit,
                      t = 0.08,D = 0.08, gene_sets = gene_set_list)
    # --- Data [] ---
    # Key functions: chisq_sumstat
    ---------------------------------------------------------------------
    data(z_sumstats)
    data(exprwt_sumstats)
    data(protwt_sumstats)
    data(ld_sumstats)
    # --- Data [] ---
    # Key functions: multi_intact
    ---------------------------------------------------------------------
    data(multi_simdat)
    rst <- INTACT::multi_intact(df = multi_simdat)
    # --- Multi Intact [] ---
    # Key functions: multi_intact
    ---------------------------------------------------------------------
    rst <- INTACT::multi_intact(df = multi_simdat,return_model_posteriors = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_intact_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_intact_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_intact_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_INTACT:", paste0("    intact: ", packageVersion("INTACT"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_intact_results.csv
    touch ${prefix}_intact_output.rds
    echo "BIOC_INTACT:" > versions.yml
    echo "    intact: 0.0.0" >> versions.yml
    """
}


workflow BIOC_INTACT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_INTACT(ch_input)

    emit:
    results  = BIOC_INTACT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_INTACT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_INTACT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_INTACT.out.versions  // channel: path(versions.yml)
}
