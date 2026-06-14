#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: missMethyl — diff_var_rnaseq
// Test for differences in gene expression variance between groups in RNA-Seq data, accounting for the mean-variance relationship.
// Input: counts, annot, gender
// Container: quay.io/biocontainers/bioconductor-missmethyl:1.44.0--r45hdfd78af_0
// R packages: edgeR, limma, missMethyl
// Bioconductor: 3.20 | R: 4.4
// Requires: edgeR, limma, missMethyl
// Visualizations: strip chart
// QC: TMM normalization, low-count filtering, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read user inputs from the working directory
//  * 2. [Input & Preparation] Create a DGEList object
//  * 3. [Input & Preparation] Filter lowly expressed genes and normalize library sizes
//  * 4. [Input & Preparation] Fit the variability model using varFit
//  * 5. [Input & Preparation] Extract top differentially variable genes using topVar
//  * 6. [Input & Preparation] Write outputs

nextflow.enable.dsl = 2

process BIOC_MISSMETHYL_DIFF_VAR_RNASEQ {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("edgeR", "limma", "missMethyl")
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
    library(missMethyl)
    library(edgeR)
    library(limma)
    
    # Helper function to robustly read matrix or data frame inputs
    read_matrix_or_df <- function(filename) {
      exts <- c("", ".rds", ".csv", ".tsv", ".txt")
      found_path <- NULL
      for (ext in exts) {
        path <- paste0(filename, ext)
        if (file.exists(path)) {
          found_path <- path
          break
        }
      }
      if (is.null(found_path)) {
        stop(paste("Required input file not found:", filename))
      }
    
      if (grepl("\\\\.rds\$", found_path, ignore.case = TRUE)) {
        return(readRDS(found_path))
      } else if (grepl("\\\\.csv\$", found_path, ignore.case = TRUE)) {
        res <- tryCatch({
          read.csv(found_path, row.names = 1, check.names = FALSE)
        }, error = function(e) {
          read.csv(found_path, check.names = FALSE)
        })
        return(res)
      } else {
        res <- tryCatch({
          read.table(found_path, header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
        }, error = function(e) {
          read.table(found_path, header = TRUE, sep = "\t", check.names = FALSE)
        })
        return(res)
      }
    }
    
    # Helper function to robustly read the gender covariate vector
    read_gender <- function() {
      exts <- c("", ".rds", ".csv", ".tsv", ".txt")
      found_path <- NULL
      for (ext in exts) {
        path <- paste0("gender", ext)
        if (file.exists(path)) {
          found_path <- path
          break
        }
      }
      if (is.null(found_path)) {
        stop("Required input file not found: gender")
      }
    
      if (grepl("\\\\.rds\$", found_path, ignore.case = TRUE)) {
        val <- readRDS(found_path)
      } else if (grepl("\\\\.csv\$", found_path, ignore.case = TRUE)) {
        df <- read.csv(found_path, header = FALSE)
        if (ncol(df) == 1) {
          val <- df[[1]]
        } else {
          val <- df[[2]]
        }
      } else if (grepl("\\\\.tsv\$", found_path, ignore.case = TRUE)) {
        df <- read.delim(found_path, header = FALSE)
        if (ncol(df) == 1) {
          val <- df[[1]]
        } else {
          val <- df[[2]]
        }
      } else {
        val <- readLines(found_path)
      }
      return(as.factor(val))
    }
    
    # --- Read user inputs from the working directory ---
    counts <- as.matrix(read_matrix_or_df("counts"))
    annot <- read_matrix_or_df("annot")
    gender <- read_gender()
    
    # Validate dimensions
    if (length(gender) != ncol(counts)) {
      stop(sprintf("Length of gender vector (%d) does not match number of columns in counts matrix (%d)", length(gender), ncol(counts)))
    }
    
    if (length(unique(gender)) < 2) {
      stop("Gender covariate must have at least 2 levels to test for differential variability.")
    }
    
    # Ensure annotation has Symbol and Chr columns
    if (!all(c("Symbol", "Chr") %in% colnames(annot))) {
      if ("symbol" %in% tolower(colnames(annot))) {
        colnames(annot)[tolower(colnames(annot)) == "symbol"] <- "Symbol"
      } else {
        annot\$Symbol <- rownames(annot)
      }
      if ("chr" %in% tolower(colnames(annot))) {
        colnames(annot)[tolower(colnames(annot)) == "chr"] <- "Chr"
      } else {
        annot\$Chr <- "Unknown"
      }
    }
    annot <- annot[, c("Symbol", "Chr"), drop = FALSE]
    
    # --- Create a DGEList object ---
    y <- DGEList(counts=counts, genes=annot[rownames(counts),])
    
    # --- Filter lowly expressed genes and normalize library sizes ---
    isexpr <- rowSums(cpm(y)>1) >= 20
    # Fallback for small sample sizes to ensure the pipeline runs successfully
    if (sum(isexpr) == 0) {
      warning("No genes passed the default filter (cpm > 1 in >= 20 samples). Adjusting threshold for small dataset.")
      isexpr <- rowSums(cpm(y)>1) >= max(1, ncol(y) %/% 2)
    }
    
    hasannot <- rowSums(is.na(y\$genes))==0
    if (sum(isexpr & hasannot) == 0) {
      warning("No genes have complete annotations. Proceeding without annotation filtering.")
      hasannot <- rep(TRUE, nrow(y))
    }
    
    y <- y[isexpr & hasannot,,keep.lib.sizes=FALSE]
    y <- calcNormFactors(y)
    
    # --- Fit the variability model using varFit ---
    design.hapmap <- model.matrix(~gender)
    fitvar.hapmap <- varFit(y, design = design.hapmap, coef=c(1,2))
    fitvar.hapmap\$genes <- y\$genes
    
    # --- Extract top differentially variable genes using topVar ---
    topDV.hapmap <- topVar(fitvar.hapmap,coef=ncol(design.hapmap))
    
    # --- Write outputs ---
    write.csv(topDV.hapmap, file = "top_DV_genes.csv", row.names = TRUE)
    saveRDS(fitvar.hapmap, file = "fitvar_hapmap.rds")
    
    # Generate visualization plot
    pdf("diff_var_plots.pdf", width = 8, height = 8)
    genesDV <- rownames(topDV.hapmap)
    n_plots <- min(4, length(genesDV))
    if (n_plots > 0) {
      par(mfrow=c(2,2))
      for(i in 1:n_plots){
        stripchart(cpm(y,log=TRUE)[rownames(y)==genesDV[i],]~design.hapmap[,ncol(design.hapmap)],
                   method="jitter",
                   group.names=levels(factor(gender)),
                   pch=16, cex=1.5, col=c(4,2),
                   ylab="Log counts per million",
                   vertical=TRUE, cex.axis=1.5, cex.lab=1.5)
        title(genesDV[i], cex.main=1.5)
      }
    }
    dev.off()

    writeLines(c(
        '"BIOC_MISSMETHYL_DIFF_VAR_RNASEQ":',
        paste0('    missMethyl: ', as.character(packageVersion('missMethyl')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_diff_var_rnaseq.csv versions.yml
    """
}

workflow BIOC_MISSMETHYL_DIFF_VAR_RNASEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts, annot, gender ] ]

    main:
    BIOC_MISSMETHYL_DIFF_VAR_RNASEQ(ch_input)

    emit:
    tables   = BIOC_MISSMETHYL_DIFF_VAR_RNASEQ.out.tables
    plots    = BIOC_MISSMETHYL_DIFF_VAR_RNASEQ.out.plots
    objects  = BIOC_MISSMETHYL_DIFF_VAR_RNASEQ.out.objects
    versions = BIOC_MISSMETHYL_DIFF_VAR_RNASEQ.out.versions
}
