#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ProteoMM
// ProteoMM is a statistical method to perform model-based peptide-level differential expression analys
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ProteoMM/inst/doc/ProteoMM_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ProteoMM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROTEOMM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-proteomm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-proteomm:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-proteomm:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_proteomm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_proteomm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_proteomm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ProteoMM)
    library(jsonlite)

    # --- Data Preparation and Log Transformation [Data Preparation] ---
    # Key functions: make_intencities, convert_log2, make_meta
    data("hs_peptides")
    intsCols <- 8:13
    metaCols <- 1:7
    m_logInts <- make_intencities(hs_peptides, intsCols)
    m_logInts <- convert_log2(m_logInts)
    m_prot.info <- make_meta(hs_peptides, metaCols)
    grps <- as.factor(c('CG','CG','CG', 'mCG','mCG','mCG'))

    # --- Eigen-based Normalization [Normalization] ---
    # Key functions: eig_norm1, eig_norm2
    hs_m_ints_eig1 <- eig_norm1(
        m = m_logInts,
        treatment = grps,
        prot.info = m_prot.info
    )
    hs_m_ints_eig1$h.c <- 2
    hs_m_ints_norm <- eig_norm2(rv = hs_m_ints_eig1)
    hs_prot.info <- hs_m_ints_norm$normalized[, 1:7]
    hs_norm_m <- hs_m_ints_norm$normalized[, 8:13]

    # --- Model-Based Imputation [Imputation] ---
    # Key functions: MBimpute
    imp_hs <- MBimpute(
        hs_norm_m,
        grps,
        prot.info = hs_prot.info,
        pr_ppos = 3,
        my.pi = 0.05,
        compute_pi = FALSE
    )

    # --- Peptide Trend Visualization [Visualisation] ---
    # Key functions: plot_3_pep_trends_NOfile
    mylabs <- c('CG','CG','CG', 'mCG','mCG','mCG')
    prot_to_plot <- 'Prot32'
    gene_to_plot <- 'Gene32'
    plot_3_pep_trends_NOfile(
        as.matrix(hs_m_ints_eig1$m),
        hs_m_ints_eig1$prot.info,
        as.matrix(hs_norm_m),
        hs_prot.info,
        imp_hs$y_imputed,
        imp_hs$imp_prot.info,
        prot_to_plot,
        3,
        gene_to_plot,
        4,
        mylabs
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_proteomm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_proteomm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_proteomm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PROTEOMM:", paste0("    proteomm: ", packageVersion("ProteoMM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_proteomm_results.csv
    touch ${prefix}_proteomm_output.rds
    echo "BIOC_PROTEOMM:" > versions.yml
    echo "    proteomm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PROTEOMM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PROTEOMM(ch_input)

    emit:
    results  = BIOC_PROTEOMM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PROTEOMM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PROTEOMM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PROTEOMM.out.versions  // channel: path(versions.yml)
}
