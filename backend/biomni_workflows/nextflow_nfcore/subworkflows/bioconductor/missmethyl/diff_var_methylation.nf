#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: missMethyl — diff_var_methylation
// Test for differences in methylation variance between groups.
// Input: Mval, design
// Container: quay.io/biocontainers/bioconductor-missmethyl:1.44.0--r45hdfd78af_0
// R packages: limma, missMethyl
// Bioconductor: 3.20 | R: 4.4
// Requires: limma, missMethyl
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit the variability model using varFit, specifying the
//  * 2. [Core Analysis] Extract top differentially variable CpGs using topVar

nextflow.enable.dsl = 2

process BIOC_MISSMETHYL_DIFF_VAR_METHYLATION {
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
    .bm_deps <- c("limma", "missMethyl")
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
                library(limma)
                
                # Function to read input files flexibly (RDS, CSV, TSV, or TXT)
                read_input <- function(base_name) {
                  rds_file <- paste0(base_name, ".rds")
                  csv_file <- paste0(base_name, ".csv")
                  tsv_file <- paste0(base_name, ".tsv")
                  txt_file <- paste0(base_name, ".txt")
                  
                  if (file.exists(rds_file)) {
                    return(readRDS(rds_file))
                  } else if (file.exists(csv_file)) {
                    df <- read.csv(csv_file, row.names = 1, check.names = FALSE)
                    return(as.matrix(df))
                  } else if (file.exists(tsv_file)) {
                    df <- read.delim(tsv_file, row.names = 1, check.names = FALSE)
                    return(as.matrix(df))
                  } else if (file.exists(txt_file)) {
                    df <- read.table(txt_file, header = TRUE, row.names = 1, check.names = FALSE)
                    return(as.matrix(df))
                  } else {
                    stop(paste("Error: Required input file for", base_name, "not found in the working directory."))
                  }
                }
                
                # Read user inputs
                Mval <- read_input("Mval")
                design <- read_input("design")
                
                # Validate design matrix dimensions
                if (ncol(design) < 2) {
                  stop("The input design matrix must have at least 2 columns.")
                }
                
                # --- DOCUMENTED WORKFLOW ---
                
                # --- Fit the variability model using varFit, specifying the ---
                coef_interest <- ncol(design)
                fitvar <- varFit(Mval, design = design, coef = c(1, coef_interest))
                
                # --- Extract top differentially variable CpGs using topVar ---
                topDV <- topVar(fitvar, coef=coef_interest)
                
                # 3. (Alternative) Test specific contrasts using contrasts.varFit.
                design2 <- design
                intercept_col <- which(colnames(design2) == "(Intercept)")
                
                if (length(intercept_col) > 0) {
                  # Convert intercept model to cell-means model
                  design2[, intercept_col] <- design2[, intercept_col] - design2[, coef_interest]
                  colnames(design2)[intercept_col] <- "Group1"
                  colnames(design2)[coef_interest] <- "Group2"
                  colnames(design2) <- make.names(colnames(design2))
                  
                  fitvar2 <- varFit(Mval, design = design2, coef = c(intercept_col, coef_interest))
                  contr <- makeContrasts(Group2 - Group1, levels = colnames(design2))
                  fitvar.contr <- contrasts.varFit(fitvar2, contrasts = contr)
                  top_contr <- topVar(fitvar.contr, coef = 1)
                } else {
                  # If no intercept, ensure valid names and fit
                  colnames(design2) <- make.names(colnames(design2))
                  fitvar2 <- varFit(Mval, design = design2, coef = c(1, coef_interest))
                  group1_name <- colnames(design2)[1]
                  group2_name <- colnames(design2)[coef_interest]
                  contr_string <- paste0(group2_name, "-", group1_name)
                  contr <- makeContrasts(contrasts = contr_string, levels = colnames(design2))
                  fitvar.contr <- contrasts.varFit(fitvar2, contrasts = contr)
                  top_contr <- topVar(fitvar.contr, coef = 1)
                }
                
                # --- SAVE OUTPUTS ---
                
                # Save RDS objects
                saveRDS(fitvar, "fitvar.rds")
                saveRDS(fitvar.contr, "fitvar_contr.rds")
                
                # Save CSV tables
                write.csv(topDV, "top_variable_cpgs.csv", row.names = TRUE)
                write.csv(top_contr, "top_variable_cpgs_contrasts.csv", row.names = TRUE)
                
                # Generate PDF plot of top differentially variable CpGs
                pdf("top_dv_cpgs_mvalues.pdf", width = 8, height = 8)
                cpgsDV <- rownames(topDV)
                group_factor <- as.factor(design[, coef_interest])
                
                par(mfrow=c(2,2))
                for(i in 1:min(4, length(cpgsDV))){
                  stripchart(Mval[rownames(Mval)==cpgsDV[i],] ~ group_factor, method="jitter",
                             group.names=levels(group_factor), pch=16, cex=1.5, col=c(4,2),
                             ylab="M-values", vertical=TRUE, cex.axis=1.5, cex.lab=1.5)
                  title(cpgsDV[i], cex.main=1.5)
                }
                dev.off()
                
                message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_MISSMETHYL_DIFF_VAR_METHYLATION":',
        paste0('    missMethyl: ', as.character(packageVersion('missMethyl')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_diff_var_methylation.csv versions.yml
    """
}

workflow BIOC_MISSMETHYL_DIFF_VAR_METHYLATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Mval, design ] ]

    main:
    BIOC_MISSMETHYL_DIFF_VAR_METHYLATION(ch_input)

    emit:
    tables   = BIOC_MISSMETHYL_DIFF_VAR_METHYLATION.out.tables
    plots    = BIOC_MISSMETHYL_DIFF_VAR_METHYLATION.out.plots
    objects  = BIOC_MISSMETHYL_DIFF_VAR_METHYLATION.out.objects
    versions = BIOC_MISSMETHYL_DIFF_VAR_METHYLATION.out.versions
}
