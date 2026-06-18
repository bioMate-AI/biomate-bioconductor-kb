#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MEAL — methylation_analysis
// Perform genome-wide differential methylation mean and variance analysis on preprocessed methylation data.
// Input: meth
// Container: quay.io/biocontainers/bioconductor-meal:1.28.0--r42hdfd78af_0
// R packages: brgedata, GenomicRanges, ggplot2, MEAL, minfi, MultiDataSet
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, MEAL, ggplot2
// Visualizations: genomic region plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run the analysis pipeline using runPipeline
//  * 2. [Core Analysis] Extract results using getAssociation, getProbeResults, or getGeneVals
//  * 3. [Visualization & Output] Visualize results using plot (Manhattan, Volcano, QQ-plots), plotFeature, or plotRegion

nextflow.enable.dsl = 2

process BIOC_MEAL_METHYLATION_ANALYSIS {
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
    .bm_deps <- c("brgedata", "GenomicRanges", "ggplot2", "MEAL", "minfi", "MultiDataSet", "SummarizedExperiment")
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
        library(MEAL)
        library(SummarizedExperiment)
        library(GenomicRanges)
        library(ggplot2)
        
        # -----------------------------------------------------------------------------
        # Stage 0: Read User Input
        # -----------------------------------------------------------------------------
        # The pipeline expects a preprocessed GenomicRatioSet object named 'meth' or 'meth.rds'
        # in the working directory.
        if (file.exists("meth")) {
          meth <- readRDS("meth")
        } else if (file.exists("meth.rds")) {
          meth <- readRDS("meth.rds")
        } else {
          stop("Error: Input file 'meth' or 'meth.rds' (GenomicRatioSet) not found in the working directory.")
        }
        
        # -----------------------------------------------------------------------------
        # Stage 1: Run the Analysis Pipeline
        # -----------------------------------------------------------------------------
        # Dynamically select phenotype variables from the dataset
        pheno_vars <- colnames(colData(meth))
        if (length(pheno_vars) == 0) {
          stop("Error: No phenotypic variables found in colData(meth).")
        }
        var_name <- pheno_vars[1]
        covar_name <- NULL
        
        if (length(pheno_vars) > 1) {
          for (cv in pheno_vars[-1]) {
            val_var <- colData(meth)[[var_name]]
            val_cov <- colData(meth)[[cv]]
            
            # Check for missing values in the covariate
            if (any(is.na(val_cov))) next
            
            # Check for collinearity
            valid_idx <- !is.na(val_var)
            if (sum(valid_idx) > 2) {
              val_var_sub <- val_var[valid_idx]
              val_cov_sub <- val_cov[valid_idx]
              
              if (length(unique(val_cov_sub)) > 1) {
                tmp_df <- data.frame(v1 = val_var_sub, v2 = val_cov_sub)
                mm <- try(model.matrix(~ v1 + v2, data = tmp_df), silent = TRUE)
                if (!inherits(mm, "try-error")) {
                  if (qr(mm)\$rank == ncol(mm)) {
                    covar_name <- cv
                    break
                  }
                }
              }
            }
          }
        }
        
        resAdj <- runPipeline(set = meth, variable_names = var_name, 
                              covariable_names = covar_name, analyses = c("DiffMean", "DiffVar"))
        
        # Save the complete ResultSet object
        saveRDS(resAdj, "resAdj.rds")
        
        # -----------------------------------------------------------------------------
        # Stage 2: Extract and Save Results
        # -----------------------------------------------------------------------------
        # Print names of analyses in the ResultSet
        print(names(resAdj))
        
        # Extract and save DiffMean associations
        diff_mean_assoc <- getAssociation(resAdj, "DiffMean")
        write.csv(diff_mean_assoc, "association_diffmean.csv", row.names = TRUE)
        print(head(diff_mean_assoc))
        
        # Extract and save DiffVar associations
        diff_var_assoc <- getAssociation(resAdj, "DiffVar")
        write.csv(diff_var_assoc, "association_diffvar.csv", row.names = TRUE)
        print(head(diff_var_assoc))
        
        # Extract and save probe results for multiple coefficients
        # Dynamically determine coefficients based on the model
        coefs_to_extract <- if (!is.null(covar_name)) 2:3 else 2
        
        rData_cols <- colnames(rowData(meth))
        fNames_to_use <- c("chromosome", "start")
        fNames_to_use <- fNames_to_use[fNames_to_use %in% rData_cols]
        
        if (length(fNames_to_use) > 0) {
          probe_results <- getProbeResults(resAdj, rid = 1, coef = coefs_to_extract, 
                                            fNames = fNames_to_use)
        } else {
          probe_results <- getProbeResults(resAdj, rid = 1, coef = coefs_to_extract)
        }
        write.csv(probe_results, "probe_results.csv", row.names = TRUE)
        print(head(probe_results))
        
        # Extract and save gene-specific values
        # Dynamically select a gene from the dataset
        rData <- rowData(meth)
        gene_col <- grep("gene", colnames(rData), ignore.case = TRUE, value = TRUE)[1]
        if (is.na(gene_col)) {
          gene_col <- "UCSC_RefGene_Name"
        }
        
        if (gene_col %in% colnames(rData)) {
          genes <- as.character(rData[[gene_col]])
          genes <- unlist(strsplit(genes, "[,;]"))
          genes <- trimws(genes)
          valid_genes <- unique(genes[!is.na(genes) & genes != "" & genes != "character(0)"])
          target_gene <- if (length(valid_genes) > 0) valid_genes[1] else "ARMS2"
        } else {
          target_gene <- "ARMS2"
        }
        
        # Wrapped in tryCatch in case the gene or the annotation column is missing in the input dataset
        tryCatch({
          if (length(fNames_to_use) > 0) {
            gene_vals <- getGeneVals(resAdj, target_gene, genecol = gene_col, fNames = fNames_to_use)
          } else {
            gene_vals <- getGeneVals(resAdj, target_gene, genecol = gene_col)
          }
          write.csv(gene_vals, paste0("gene_vals_", target_gene, ".csv"), row.names = TRUE)
          print(gene_vals)
        }, error = function(e) {
          warning("Could not extract gene values for ", target_gene, ": ", e\$message)
        })
        
        # -----------------------------------------------------------------------------
        # Stage 3: Visualize Results
        # -----------------------------------------------------------------------------
        pdf("methylation_analysis_plots.pdf", width = 10, height = 8)
        
        # Manhattan plots (Base R graphics)
        targetRange <- GRanges("23:13000000-23000000")
        tryCatch({
          plot(resAdj, rid = "DiffMean", type = "manhattan", highlight = targetRange)
        }, error = function(e) {
          warning("Manhattan plot with highlight failed: ", e\$message)
        })
        
        tryCatch({
          plot(resAdj, rid = "DiffMean", type = "manhattan", subset = targetRange)
        }, error = function(e) {
          warning("Manhattan plot with subset failed: ", e\$message)
        })
        
        tryCatch({
          plot(resAdj, rid = "DiffMean", type = "manhattan", suggestiveline = 3, 
               genomewideline = 6, main = "My custom Manhattan")
          abline(h = 13, col = "yellow")
        }, error = function(e) {
          warning("Custom Manhattan plot failed: ", e\$message)
        })
        
        # Volcano plot (ggplot2)
        tryCatch({
          p_volcano <- plot(resAdj, rid = "DiffMean", type = "volcano", tPV = 14, tFC = 0.4, 
                            show.labels = FALSE) + ggtitle("My custom Volcano")
          print(p_volcano)
        }, error = function(e) {
          warning("Volcano plot failed: ", e\$message)
        })
        
        # QQ plot (ggplot2)
        tryCatch({
          p_qq <- plot(resAdj, rid = "DiffMean", type = "qq") + ggtitle("My custom QQplot")
          print(p_qq)
        }, error = function(e) {
          warning("QQ plot failed: ", e\$message)
        })
        
        # Feature plots (ggplot2)
        # Dynamically select probe IDs from the dataset
        valid_probes <- rownames(meth)
        probe1 <- if (length(valid_probes) > 0) valid_probes[1] else "cg09383816"
        probe2 <- if (length(valid_probes) > 1) valid_probes[2] else probe1
        
        # Wrapped in tryCatch as specific probe IDs may not exist in the user's input dataset
        tryCatch({
          p_feat1 <- plotFeature(set = meth, feat = probe1, variables = var_name) + 
            ggtitle("Diff Means")
          print(p_feat1)
        }, error = function(e) {
          warning("plotFeature for ", probe1, " failed: ", e\$message)
        })
        
        tryCatch({
          p_feat2 <- plotFeature(set = meth, feat = probe2, variables = var_name) + 
            ggtitle("Diff Vars")
          print(p_feat2)
        }, error = function(e) {
          warning("plotFeature for ", probe2, " failed: ", e\$message)
        })
        
        # Regional plots
        targetRange_X <- GRanges("chrX:13000000-14000000")
        tryCatch({
          plotRegion(resAdj, targetRange_X)
        }, error = function(e) {
          warning("plotRegion failed: ", e\$message)
        })
        
        tryCatch({
          plotRegion(resAdj, targetRange_X, results = c("DiffMean"), tPV = 10)
        }, error = function(e) {
          warning("plotRegion with results filter failed: ", e\$message)
        })
        
        dev.off()
        
        cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_MEAL_METHYLATION_ANALYSIS":',
        paste0('    MEAL: ', as.character(packageVersion('MEAL')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylation_analysis.csv versions.yml
    """
}

workflow BIOC_MEAL_METHYLATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ meth ] ]

    main:
    BIOC_MEAL_METHYLATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MEAL_METHYLATION_ANALYSIS.out.tables
    plots    = BIOC_MEAL_METHYLATION_ANALYSIS.out.plots
    objects  = BIOC_MEAL_METHYLATION_ANALYSIS.out.objects
    versions = BIOC_MEAL_METHYLATION_ANALYSIS.out.versions
}
