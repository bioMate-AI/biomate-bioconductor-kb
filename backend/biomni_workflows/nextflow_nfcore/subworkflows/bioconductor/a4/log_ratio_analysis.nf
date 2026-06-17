#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: a4 — log_ratio_analysis
// Compute and visualize log ratios of gene expression relative to a control or reference group across different conditions or time points.
// Input: ExpressionSet
// Container: quay.io/biocontainers/bioconductor-a4:1.58.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, a4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute log ratios relative to a reference level
//  * 2. [Visualization & Output] Plot log ratios for selected genes

nextflow.enable.dsl = 2

process BIOC_A4_LOG_RATIO_ANALYSIS {
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
    .bm_deps <- c("a4", "Biobase")
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
        library(a4)
        library(Biobase)
        
        # 1. Read the user input ExpressionSet
        input_file <- "expression_set.rds"
        if (!file.exists(input_file)) {
          stop(paste("Required input file", input_file, "not found in the working directory."))
        }
        
        eset <- readRDS(input_file)
        
        # Ensure the ExpressionSet has the necessary feature annotation (SYMBOL)
        if (!"SYMBOL" %in% colnames(fData(eset))) {
          tryCatch({
            eset <- addGeneInfo(eset)
          }, error = function(e) {
            fData(eset)\$SYMBOL <- rownames(eset)
          })
        }
        if (!"SYMBOL" %in% colnames(fData(eset))) {
          fData(eset)\$SYMBOL <- rownames(eset)
        }
        
        # --- Prepare data for Workflow 1 (Two-group log ratio analysis) ---
        # Identify categorical variables for grouping
        cat_cols <- sapply(pData(eset), function(x) is.factor(x) || is.character(x))
        if (!any(cat_cols)) {
          stop("No categorical variables found in the ExpressionSet for log-ratio analysis.")
        }
        
        group_var <- names(which(cat_cols))[1]
        group_levels <- unique(as.character(pData(eset)[[group_var]]))
        
        if (length(group_levels) < 2) {
          stop("The selected grouping variable must have at least two levels.")
        }
        
        # Subset to the first two levels to ensure tTest works correctly
        level1 <- group_levels[1]
        level2 <- group_levels[2]
        eset_sub <- eset[, pData(eset)[[group_var]] %in% c(level1, level2)]
        pData(eset_sub)[[group_var]] <- as.factor(as.character(pData(eset_sub)[[group_var]]))
        
        ref_level <- level1
        
        # Test for differential expression to select top genes
        tTestResult <- tTest(eset_sub, group_var, probe2gene = FALSE)
        topGenes <- rownames(tTestResult)[1:min(20, nrow(tTestResult))]
        
        # Compute log ratios relative to reference level
        LogRatioALL <- computeLogRatio(eset_sub, reference = list(var=group_var, level=ref_level))
        
        # Plot log ratios for top genes
        a <- plotLogRatio(e = LogRatioALL[topGenes,], 
                          openFile = FALSE, 
                          tooltipvalues = FALSE, 
                          device = "pdf", 
                          filename = "GeneLRlist", 
                          colorsColumnsBy = group_var, 
                          main = paste('Top 20 genes most differentially expressed by', group_var), 
                          orderBy = list(rows = "hclust"), 
                          probe2gene = TRUE)
        
        # Save LogRatioALL object
        saveRDS(LogRatioALL, "LogRatioALL.rds")
        
        
        # --- Prepare data for Workflow 2 (Time course / Two-factor log ratio analysis) ---
        if (ncol(pData(eset)) >= 2) {
          # Use the first categorical variable as reference variable, and another variable as 'within'
          ref_var <- names(which(cat_cols))[1]
          other_vars <- setdiff(colnames(pData(eset)), ref_var)
          within_var <- other_vars[1]
          
          ref_levels <- unique(as.character(pData(eset)[[ref_var]]))
          
          if (length(ref_levels) >= 2) {
            ref_level_tc <- ref_levels[1]
            
            # Compute log ratios for time course
            logRatioEset <- computeLogRatio(eset, 
                                            within = within_var, 
                                            reference = list(var = ref_var, level = ref_level_tc))
            
            # Re-order
            idx <- order(pData(logRatioEset)[[ref_var]], pData(logRatioEset)[[within_var]])
            logRatioEset <- logRatioEset[,idx]
            
            # Plot LogRatioEset across all
            shortvarnames <- unique(interaction(pData(logRatioEset)[[ref_var]], pData(logRatioEset)[[within_var]]))
            match_idx <- grep(ref_level_tc, as.character(shortvarnames), fixed = TRUE)
            if (length(match_idx) > 0) {
              shortvarnames <- shortvarnames[-match_idx, drop=TRUE]
            }
            
            plotLogRatio(e = logRatioEset, 
                         mx = 1, 
                         filename = "logRatioOverallTimeCourse.pdf", 
                         gene.fontsize = 8, 
                         orderBy = list(rows = "hclust", cols = NULL), 
                         colorsColumnsBy = ref_var, 
                         within = within_var, 
                         shortvarnames = shortvarnames, 
                         exp.width = 1, 
                         main = paste("Differential Expression across", within_var, "by", ref_var), 
                         reference = list(var = ref_var, level = ref_level_tc), 
                         device = 'pdf')
            
            # Save logRatioEset object
            saveRDS(logRatioEset, "logRatioEset.rds")
          } else {
            message("Skipping Workflow 2: Reference variable must have at least two levels.")
          }
        } else {
          message("Skipping Workflow 2: At least two metadata variables are required for two-factor log-ratio analysis.")
        }

    writeLines(c(
        '"BIOC_A4_LOG_RATIO_ANALYSIS":',
        paste0('    a4: ', as.character(packageVersion('a4')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_log_ratio_analysis.csv versions.yml
    """
}

workflow BIOC_A4_LOG_RATIO_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ExpressionSet ] ]

    main:
    BIOC_A4_LOG_RATIO_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_A4_LOG_RATIO_ANALYSIS.out.tables
    plots    = BIOC_A4_LOG_RATIO_ANALYSIS.out.plots
    objects  = BIOC_A4_LOG_RATIO_ANALYSIS.out.objects
    versions = BIOC_A4_LOG_RATIO_ANALYSIS.out.versions
}
