#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pcaExplorer — interactive_pca_exploration
// Launch the interactive Shiny application for comprehensive RNA-seq exploration using pre-computed DESeq2 objects and gene annotations.
// Input: count_matrix.txt, metadata.txt
// Container: quay.io/biocontainers/bioconductor-pcaexplorer:3.4.0--r45hdfd78af_0
// R packages: airway, DESeq2, devtools, org.Hs.eg.db, pcaExplorer, topGO
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, org.Hs.eg.db, pcaExplorer
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Retrieve gene annotations using get_annotation_orgdb
//  * 2. [Core Analysis] Pre-compute functional enrichment of PC loadings using pca2go
//  * 3. [Core Analysis] Launch the interactive Shiny app using pcaExplorer

nextflow.enable.dsl = 2

process BIOC_PCAEXPLORER_INTERACTIVE_PCA_EXPLORATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("airway", "DESeq2", "devtools", "org.Hs.eg.db", "pcaExplorer", "topGO")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(DESeq2)
    library(pcaExplorer)
    library(org.Hs.eg.db)
    
    # 1. Read user input files from the working directory
    if (!file.exists("count_matrix.txt") || !file.exists("metadata.txt")) {
      stop("Required input files 'count_matrix.txt' and/or 'metadata.txt' are missing in the working directory.")
    }
    
    counts <- read.table("count_matrix.txt", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
    metadata <- read.table("metadata.txt", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
    
    # Align samples between count matrix and metadata
    common_samples <- intersect(colnames(counts), rownames(metadata))
    if (length(common_samples) == 0) {
      stop("No matching sample names found between count_matrix.txt columns and metadata.txt row names.")
    }
    counts <- counts[, common_samples, drop = FALSE]
    metadata <- metadata[common_samples, , drop = FALSE]
    
    # Construct DESeq2 objects
    dds_airway <- DESeqDataSetFromMatrix(countData = counts, colData = metadata, design = ~ 1)
    rld_airway <- rlogTransformation(dds_airway)
    
    # 2. Retrieve gene annotations using get_annotation_orgdb
    anno_df_orgdb <- get_annotation_orgdb(dds = dds_airway, orgdb_species = "org.Hs.eg.db", idtype = "ENSEMBL")
    annotation_airway <- anno_df_orgdb
    
    # Define background genes for enrichment analysis
    bg_ids <- rownames(dds_airway)[rowSums(counts(dds_airway)) > 0]
    
    # 3. Pre-compute functional enrichment of PC loadings using pca2go
    pca2go_airway <- pca2go(rld_airway, annotation = annotation_airway, organism = "Hs", ensToGeneSymbol = TRUE, background_genes = bg_ids)
    
    # Write meaningful results to the working directory
    write.csv(as.data.frame(annotation_airway), "annotation_airway.csv", row.names = TRUE)
    saveRDS(pca2go_airway, "pca2go_airway.rds")
    saveRDS(rld_airway, "rld_airway.rds")
    saveRDS(dds_airway, "dds_airway.rds")
    
    # 4. Launch the interactive Shiny app using pcaExplorer
    if (interactive()) {
      pcaExplorer(dds_airway, rld_airway, pca2go = pca2go_airway, annotation = annotation_airway)
    } else {
      message("Pipeline completed successfully. Outputs saved to the working directory:")
      message("- annotation_airway.csv")
      message("- pca2go_airway.rds")
      message("- rld_airway.rds")
      message("- dds_airway.rds")
      message("To launch the interactive app, run this script in an interactive R session.")
    }

    writeLines(c(
        '"BIOC_PCAEXPLORER_INTERACTIVE_PCA_EXPLORATION":',
        paste0('    pcaExplorer: ', as.character(packageVersion('pcaExplorer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interactive_pca_exploration.csv versions.yml
    """
}

workflow BIOC_PCAEXPLORER_INTERACTIVE_PCA_EXPLORATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ count_matrix.txt, metadata.txt ] ]

    main:
    BIOC_PCAEXPLORER_INTERACTIVE_PCA_EXPLORATION(ch_input)

    emit:
    tables   = BIOC_PCAEXPLORER_INTERACTIVE_PCA_EXPLORATION.out.tables
    plots    = BIOC_PCAEXPLORER_INTERACTIVE_PCA_EXPLORATION.out.plots
    objects  = BIOC_PCAEXPLORER_INTERACTIVE_PCA_EXPLORATION.out.objects
    versions = BIOC_PCAEXPLORER_INTERACTIVE_PCA_EXPLORATION.out.versions
}
