#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clusterProfiler — gene_set_enrichment_analysis
// Perform gene set enrichment analysis on a ranked list of genes to identify coordinated pathway changes.
// Input: ranked_gene_list.txt
// Container: quay.io/biocontainers/bioconductor-clusterprofiler:4.18.4--r45hdfd78af_0
// R packages: clusterProfiler, enrichplot, org.Hs.eg.db
// Bioconductor: 3.20 | R: 4.4
// Requires: clusterProfiler, enrichplot, org.Hs.eg.db
// Visualizations: ridge plot, GSEA plot, enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare the ranked gene list
//  * 2. [Core Analysis] Run GSEA using functions like gseGO, gseKEGG, gseMKEGG, gseWP, or GSEA
//  * 3. [Visualization & Output] Visualize enrichment scores and distributions using gseaplot or ridgeplot

nextflow.enable.dsl = 2

process BIOC_CLUSTERPROFILER_GENE_SET_ENRICHMENT_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("clusterProfiler", "enrichplot", "org.Hs.eg.db")
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
        library(clusterProfiler)
        library(org.Hs.eg.db)
        library(enrichplot)
        
        # ==========================================
        # STAGE 1: Prepare the ranked gene list
        # ==========================================
        
        input_file <- "ranked_gene_list.txt"
        if (!file.exists(input_file)) {
          stop("Required input file 'ranked_gene_list.txt' not found in the working directory.")
        }
        
        # Read the ranked gene list robustly
        df <- tryCatch({
          read.table(input_file, header = TRUE, stringsAsFactors = FALSE)
        }, error = function(e) {
          read.table(input_file, header = FALSE, stringsAsFactors = FALSE)
        })
        
        # If the first row was read as header but contains numeric values in column 2, re-read without header
        if (is.character(df[1, 1]) && !is.na(suppressWarnings(as.numeric(df[1, 2]))) && !is.na(suppressWarnings(as.numeric(colnames(df)[2])))) {
          df <- read.table(input_file, header = FALSE, stringsAsFactors = FALSE)
        }
        
        if (ncol(df) < 2) {
          stop("Input file must have at least two columns: Gene ID and Rank Metric.")
        }
        
        # Extract gene list and names
        gene_list <- as.numeric(df[[2]])
        names(gene_list) <- as.character(df[[1]])
        
        # Remove any NA values
        valid_idx <- !is.na(gene_list) & !is.na(names(gene_list)) & names(gene_list) != ""
        gene_list <- gene_list[valid_idx]
        
        # Sort the list in decreasing order (essential for GSEA)
        gene_list <- sort(gene_list, decreasing = TRUE)
        
        # Heuristic to detect keyType (ENTREZID or SYMBOL)
        first_gene <- names(gene_list)[1]
        is_num <- !is.na(suppressWarnings(as.numeric(first_gene)))
        key_type <- if (is_num) "ENTREZID" else "SYMBOL"
        
        # ==========================================
        # STAGE 2: Run GSEA
        # ==========================================
        
        gse <- gseGO(
          geneList      = gene_list,
          OrgDb         = org.Hs.eg.db,
          ont           = "BP",
          keyType       = key_type,
          minGSSize     = 10,
          maxGSSize     = 500,
          pvalueCutoff  = 0.05,
          pAdjustMethod = "BH",
          verbose       = FALSE
        )
        
        # Save the GSEA object and results table
        saveRDS(gse, "gsea_results.rds")
        gse_df <- as.data.frame(gse)
        write.csv(gse_df, "gsea_results.csv", row.names = FALSE)
        
        # ==========================================
        # STAGE 3: Visualize enrichment scores
        # ==========================================
        
        if (nrow(gse_df) > 0) {
          # 1. gseaplot for the top enriched pathway
          pdf("gseaplot.pdf", width = 8, height = 6)
          print(gseaplot(gse, geneSetID = 1))
          dev.off()
        
          # 2. ridgeplot for expression distributions of core enriched genes
          tryCatch({
            pdf("ridgeplot.pdf", width = 10, height = 8)
            print(ridgeplot(gse))
            dev.off()
          }, error = function(e) {
            message("Could not generate ridgeplot: ", e\$message)
          })
        } else {
          message("No significantly enriched pathways found. Output tables are empty, and plots were not generated.")
        }

    writeLines(c(
        '"BIOC_CLUSTERPROFILER_GENE_SET_ENRICHMENT_ANALYSIS":',
        paste0('    clusterProfiler: ', as.character(packageVersion('clusterProfiler')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_set_enrichment_analysis.csv versions.yml
    """
}

workflow BIOC_CLUSTERPROFILER_GENE_SET_ENRICHMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ranked_gene_list.txt ] ]

    main:
    BIOC_CLUSTERPROFILER_GENE_SET_ENRICHMENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CLUSTERPROFILER_GENE_SET_ENRICHMENT_ANALYSIS.out.tables
    plots    = BIOC_CLUSTERPROFILER_GENE_SET_ENRICHMENT_ANALYSIS.out.plots
    objects  = BIOC_CLUSTERPROFILER_GENE_SET_ENRICHMENT_ANALYSIS.out.objects
    versions = BIOC_CLUSTERPROFILER_GENE_SET_ENRICHMENT_ANALYSIS.out.versions
}
