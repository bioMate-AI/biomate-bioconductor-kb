#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: goseq — custom_category_analysis
// Perform enrichment analysis using custom gene-to-category mappings (like KEGG pathways) or non-native organisms.
// Input: genes, org.Hs.egENSEMBL2EG, org.Hs.egPATH
// Container: quay.io/biocontainers/bioconductor-goseq:1.62.0--r45hdfd78af_0
// R packages: AnnotationDbi, goseq
// Bioconductor: 3.20 | R: 4.4
// Requires: AnnotationDbi, goseq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct custom gene-to-category mapping list
//  * 2. [Core Analysis] Fit the PWF using nullp
//  * 3. [Core Analysis] Run enrichment analysis using goseq with the gene2cat argument

nextflow.enable.dsl = 2

process BIOC_GOSEQ_CUSTOM_CATEGORY_ANALYSIS {
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
    .bm_deps <- c("AnnotationDbi", "goseq")
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
    library(goseq)
    library(AnnotationDbi)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Read 'genes' (named binary vector of assayed genes and DE status)
    if (file.exists("genes.rds")) {
      genes <- readRDS("genes.rds")
    } else if (file.exists("genes.txt")) {
      df_genes <- read.table("genes.txt", header = TRUE, stringsAsFactors = FALSE)
      genes <- as.integer(df_genes[[2]])
      names(genes) <- df_genes[[1]]
    } else if (file.exists("genes.csv")) {
      df_genes <- read.csv("genes.csv", header = TRUE, stringsAsFactors = FALSE)
      genes <- as.integer(df_genes[[2]])
      names(genes) <- df_genes[[1]]
    } else {
      stop("Error: Required input file 'genes' (as genes.rds, genes.txt, or genes.csv) not found in the working directory.")
    }
    
    # Read 'org.Hs.egENSEMBL2EG' mapping object
    if (file.exists("org.Hs.egENSEMBL2EG.rds")) {
      org.Hs.egENSEMBL2EG <- readRDS("org.Hs.egENSEMBL2EG.rds")
    } else {
      stop("Error: Required input file 'org.Hs.egENSEMBL2EG.rds' not found in the working directory.")
    }
    
    # Read 'org.Hs.egPATH' mapping object
    if (file.exists("org.Hs.egPATH.rds")) {
      org.Hs.egPATH <- readRDS("org.Hs.egPATH.rds")
    } else {
      stop("Error: Required input file 'org.Hs.egPATH.rds' not found in the working directory.")
    }
    
    # ==========================================
    # 2. Execute Documented Workflow
    # ==========================================
    
    # Construct custom gene-to-category mapping list
    en2eg <- as.list(org.Hs.egENSEMBL2EG)
    eg2kegg <- as.list(org.Hs.egPATH)
    grepKEGG <- function(id, mapkeys) {
      unique(unlist(mapkeys[id], use.names = FALSE))
    }
    kegg <- lapply(en2eg, grepKEGG, eg2kegg)
    
    # Fit the PWF using nullp (capturing the plot to a PDF file)
    pdf("pwf_plot.pdf", width = 7, height = 7)
    pwf <- nullp(genes, "hg19", "ensGene")
    dev.off()
    
    # Run enrichment analysis using goseq with the gene2cat argument
    KEGG <- goseq(pwf, gene2cat = kegg)
    
    # ==========================================
    # 3. Save Outputs
    # ==========================================
    
    # Save the PWF object
    saveRDS(pwf, "pwf.rds")
    
    # Save the KEGG enrichment results as RDS and CSV
    saveRDS(KEGG, "kegg_enrichment.rds")
    write.csv(KEGG, "kegg_enrichment.csv", row.names = FALSE)
    
    cat("Pipeline completed successfully. Outputs written:\n")
    cat("- pwf_plot.pdf (PWF plot)\n")
    cat("- pwf.rds (PWF R object)\n")
    cat("- kegg_enrichment.rds (KEGG enrichment R object)\n")
    cat("- kegg_enrichment.csv (KEGG enrichment table)\n")

    writeLines(c(
        '"BIOC_GOSEQ_CUSTOM_CATEGORY_ANALYSIS":',
        paste0('    goseq: ', as.character(packageVersion('goseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_category_analysis.csv versions.yml
    """
}

workflow BIOC_GOSEQ_CUSTOM_CATEGORY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genes, org.Hs.egENSEMBL2EG, org.Hs.egPATH ] ]

    main:
    BIOC_GOSEQ_CUSTOM_CATEGORY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GOSEQ_CUSTOM_CATEGORY_ANALYSIS.out.tables
    plots    = BIOC_GOSEQ_CUSTOM_CATEGORY_ANALYSIS.out.plots
    objects  = BIOC_GOSEQ_CUSTOM_CATEGORY_ANALYSIS.out.objects
    versions = BIOC_GOSEQ_CUSTOM_CATEGORY_ANALYSIS.out.versions
}
