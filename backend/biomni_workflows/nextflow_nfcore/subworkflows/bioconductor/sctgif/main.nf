#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scTGIF — sctgif_analysis
// Perform joint NMF on single-cell RNA-Seq data and gene sets to generate attention maps and functional annotations, followed by an HTML report.
// Input: DistalLungEpithelium, pca.DistalLungEpithelium, msigdbr
// Container: quay.io/biocontainers/bioconductor-sctgif:1.24.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GSEABase, SingleCellExperiment, msigdbr, scTGIF
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and prepare the gene set collection
//  * 2. [Input & Preparation] Create a SingleCellExperiment object with the expression matrix and 2D coordinates
//  * 3. [Core Analysis] Normalize the expression data and register it in the normcounts slot
//  * 4. [Core Analysis] Initialize parameters using settingTGIF
//  * 5. [Core Analysis] Perform joint NMF using calcTGIF
//  * 6. [Visualization & Output] Generate an HTML report using reportTGIF

nextflow.enable.dsl = 2

process BIOC_SCTGIF_SCTGIF_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("scTGIF", "SingleCellExperiment", "GSEABase", "msigdbr")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
    # Load required libraries
    library("scTGIF")
    library("SingleCellExperiment")
    library("GSEABase")
    library("msigdbr")
    
    # Helper function to read input files robustly from the working directory
    read_input <- function(base_name) {
      extensions <- c(".rds", ".csv", ".tsv", ".txt", "")
      for (ext in extensions) {
        file_path <- paste0(base_name, ext)
        if (file.exists(file_path)) {
          if (ext == ".rds" || (ext == "" && grepl("\\\\.rds\$", file_path, ignore.case=TRUE))) {
            return(readRDS(file_path))
          } else if (ext == ".csv" || (ext == "" && grepl("\\\\.csv\$", file_path, ignore.case=TRUE))) {
            return(read.csv(file_path, row.names=1, check.names=FALSE))
          } else if (ext == ".tsv" || ext == ".txt" || (ext == "" && grepl("\\\\.(tsv|txt)\$", file_path, ignore.case=TRUE))) {
            return(read.delim(file_path, row.names=1, check.names=FALSE))
          } else {
            res <- try(readRDS(file_path), silent=TRUE)
            if (!inherits(res, "try-error")) return(res)
            res <- try(read.csv(file_path, row.names=1, check.names=FALSE), silent=TRUE)
            if (!inherits(res, "try-error")) return(res)
          }
        }
      }
      stop(paste("Error: Could not find or read file for", base_name))
    }
    
    # 1. Load and prepare the gene set collection
    m_df <- read_input("msigdbr")
    m_df <- as.data.frame(m_df)
    
    hallmark = unique(m_df\$gs_name)
    gsc <- lapply(hallmark, function(h){
        target = which(m_df\$gs_name == h)
        geneIds = unique(as.character(m_df\$entrez_gene[target]))
        GeneSet(setName=h, geneIds)
    })
    gmt = GeneSetCollection(gsc)
    
    # 2. Create a SingleCellExperiment object with the expression matrix and 2D coordinates
    DistalLungEpithelium <- read_input("DistalLungEpithelium")
    pca.DistalLungEpithelium <- read_input("pca.DistalLungEpithelium")
    
    # Ensure correct matrix formats
    DistalLungEpithelium <- as.matrix(DistalLungEpithelium)
    pca.DistalLungEpithelium <- as.matrix(pca.DistalLungEpithelium)
    
    sce <- SingleCellExperiment(assays = list(counts = DistalLungEpithelium))
    reducedDims(sce) <- SimpleList(PCA=pca.DistalLungEpithelium)
    
    # 3. Normalize the expression data and register it in the normcounts slot
    CPMED <- function(input){
        libsize <- colSums(input)
        median(libsize) * t(t(input) / libsize)
    }
    normcounts(sce) <- log10(CPMED(counts(sce)) + 1)
    
    # 4. Initialize parameters using settingTGIF
    settingTGIF(sce, gmt, reducedDimNames="PCA", assayNames="normcounts")
    
    # 5. Perform joint NMF using calcTGIF
    calcTGIF(sce, ndim=3)
    
    # 6. Generate an HTML report using reportTGIF
    reportTGIF(sce,
        html.open=FALSE,
        title="scTGIF Report for DistalLungEpithelium dataset",
        author="User")
    
    # Save the final SingleCellExperiment object with results
    saveRDS(sce, "scTGIF_output_sce.rds")

    writeLines(c(
        '"BIOC_SCTGIF_SCTGIF_ANALYSIS":',
        paste0('    scTGIF: ', as.character(packageVersion('scTGIF')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sctgif_analysis.csv versions.yml
    """
}

workflow BIOC_SCTGIF_SCTGIF_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ DistalLungEpithelium, pca.DistalLungEpithelium, msigdbr ] ]

    main:
    BIOC_SCTGIF_SCTGIF_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCTGIF_SCTGIF_ANALYSIS.out.tables
    plots    = BIOC_SCTGIF_SCTGIF_ANALYSIS.out.plots
    objects  = BIOC_SCTGIF_SCTGIF_ANALYSIS.out.objects
    versions = BIOC_SCTGIF_SCTGIF_ANALYSIS.out.versions
}
