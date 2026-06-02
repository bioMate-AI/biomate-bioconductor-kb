#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Rtpca
// R package for performing thermal proximity co-aggregation analysis with thermal proteome profiling d
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Rtpca/inst/doc/Rtpca.R
// Upstream  : TPP
// Downstream: none
//
// Install: BiocManager::install("Rtpca")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RTPCA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rtpca"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rtpca:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rtpca:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rtpca_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rtpca_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rtpca_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Rtpca)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("hdacTR_smallExample")
    # --- Lapply [] ---
    # Key functions: filter
    ---------------------------------------------------------------------
    hdacTR_data_fil <- lapply(hdacTR_data, function(temp_df){
        filter(temp_df, gene_name %in% random_proteins)
    })
    # --- Tpptrimport [] ---
    # Key functions: tpptrImport
    ---------------------------------------------------------------------
    trData <- tpptrImport(configTable = hdacTR_config, data = hdacTR_data_fil)
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("string_ppi_df")
    string_ppi_df
    # --- Filter [] ---
    # Key functions: filter, runTPCA
    ---------------------------------------------------------------------
    string_ppi_cs_950_df <- string_ppi_df %>%
        filter(combined_score >= 950 )
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("ori_et_al_complexes_df")
    ori_et_al_complexes_df
    # --- Runtpca [] ---
    # Key functions: runTPCA
    ---------------------------------------------------------------------
    # --- Plotppiroc [] ---
    # Key functions: plotPPiRoc
    ---------------------------------------------------------------------
    plotPPiRoc(vehTPCA, computeAUC = TRUE)
    # --- Plotcomplexroc [] ---
    # Key functions: plotComplexRoc
    ---------------------------------------------------------------------
    plotComplexRoc(vehComplexTPCA, computeAUC = TRUE)
    # --- Rundifftpca [] ---
    # Key functions: runDiffTPCA
    ---------------------------------------------------------------------
    diffTPCA <-
    # --- Plotdifftpcavolcano [] ---
    # Key functions: plotDiffTpcaVolcano
    ---------------------------------------------------------------------
    plotDiffTpcaVolcano(
        diffTPCA,
        setXLim = TRUE,
        xlimit = c(-0.5, 0.5))
    # --- Head [] ---
    # Key functions: diffTpcaResultTable, arrange, select
    ---------------------------------------------------------------------
    head(diffTpcaResultTable(diffTPCA) %>%
             arrange(p_value) %>%
            dplyr::select(pair, rssC1_rssC2, f_stat, p_value, p_adj))
    # --- Plotppiprofiles [] ---
    # Key functions: plotPPiProfiles
    ---------------------------------------------------------------------
    plotPPiProfiles(diffTPCA, pair = c("KPNA6", "KPNB1"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rtpca_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rtpca_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rtpca_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RTPCA:", paste0("    rtpca: ", packageVersion("Rtpca"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rtpca_results.csv
    touch ${prefix}_rtpca_output.rds
    echo "BIOC_RTPCA:" > versions.yml
    echo "    rtpca: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RTPCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RTPCA(ch_input)

    emit:
    results  = BIOC_RTPCA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RTPCA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RTPCA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RTPCA.out.versions  // channel: path(versions.yml)
}
