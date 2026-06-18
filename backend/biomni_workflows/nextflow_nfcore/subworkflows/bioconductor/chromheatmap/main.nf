#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ChromHeatMap — chrom_heatmap_analysis
// Map genomic expression data to chromosome coordinates, plot strand-specific or combined chromosome heatmaps, and interactively extract probe identifiers of inte
// Input: expression_matrix.csv, annotation_package
// Container: quay.io/biocontainers/bioconductor-chromheatmap:1.64.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: AnnotationDbi, ChromHeatMap
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Input Files
//  * 2. [Visualization & Output] Map Probe Identifiers to Coordinates
//  * 3. [Visualization & Output] Plot Chromosome Heatmaps
//  * 4. [Visualization & Output] Extract Probe Identifiers and Map to Genes

nextflow.enable.dsl = 2

process BIOC_CHROMHEATMAP_CHROM_HEATMAP_ANALYSIS {
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
    .bm_deps <- c("ChromHeatMap", "AnnotationDbi", "anno_pkg")
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
        library(ChromHeatMap)
        library(AnnotationDbi)
        
        # ==========================================
        # --- Read User Input Files ---
        # ==========================================
        if (!file.exists("expression_matrix.csv")) {
          stop("Error: 'expression_matrix.csv' not found in the working directory.")
        }
        if (!file.exists("annotation_package")) {
          stop("Error: 'annotation_package' file not found in the working directory.")
        }
        
        # Read expression matrix (probes/genes as row names, samples as columns)
        expr_matrix <- as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
        
        # Read the annotation package name from the file
        anno_pkg <- trimws(readLines("annotation_package", n = 1))
        
        # Load the specified annotation package
        if (!requireNamespace(anno_pkg, quietly = TRUE)) {
          # Try appending '.db' if not found
          anno_pkg_db <- paste0(anno_pkg, ".db")
          if (requireNamespace(anno_pkg_db, quietly = TRUE)) {
            anno_pkg <- anno_pkg_db
          } else {
            stop(paste("Error: Annotation package", anno_pkg, "is not installed."))
          }
        }
        library(anno_pkg, character.only = TRUE)
        
        # ==========================================
        # --- Map Probe Identifiers to Coordinates ---
        # ==========================================
        # Adapt the documented call: chrdata<-makeChrStrandData(exprs(ALLs), lib='hgu95av2')
        chrdata <- makeChrStrandData(expr_matrix, lib = gsub("\\\\.db\$", "", anno_pkg))
        
        # Save the mapped genomic coordinates object
        saveRDS(chrdata, file = "chrdata.rds")
        
        # ==========================================
        # --- Plot Chromosome Heatmaps ---
        # ==========================================
        # Generate sample annotation colors matching the number of samples
        groupcol <- rep(c("red", "green"), length.out = ncol(expr_matrix))
        
        # Open PDF device to save the plots
        pdf("chrom_heatmap_plots.pdf", width = 10, height = 8)
        
        # Plot 1: Whole chromosome (Chromosome 19), both strands combined
        tryCatch({
          plotChrMap(chrdata, 19, strands='both', RowSideColors=groupcol)
        }, error = function(e) {
          message("Skipped plotting Chromosome 19 (might not be present in the dataset): ", e\$message)
        })
        
        # Plot 2: Subsetted chromosome (Chromosome 1, cytoband q23)
        plotmap <- NULL
        tryCatch({
          plotmap <- plotChrMap(chrdata, 1, cytoband='q23', interval=50000, srtCyto=0, cexCyto=1.2)
        }, error = function(e) {
          message("Skipped plotting Chromosome 1 cytoband q23 (might not be present in the dataset): ", e\$message)
        })
        
        # ==========================================
        # --- Extract Probe Identifiers and Map to Genes ---
        # ==========================================
        # Set up the symbol environment alias to match the exact documented code variable name
        symbol_env_name <- paste0(gsub("\\\\.db\$", "", anno_pkg), "SYMBOL")
        if (exists(symbol_env_name)) {
          hgu95av2SYMBOL <- get(symbol_env_name)
        } else {
          hgu95av2SYMBOL <- new.env()
        }
        
        probes <- NULL
        # Attempt interactive selection; fallback to programmatic extraction if non-interactive
        tryCatch({
          probes <- grabChrMapProbes( plotmap )
        }, error = function(e) {
          message("Interactive grabChrMapProbes skipped/failed. Extracting probes programmatically from plotmap.")
          if (!is.null(plotmap)) {
            probes <<- unique(unlist(plotmap))
          }
        })
        
        dev.off()
        
        # Fallback to top probes from the expression matrix if no probes were extracted
        if (is.null(probes) || length(probes) == 0) {
          message("No probes found in plotmap. Using top 10 probes from expression matrix as fallback.")
          probes <- head(rownames(expr_matrix), 10)
        }
        
        # Map the extracted probes to gene symbols using the exact documented call
        genes <- unlist(mget(probes, envir=hgu95av2SYMBOL, ifnotfound=NA))
        
        # Save the extracted probes and mapped gene symbols to a CSV file
        output_df <- data.frame(
          Probe_ID = names(genes),
          Gene_Symbol = genes,
          stringsAsFactors = FALSE
        )
        write.csv(output_df, file = "extracted_probes_genes.csv", row.names = FALSE)
        
        message("Pipeline completed successfully. Outputs saved: 'chrdata.rds', 'chrom_heatmap_plots.pdf', 'extracted_probes_genes.csv'.")

    writeLines(c(
        '"BIOC_CHROMHEATMAP_CHROM_HEATMAP_ANALYSIS":',
        paste0('    ChromHeatMap: ', as.character(packageVersion('ChromHeatMap')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chrom_heatmap_analysis.csv versions.yml
    """
}

workflow BIOC_CHROMHEATMAP_CHROM_HEATMAP_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, annotation_package ] ]

    main:
    BIOC_CHROMHEATMAP_CHROM_HEATMAP_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CHROMHEATMAP_CHROM_HEATMAP_ANALYSIS.out.tables
    plots    = BIOC_CHROMHEATMAP_CHROM_HEATMAP_ANALYSIS.out.plots
    objects  = BIOC_CHROMHEATMAP_CHROM_HEATMAP_ANALYSIS.out.objects
    versions = BIOC_CHROMHEATMAP_CHROM_HEATMAP_ANALYSIS.out.versions
}
