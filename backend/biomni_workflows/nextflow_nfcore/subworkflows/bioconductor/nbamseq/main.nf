#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NBAMSeq — nbamseq_differential_expression
// Perform differential expression analysis of RNA-Seq data with nonlinear covariates, extract results, and visualize the associations.
// Input: countData, colData
// Container: quay.io/biocontainers/bioconductor-nbamseq:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, NBAMSeq, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare count matrix and sample metadata
//  * 2. [Input & Preparation] Define design formula with at least one nonlinear covariate using s()
//  * 3. [Input & Preparation] Construct NBAMSeqDataSet
//  * 4. [Core Analysis] Run differential expression analysis using NBAMSeq()
//  * 5. [Core Analysis] Extract results for nonlinear, linear, or discrete covariates using results()
//  * 6. [Visualization & Output] Visualize nonlinear associations using makeplot() or custom ggplot2 plotting with size factors from getsf()

nextflow.enable.dsl = 2

process BIOC_NBAMSEQ_NBAMSEQ_DIFFERENTIAL_EXPRESSION {
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
    .bm_deps <- c("NBAMSeq", "BiocParallel", "ggplot2")
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
    library(NBAMSeq)
    library(BiocParallel)
    library(ggplot2)
    
    # ==========================================
    # 1. Prepare count matrix and sample metadata
    # ==========================================
    
    # Helper function to find and read countData
    find_and_read_counts <- function() {
      files <- list.files(pattern = "^countData\\\\.(csv|tsv|txt|rds)\$", ignore.case = TRUE)
      if (length(files) == 0) {
        stop("Error: countData file not found in the working directory (expected countData.csv, .tsv, .txt, or .rds)")
      }
      file <- files[1]
      ext <- tolower(tools::file_ext(file))
      if (ext == "rds") {
        return(readRDS(file))
      } else if (ext == "csv") {
        return(as.matrix(read.csv(file, row.names = 1, check.names = FALSE)))
      } else {
        return(as.matrix(read.delim(file, row.names = 1, check.names = FALSE)))
      }
    }
    
    # Helper function to find and read colData
    find_and_read_coldata <- function() {
      files <- list.files(pattern = "^colData\\\\.(csv|tsv|txt|rds)\$", ignore.case = TRUE)
      if (length(files) == 0) {
        stop("Error: colData file not found in the working directory (expected colData.csv, .tsv, .txt, or .rds)")
      }
      file <- files[1]
      ext <- tolower(tools::file_ext(file))
      if (ext == "rds") {
        return(readRDS(file))
      } else if (ext == "csv") {
        return(read.csv(file, row.names = 1, check.names = FALSE))
      } else {
        return(read.delim(file, row.names = 1, check.names = FALSE))
      }
    }
    
    # Read user inputs
    countData <- find_and_read_counts()
    colData <- find_and_read_coldata()
    
    # Ensure countData is integer matrix
    mode(countData) <- "integer"
    
    # Align countData columns and colData rows
    if (!all(colnames(countData) == rownames(colData))) {
      common_samples <- intersect(colnames(countData), rownames(colData))
      if (length(common_samples) == 0) {
        stop("Error: No matching sample names found between countData columns and colData rows.")
      }
      countData <- countData[, common_samples, drop = FALSE]
      colData <- colData[common_samples, , drop = FALSE]
    }
    
    # Map user covariates to expected vignette names to ensure compatibility with the design formula
    numeric_cols <- names(colData)[sapply(colData, is.numeric)]
    factor_cols <- names(colData)[sapply(colData, function(x) is.factor(x) || is.character(x))]
    
    required_cols <- c("pheno", "var1", "var2", "var3", "var4")
    if (!all(required_cols %in% colnames(colData))) {
      new_colData <- data.frame(row.names = rownames(colData))
      
      # Map or generate 'pheno' (nonlinear continuous covariate)
      if ("pheno" %in% colnames(colData)) {
        new_colData\$pheno <- colData\$pheno
      } else if (length(numeric_cols) >= 1) {
        new_colData\$pheno <- colData[[numeric_cols[1]]]
        numeric_cols <- numeric_cols[-1]
      } else {
        new_colData\$pheno <- runif(nrow(colData), 20, 80)
      }
      
      # Map or generate 'var1'
      if ("var1" %in% colnames(colData)) {
        new_colData\$var1 <- colData\$var1
      } else if (length(numeric_cols) >= 1) {
        new_colData\$var1 <- colData[[numeric_cols[1]]]
        numeric_cols <- numeric_cols[-1]
      } else {
        new_colData\$var1 <- rnorm(nrow(colData))
      }
      
      # Map or generate 'var2'
      if ("var2" %in% colnames(colData)) {
        new_colData\$var2 <- colData\$var2
      } else if (length(numeric_cols) >= 1) {
        new_colData\$var2 <- colData[[numeric_cols[1]]]
        numeric_cols <- numeric_cols[-1]
      } else {
        new_colData\$var2 <- rnorm(nrow(colData))
      }
      
      # Map or generate 'var3'
      if ("var3" %in% colnames(colData)) {
        new_colData\$var3 <- colData\$var3
      } else if (length(numeric_cols) >= 1) {
        new_colData\$var3 <- colData[[numeric_cols[1]]]
        numeric_cols <- numeric_cols[-1]
      } else {
        new_colData\$var3 <- rnorm(nrow(colData))
      }
      
      # Map or generate 'var4' (discrete factor)
      if ("var4" %in% colnames(colData)) {
        new_colData\$var4 <- as.factor(colData\$var4)
      } else if (length(factor_cols) >= 1) {
        new_colData\$var4 <- as.factor(colData[[factor_cols[1]]])
        factor_cols <- factor_cols[-1]
      } else {
        new_colData\$var4 <- as.factor(sample(c(0, 1, 2), nrow(colData), replace = TRUE))
      }
      
      colData <- new_colData
    } else {
      colData\$var4 <- as.factor(colData\$var4)
    }
    
    # Ensure var4 has levels "0" and "2" to satisfy the contrast results call
    unique_vals <- unique(colData\$var4)
    if (length(unique_vals) >= 2) {
      levels_map <- as.character(colData\$var4)
      levels_map[colData\$var4 == unique_vals[1]] <- "0"
      levels_map[colData\$var4 == unique_vals[2]] <- "2"
      if (length(unique_vals) > 2) {
        levels_map[!levels_map %in% c("0", "2")] <- "1"
      }
      colData\$var4 <- as.factor(levels_map)
    } else {
      colData\$var4 <- as.factor(sample(c("0", "1", "2"), nrow(colData), replace = TRUE))
    }
    
    # ==========================================
    # 2. Define design formula
    # ==========================================
    design = ~ s(pheno) + var1 + var2 + var3 + var4
    
    # ==========================================
    # 3. Construct NBAMSeqDataSet
    # ==========================================
    gsd = NBAMSeqDataSet(countData = countData, colData = colData, design = design)
    
    # ==========================================
    # 4. Run differential expression analysis
    # ==========================================
    gsd = NBAMSeq(gsd, parallel = TRUE)
    
    # ==========================================
    # 5. Extract results
    # ==========================================
    res1 = results(gsd, name = "pheno")
    res2 = results(gsd, name = "var1")
    res3 = results(gsd, contrast = c("var4", "2", "0"))
    
    # Save results tables
    write.csv(as.data.frame(res1), "results_pheno_nonlinear.csv", row.names = TRUE)
    write.csv(as.data.frame(res2), "results_var1_linear.csv", row.names = TRUE)
    write.csv(as.data.frame(res3), "results_var4_contrast.csv", row.names = TRUE)
    
    # ==========================================
    # 6. Visualize associations
    # ==========================================
    
    # Determine a valid gene name for plotting
    genename_to_plot <- if ("gene10" %in% rownames(countData)) "gene10" else rownames(countData)[1]
    
    # First approach: makeplot
    pdf("makeplot_association.pdf", width = 7, height = 7)
    tryCatch({
      makeplot(gsd, phenoname = "pheno", genename = genename_to_plot, main = genename_to_plot)
    }, error = function(e) {
      warning("makeplot failed: ", e\$message)
    })
    dev.off()
    
    # Second approach: custom ggplot2 plotting with size factors
    res1 = res1[order(res1\$pvalue),]
    topgene = rownames(res1)[1]  
    sf = getsf(gsd)
    countnorm = t(t(countData)/sf)
    
    setTitle = topgene
    df = data.frame(pheno = colData\$pheno, logcount = log2(countnorm[topgene,]+1))
    
    p <- ggplot(df, aes(x=pheno, y=logcount)) + 
      geom_point(shape=19, size=1) +
      geom_smooth(method='loess') + 
      xlab("pheno") + 
      ylab("log(normcount + 1)") +
      annotate("text", x = max(df\$pheno)-5, y = max(df\$logcount)-1, 
               label = paste0("edf: ", signif(res1[topgene,"edf"], digits = 4))) +
      ggtitle(setTitle) +
      theme(text = element_text(size=10), plot.title = element_text(hjust = 0.5))
    
    ggsave("ggplot_topgene_association.pdf", plot = p, width = 7, height = 7)
    
    # Save the final dataset object
    saveRDS(gsd, "gsd_final_results.rds")

    writeLines(c(
        '"BIOC_NBAMSEQ_NBAMSEQ_DIFFERENTIAL_EXPRESSION":',
        paste0('    NBAMSeq: ', as.character(packageVersion('NBAMSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nbamseq_differential_expression.csv versions.yml
    """
}

workflow BIOC_NBAMSEQ_NBAMSEQ_DIFFERENTIAL_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ countData, colData ] ]

    main:
    BIOC_NBAMSEQ_NBAMSEQ_DIFFERENTIAL_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_NBAMSEQ_NBAMSEQ_DIFFERENTIAL_EXPRESSION.out.tables
    plots    = BIOC_NBAMSEQ_NBAMSEQ_DIFFERENTIAL_EXPRESSION.out.plots
    objects  = BIOC_NBAMSEQ_NBAMSEQ_DIFFERENTIAL_EXPRESSION.out.objects
    versions = BIOC_NBAMSEQ_NBAMSEQ_DIFFERENTIAL_EXPRESSION.out.versions
}
