#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rgsepd
// R/GSEPD is a bioinformatics package for R to help disambiguate transcriptome samples (a matrix of RN
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rgsepd/inst/doc/rgsepd.R
// Upstream  : xtable
// Downstream: none
//
// Install: BiocManager::install("rgsepd")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RGSEPD {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rgsepd"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rgsepd:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rgsepd:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rgsepd_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rgsepd_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rgsepd_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GSEPD_Heatmap)
    library(GSEPD_PCA_Plot)
    library(GSEPD_Process)
    library(jsonlite)

    # --- Setup Latex [] ---
    # Key functions: setenv
    Sys.setenv(TEXINPUTS=getwd(),
               BIBINPUTS=getwd(),
               BSTINPUTS=getwd())
    library(xtable)
    # --- Dataload [] ---
    # Key functions: seed, data
    library(rgsepd)
    set.seed(1000) #fixed randomness
    data("IlluminaBodymap" , package="rgsepd")
    data("IlluminaBodymapMeta" , package="rgsepd")
    # --- xtable [] ---
    # Key functions: xtable
    xT<-xtable(T1, caption ="First few rows of the included IlluminaBodymap dataset. See \\texttt{?IlluminaBodymap} for more details.", label = 'MyT1')
    print.xtable(xT, scalebox=0.75)
    xtable(T2, caption ="First few rows of the included IlluminaBodymapMeta dataset. See \\texttt{?IlluminaBodymapMeta} for more details. These are easy to build with a spreadsheet, saved to csv and R's builtin \\texttt{?read.csv}", label = 'MyT2')
    # --- Gsepd Process [] ---
    # Key functions: GSEPD_Process
    G <- GSEPD_Process( G )
    # --- Gsepd Heatmap   Pca [] ---
    # Key functions: GSEPD_Heatmap, GSEPD_PCA_Plot
    print(isoform_ids)
      GSEPD_Heatmap(G,isoform_ids)
      GSEPD_PCA_Plot(G)
    # --- Myt3 [] ---
    # Key functions: csv
    Annotated_Filtered <- read.csv("OUT/DESEQ.RES.Ax4.Bx8.Annote_Filter.csv",
                          header=TRUE,as.is=TRUE)
    # --- xtable [] ---
    # Key functions: xtable
    xT<-xtable(head(Annotated_Filtered, n=10L),
               caption ="First few rows of OUT/DESEQ.RES.Ax4.Bx8.Annote\\_Filter.csv which contains the DESeq results, cropped for significant results, and annotated with gene names (the HGNC Symbol).", label = 'Table_Annote')
    print(xT, scalebox=0.70, include.rownames=FALSE)
    # --- csv [] ---
    # Key functions: csv, xtable
    Merge_File <- read.csv("OUT/GSEPD.RES.Ax4.Bx8.MERGE.csv",
                          header=TRUE,as.is=TRUE, nrows=20)
    xT<-xtable(head(Merge_File, n=15L),
               caption ="First few rows of OUT/GSEPD.RES.Ax4.Bx8.MERGE.csv showing enriched GO Terms, and each terms' underlying gene expression averages per group. This data is central to the rgsepd package, defining the group centroids per GO-Term. It consists of the cross-product of the GO enrichment statistics and the DESeq differential expression and summarization. ", label = 'MyT5')
    print(xT, scalebox=0.50, include.rownames=FALSE)
    # --- Alphabetatables [] ---
    # Key functions: csv, xtable, divergence
    Alpha_File <- read.csv("OUT/GSEPD.Alpha.Ax4.Bx8.csv",
                          header=TRUE,as.is=TRUE, nrows=20, row.names=1)
    xT<-xtable(head(Alpha_File, n=10L)[,c(1,2,3,4,5,9,13)],
               caption ="First ten rows of OUT/GSEPD.Alpha.Ax4.Bx8.csv showing the group projection scores for each sample, these directly correspond to the colors in the HMA file. Where the HMA displays only significant sets, the Alpha table continues for all tested GO Terms. Both the Alpha table and Beta table are summarized in Figure \\ref{fig:HMA}.", label = 'TableAlpha')
    print(xT, scalebox=0.80, include.rownames=TRUE)
    # --- Findfiles [] ---
    # Key functions: files
    HM_File <- list.files("OUT",pattern="HM.A")
    PScatter_File <- list.files("OUT//SCGO",pattern="Scatter.Ax")[1]
    PGSEPD_File <- list.files("OUT//SCGO",pattern="GSEPD.Ax")[1]
    PPairs_File <- list.files("OUT//SCGO",pattern="Pairs.Ax")[1]
    #trim the .PDF

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rgsepd_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rgsepd_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rgsepd_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RGSEPD:", paste0("    rgsepd: ", packageVersion("rgsepd"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rgsepd_results.csv
    touch ${prefix}_rgsepd_output.rds
    echo "BIOC_RGSEPD:" > versions.yml
    echo "    rgsepd: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RGSEPD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RGSEPD(ch_input)

    emit:
    results  = BIOC_RGSEPD.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RGSEPD.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RGSEPD.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RGSEPD.out.versions  // channel: path(versions.yml)
}
