#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MPRAnalyze — scalable_comparative_analysis
// Run a fast comparative analysis on large datasets with matched DNA/RNA observations by using DNA counts directly instead of fitting a DNA model.
// Input: dna_counts.tsv, rna_counts.tsv, col_annotations.tsv
// Container: quay.io/biocontainers/bioconductor-mpranalyze:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MPRAnalyze
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read the user input files from the working directory
//  * 2. [Core Analysis] Initialize the MpraObject
//  * 3. [Core Analysis] Estimate library depth normalization factors using valid
//  * 4. [Core Analysis] Fit the comparative models in scalable mode
//  * 5. [Core Analysis] Perform a Likelihood Ratio Test to identify
//  * 6. [Core Analysis] Write outputs to the working directory

nextflow.enable.dsl = 2

process BIOC_MPRANALYZE_SCALABLE_COMPARATIVE_ANALYSIS {
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
    .bm_deps <- c("MPRAnalyze")
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
        library(MPRAnalyze)
        
        # --- Read the user input files from the working directory ---
        dna_counts_file <- "dna_counts.tsv"
        rna_counts_file <- "rna_counts.tsv"
        col_annotations_file <- "col_annotations.tsv"
        
        if (!file.exists(dna_counts_file) || !file.exists(rna_counts_file) || !file.exists(col_annotations_file)) {
          stop("Error: Missing required input files (dna_counts.tsv, rna_counts.tsv, col_annotations.tsv)")
        }
        
        # Load DNA and RNA count matrices
        ce.dnaCounts <- as.matrix(read.table(dna_counts_file, header = TRUE, row.names = 1, sep = "\t"))
        ce.rnaCounts <- as.matrix(read.table(rna_counts_file, header = TRUE, row.names = 1, sep = "\t"))
        
        # Load column annotations
        ce.colAnnot <- read.table(col_annotations_file, header = TRUE, row.names = 1, sep = "\t")
        
        # Ensure factors are correctly formatted dynamically based on provided columns
        for (col in colnames(ce.colAnnot)) {
          ce.colAnnot[[col]] <- as.factor(ce.colAnnot[[col]])
        }
        
        # Establish controls vector based on row names (enhancers)
        # Look for common control identifiers in the row names, defaulting to FALSE if none are found
        ce.control <- grepl("control|scramble|shuffled|NC|ctrl", rownames(ce.dnaCounts), ignore.case = TRUE)
        if (sum(ce.control) == 0) {
          ce.control <- rep(FALSE, nrow(ce.dnaCounts))
        }
        
        # --- Initialize the MpraObject ---
        obj <- MpraObject(dnaCounts = ce.dnaCounts, rnaCounts = ce.rnaCounts, 
                          dnaAnnot = ce.colAnnot, rnaAnnot = ce.colAnnot, 
                          controls = ce.control)
        
        # Filter annotation columns to avoid overparameterization
        # Exclude 'barcode' and columns where all values are unique (e.g., unique sample IDs)
        valid_cols <- colnames(ce.colAnnot)
        valid_cols <- valid_cols[!grepl("barcode", valid_cols, ignore.case = TRUE)]
        
        if (length(valid_cols) > 0) {
          valid_cols <- valid_cols[sapply(ce.colAnnot[valid_cols], function(x) length(unique(x)) < nrow(ce.colAnnot))]
        }
        
        if (length(valid_cols) == 0) {
          valid_cols <- colnames(ce.colAnnot)[1]
        }
        
        # --- Estimate library depth normalization factors using valid ---
        obj <- estimateDepthFactors(obj, lib.factor = valid_cols,
                                    which.lib = "both")
        
        # --- Fit the comparative models in scalable mode ---
        # Dynamically construct the RNA design formula using valid annotation columns
        rna_design_formula <- as.formula(paste("~", paste(valid_cols, collapse = " + ")))
        
        obj <- analyzeComparative(obj = obj, 
                                  rnaDesign = rna_design_formula, 
                                  reducedDesign = ~ 1, 
                                  mode="scale")
        
        # --- Perform a Likelihood Ratio Test to identify ---
        res.scale <- testLrt(obj)
        
        # --- Write outputs to the working directory ---
        write.csv(res.scale, file = "comparative_analysis_scale_results.csv", row.names = TRUE)
        saveRDS(obj, file = "mpra_object_scale.rds")
        
        # Generate diagnostic and results plots
        pdf("comparative_analysis_scale_plots.pdf", width = 10, height = 5)
        par(mfrow = c(1, 2))
        
        if ("logFC" %in% colnames(res.scale)) {
          plot(density(res.scale\$logFC, na.rm = TRUE), 
               main = "Log Fold-Change Density (Scalable Mode)", 
               xlab = "logFC")
          
          if ("pval" %in% colnames(res.scale)) {
            plot(res.scale\$logFC, -log10(res.scale\$pval), 
                 main = "Volcano Plot (Scalable Mode)", 
                 xlab = "logFC", 
                 ylab = "-log10(pval)", 
                 pch = 20, 
                 col = "darkblue")
          }
        } else if ("pval" %in% colnames(res.scale)) {
          hist(res.scale\$pval, 
               breaks = 20, 
               main = "p-value Distribution", 
               xlab = "p-value", 
               col = "lightgray")
        }
        
        dev.off()

    writeLines(c(
        '"BIOC_MPRANALYZE_SCALABLE_COMPARATIVE_ANALYSIS":',
        paste0('    MPRAnalyze: ', as.character(packageVersion('MPRAnalyze')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scalable_comparative_analysis.csv versions.yml
    """
}

workflow BIOC_MPRANALYZE_SCALABLE_COMPARATIVE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dna_counts.tsv, rna_counts.tsv, col_annotations.tsv ] ]

    main:
    BIOC_MPRANALYZE_SCALABLE_COMPARATIVE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MPRANALYZE_SCALABLE_COMPARATIVE_ANALYSIS.out.tables
    plots    = BIOC_MPRANALYZE_SCALABLE_COMPARATIVE_ANALYSIS.out.plots
    objects  = BIOC_MPRANALYZE_SCALABLE_COMPARATIVE_ANALYSIS.out.objects
    versions = BIOC_MPRANALYZE_SCALABLE_COMPARATIVE_ANALYSIS.out.versions
}
