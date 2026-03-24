#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SurfR
// Identify Surface Protein coding genes from a list of candidates. Systematically download data from G
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SurfR/inst/doc/Intro_to_SurfR.R
// Upstream  : SPsimSeq, ggplot2, stringr
// Downstream: none
//
// Install: BiocManager::install("SurfR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SURFR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-surfr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-surfr:1.2.7--r44_0' :
        'quay.io/biocontainers/bioconductor-surfr:1.2.7--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_surfr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_surfr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_surfr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Annotate_SPID)
    library(DGE)
    library(DownloadArchS4)
    library(Enrichment)
    library(GEOmetadata)
    library(Gene2SProtein)
    library(jsonlite)

    # --- Identify Surface Proteins [] ---
    # Key functions: Gene2SProtein
    library(SurfR)
    GeneNames <- c("CIITA", "EPCAM", "CD24", "CDCP1", "LYVE1")
    SurfaceProteins_df <- Gene2SProtein(GeneNames,
    # --- Perform Differential Expression [] ---
    # Key functions: DGE
    library(SurfR)
    df_zhang <- DGE(expression = countMatrix,
    head(df_zhang)
    # --- Identify Surface Proteins [] ---
    # Key functions: Gene2SProtein
    df_zhang <- df_zhang[!is.na(df_zhang$padj), ]
    SP <- Gene2SProtein(genes = fdr_GeneID, input_type = "gene_name")
    SPup <- Gene2SProtein(genes = fdrUP_GeneID, input_type = "gene_name")
    # --- Download GEO Data [] ---
    # Key functions: GEOmetadata, str_split, DownloadArchS4
    library(SurfR)
    library(stringr)
    mGSE121810 <- GEOmetadata(GSE = "GSE121810")
    # --- Perform Differential Expression [] ---
    # Key functions: DGE
    df_GEO <- DGE(expression = cGSE121810,
    df_GEO <- df_GEO[!is.na(df_GEO$padj), ]
    head(df_GEO)
    # --- Identify Surface Proteins [] ---
    # Key functions: Gene2SProtein
    SP <- Gene2SProtein(genes = fdr_GeneID, input_type = "gene_name")
    SPup <- Gene2SProtein(genes = fdrUP_GeneID, input_type = "gene_name")
    SPdw <- Gene2SProtein(genes = fdrDW_GeneID, input_type = "gene_name")
    # --- Perform Differential Expression [] ---
    # Key functions: DGE
    df_TCGA <- DGE(expression = cTCGA.THYM,
    head(df_TCGA)
    # --- Identify Surface Proteins [] ---
    # Key functions: Gene2SProtein
    df_TCGA <- df_TCGA[!is.na(df_TCGA$padj), ]
    SP <- Gene2SProtein(genes = fdr_GeneID, input_type = "gene_name")
    SPup <- Gene2SProtein(genes = fdrUP_GeneID, input_type = "gene_name")
    # --- Download GEO Metadata [] ---
    # Key functions: GEOmetadata
    mGSE58135 <- GEOmetadata("GSE58135")
    mGSE58135$condition[mGSE58135$tissue %in% c("ER+ Breast Cancer Primary Tumor",
    TP_samples <- c("GSM1401694", "GSM1401717", "GSM1401729")
    # --- Download GEO Counts [] ---
    # Key functions: DownloadArchS4
    cGSE58135 <- DownloadArchS4(mGSE58135$GSM, species = "human")
    cGSE58135 <- cGSE58135[, row.names(mGSE58135)]
    table(mGSE58135$condition)
    # --- Perform Meta-analysis [] ---
    # Key functions: metaRNAseq
    L_fishercomb <- metaRNAseq(ind_deg = list(TCGA.BRCA =  df.TCGA, GEO.GSE58135 = df.GSE58135),
    # --- Perform Meta-analysis [] ---
    # Key functions: metaRNAseq
    L_invnorm <- metaRNAseq(ind_deg = list(TCGA.BRCA =  df.TCGA, GEO.GSE58135 = df.GSE58135),
    nrep = c(102, 56))
    # --- Combine Meta-analysis Results [] ---
    # Key functions: combine_fisher_invnorm, Gene2SProtein
    metacomb <- combine_fisher_invnorm(ind_deg = list(TCGA.BRCA =  df.TCGA,
    SP <- Gene2SProtein(genes = metacomb_GeneID, input_type = "gene_name")
    # --- Identify Upregulated Surface Proteins [] ---
    # Key functions: Gene2SProtein
    SPup <- Gene2SProtein(genes = metacombUP_GeneID, input_type = "gene_name")
    # --- Identify Downregulated Surface Proteins [] ---
    # Key functions: Gene2SProtein
    SPdw <- Gene2SProtein(genes = metacombDW_GeneID, input_type = "gene_name")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_surfr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_surfr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_surfr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SURFR:", paste0("    surfr: ", packageVersion("SurfR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_surfr_results.csv
    touch ${prefix}_surfr_output.rds
    echo "BIOC_SURFR:" > versions.yml
    echo "    surfr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SURFR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SURFR(ch_input)

    emit:
    results  = BIOC_SURFR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SURFR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SURFR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SURFR.out.versions  // channel: path(versions.yml)
}
