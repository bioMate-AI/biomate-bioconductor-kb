#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pathwayPCA
// pathwayPCA is an integrative analysis tool that implements the principal component analysis (PCA) ba
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pathwayPCA/inst/doc/Introduction_to_pathwayPCA.R
// Upstream  : SummarizedExperiment, XML, parallel, rWikiPathways, survival
// Downstream: none
//
// Install: BiocManager::install("pathwayPCA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PATHWAYPCA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pathwaypca"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pathwaypca:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pathwaypca:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pathwaypca_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pathwaypca_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pathwaypca_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AESPCA_pVals)
    library(CreateOmics)
    library(SubsetPathwayData)
    library(Surv)
    library(jsonlite)

    # --- Data import and preprocessing [] ---
    # Key functions: url
    ovCNV_aespcOut <- readRDS(
    url(paste0(gitHubPath_char, "ovarian_copyNum_aespcOut.RDS"))
    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, theme_bw, aes, geom_col, geom_text, labs, theme_classic, geom_histogram
    ggplot(wp195gather_df, aes(x = protein, y = sampleID)) +
    geom_tile(aes(fill = value)) +
    scale_fill_gradient2(low = "red", mid = "black", high = "green") +
    # --- DownloadPathwayArchive analysis [] ---
    # Key functions: downloadPathwayArchive, read_gmt, CreateOmics, AESPCA_pVals, getPathpVals, getPathPCLs, arrange, SubsetPathwayData
    kidneyWP1559_df <- bind_cols(
    getPathPCLs(kidney_aespcOut, "WP1559")$PCs %>% select(PC1 = V1)
    mutate(direction = ifelse(PC1 > median(PC1), "High", "Low")) %>%

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pathwaypca_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pathwaypca_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pathwaypca_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PATHWAYPCA:", paste0("    pathwaypca: ", packageVersion("pathwayPCA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathwaypca_results.csv
    touch ${prefix}_pathwaypca_output.rds
    echo "BIOC_PATHWAYPCA:" > versions.yml
    echo "    pathwaypca: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PATHWAYPCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PATHWAYPCA(ch_input)

    emit:
    results  = BIOC_PATHWAYPCA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PATHWAYPCA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PATHWAYPCA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PATHWAYPCA.out.versions  // channel: path(versions.yml)
}
