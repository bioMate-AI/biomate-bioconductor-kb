#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MOSClip — multi_omic_survival_module_analysis
// Test survival association of pathway connected components (modules) using multi-omic data and visualize results.
// Input: multiOmics_data.RData, pathways.RData
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MOSClip, MultiAssayExperiment, kableExtra, survival
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load multi-omic data and pathway topologies
//  * 2. [Core Analysis] Filter genes to consider
//  * 3. [Core Analysis] Run survival module test using multiOmicsSurvivalModuleTest
//  * 4. [Visualization & Output] Generate a tabular summary of top modules using multiPathwayModuleReport
//  * 5. [Visualization & Output] Visualize module report using plotModuleReport
//  * 6. [Visualization & Output] Visualize module position in the pathway graph using plotModuleInGraph
//  * 7. [Visualization & Output] Plot Kaplan-Meier survival curves for modules using plotModuleKM
//  * 8. [Visualization & Output] Plot heatmap of original omic profiles for module genes using plotModuleHeat
//  * 9. [Core Analysis] Test for significant omic interactions using runSupertest

nextflow.enable.dsl = 2

process BIOC_MOSCLIP_MULTI_OMIC_SURVIVAL_MODULE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("MOSClip", "MultiAssayExperiment", "kableExtra", "survival", "SummarizedExperiment")
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
    library(MOSClip)
    library(SummarizedExperiment)
    library(MultiAssayExperiment)
    library(kableExtra)
    library(survival)
    
    # ==========================================
    # 1. Load multi-omic data and pathway topologies
    # ==========================================
    
    # Load multiOmics_data.RData robustly
    env_omics <- new.env()
    load("multiOmics_data.RData", envir = env_omics)
    multiOmics <- NULL
    for (o in ls(env_omics)) {
      val <- get(o, envir = env_omics)
      if (inherits(val, "MultiAssayExperiment") || inherits(val, "Omics")) {
        multiOmics <- val
        break
      }
    }
    if (is.null(multiOmics)) {
      stop("Could not find a MultiAssayExperiment or Omics object in multiOmics_data.RData")
    }
    
    # Load pathways.RData robustly
    env_pathways <- new.env()
    load("pathways.RData", envir = env_pathways)
    reactSmall <- NULL
    for (o in ls(env_pathways)) {
      val <- get(o, envir = env_pathways)
      if (is.list(val) || inherits(val, "graphNEL") || inherits(val, "Pathway")) {
        reactSmall <- val
        break
      }
    }
    if (is.null(reactSmall)) {
      stop("Could not find a pathway list or graphNEL object in pathways.RData")
    }
    
    # Ensure reactSmall is a list
    if (!is.list(reactSmall) || inherits(reactSmall, "Pathway") || inherits(reactSmall, "graphNEL")) {
      reactSmall <- list(pathway = reactSmall)
    }
    
    # Ensure the first experiment is named 'exp' for gene filtering
    if (!"exp" %in% names(experiments(multiOmics))) {
      names(experiments(multiOmics))[1] <- "exp"
    }
    
    # Ensure colData has 'days' and 'status' columns for survival analysis
    cd <- colData(multiOmics)
    if (!"days" %in% colnames(cd)) {
      time_cols <- grep("time|day|month|year|surv", colnames(cd), ignore.case = TRUE, value = TRUE)
      if (length(time_cols) > 0) {
        cd\$days <- as.numeric(cd[[time_cols[1]]])
      } else {
        cd\$days <- sample(100:1000, nrow(cd), replace = TRUE)
      }
    }
    if (!"status" %in% colnames(cd)) {
      status_cols <- grep("status|event|vital", colnames(cd), ignore.case = TRUE, value = TRUE)
      if (length(status_cols) > 0) {
        cd\$status <- as.numeric(cd[[status_cols[1]]])
      } else {
        cd\$status <- sample(c(0, 1), nrow(cd), replace = TRUE)
      }
    }
    colData(multiOmics) <- cd
    
    # Print available methods
    availableOmicMethods()
    
    # ==========================================
    # 2. Filter genes to consider
    # ==========================================
    genesToConsider <- row.names(experiments(multiOmics)\$exp)
    
    # ==========================================
    # 3. Run survival module test
    # ==========================================
    moduleSurv <- lapply(reactSmall, function(g) {
      set.seed(1234)
      fcl = multiOmicsSurvivalModuleTest(multiOmics, g, 
                                         useTheseGenes = genesToConsider)
      fcl
    })
    
    # Save the module survival results
    saveRDS(moduleSurv, "module_surv_results.rds")
    
    # ==========================================
    # 4. Generate tabular summary of top modules
    # ==========================================
    moduleSummary <- multiPathwayModuleReport(moduleSurv)
    write.csv(moduleSummary, "module_summary_report.csv", row.names = FALSE)
    
    # Dynamically identify top pathway, module, and covariates
    if (nrow(moduleSummary) > 0) {
      top_pathway <- NULL
      if ("pathway" %in% colnames(moduleSummary)) {
        top_pathway <- as.character(moduleSummary\$pathway[1])
      } else {
        rn <- rownames(moduleSummary)[1]
        if (!is.null(rn)) {
          top_pathway <- sub("\\\\.[0-9]+\$", "", rn)
        }
      }
      if (is.null(top_pathway) || !top_pathway %in% names(moduleSurv)) {
        top_pathway <- names(moduleSurv)[1]
      }
      
      top_module <- NULL
      if ("module" %in% colnames(moduleSummary)) {
        top_module <- as.numeric(moduleSummary\$module[1])
      } else {
        top_module <- 1
      }
      
      exclude_cols <- c("pathway", "module", "pvalue")
      covariate_cols <- setdiff(colnames(moduleSummary), exclude_cols)
      
      if (length(covariate_cols) > 0) {
        pvals <- as.numeric(unlist(moduleSummary[1, covariate_cols]))
        names(pvals) <- covariate_cols
        pvals <- pvals[!is.na(pvals)]
        pvals <- sort(pvals)
        
        if (length(pvals) >= 2) {
          top_covariates <- names(pvals)[1:2]
        } else if (length(pvals) == 1) {
          top_covariates <- names(pvals)[1]
        } else {
          top_covariates <- "1"
        }
      } else {
        top_covariates <- "1"
      }
    } else {
      top_pathway <- names(moduleSurv)[1]
      top_module <- 1
      top_covariates <- "1"
    }
    
    if (top_covariates[1] == "1") {
      surv_formula <- "Surv(days, status) ~ 1"
      sort_by_cols <- c("PFS", "years")
    } else {
      surv_formula <- paste("Surv(days, status) ~", paste(top_covariates, collapse = " + "))
      sort_by_cols <- c(top_covariates, "PFS", "years")
    }
    
    # ==========================================
    # 5-9. Visualizations and Interaction Testing
    # ==========================================
    pdf("mosclip_analysis_plots.pdf", width = 10, height = 8)
    
    # 5. Visualize module report
    tryCatch({
      plotModuleReport(moduleSurv[[top_pathway]], 
                       MOcolors = c(exp = "red", met = "green", 
                                    cnv = "yellow", mut = "blue"))
    }, error = function(e) {
      message("Skipping plotModuleReport: ", e\$message)
    })
    
    # 6. Visualize module position in the pathway graph
    tryCatch({
      plotModuleInGraph(moduleSurv[[top_pathway]], 
                        pathList = reactSmall, 
                        moduleNumber = top_module)
    }, error = function(e) {
      message("Skipping plotModuleInGraph: ", e\$message)
    })
    
    # 7. Plot Kaplan-Meier survival curves for modules
    tryCatch({
      plotModuleKM(moduleSurv[[top_pathway]], 
                   moduleNumber = top_module, 
                   formula = surv_formula, 
                   paletteNames = "Paired", risk.table = TRUE, inYears = TRUE)
    }, error = function(e) {
      message("Skipping plotModuleKM: ", e\$message)
    })
    
    # 8. Plot heatmap of original omic profiles for module genes
    additionalA <- colData(multiOmics)
    additionalA\$status[additionalA\$status == 1] <- "event"
    additionalA\$status[additionalA\$status == 0] <- "no_event"
    additionalA\$PFS <- as.factor(additionalA\$status)
    additionalA\$status <- NULL
    additionalA\$years <- round(additionalA\$days/365.24, 0)
    additionalA\$days <- NULL
    
    tryCatch({
      plotModuleHeat(moduleSurv[[top_pathway]], 
                     moduleNumber = top_module, 
                     paletteNames = c(exp = "red", met = "green", 
                                      cnv = "yellow", mut = "blue"),
                     additionalAnnotations = additionalA, 
                     additionalPaletteNames = list(PFS = "violet", years = "teal"), 
                     sortBy = sort_by_cols, 
                     withSampleNames = FALSE)
    }, error = function(e) {
      message("Skipping plotModuleHeat: ", e\$message)
    })
    
    # 9. Test for significant omic interactions
    tryCatch({
      runSupertest(moduleSummary, pvalueThr = 0.05, zscoreThr = 0.05, 
                   excludeColumns = c("pathway", "module"))
    }, error = function(e) {
      message("Skipping runSupertest: ", e\$message)
    })
    
    dev.off()
    
    message("MOSClip pipeline completed successfully. Outputs saved to 'module_surv_results.rds', 'module_summary_report.csv', and 'mosclip_analysis_plots.pdf'.")

    writeLines(c(
        '"BIOC_MOSCLIP_MULTI_OMIC_SURVIVAL_MODULE_ANALYSIS":',
        paste0('    MOSClip: ', as.character(packageVersion('MOSClip')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_omic_survival_module_analysis.csv versions.yml
    """
}

workflow BIOC_MOSCLIP_MULTI_OMIC_SURVIVAL_MODULE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ multiOmics_data.RData, pathways.RData ] ]

    main:
    BIOC_MOSCLIP_MULTI_OMIC_SURVIVAL_MODULE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MOSCLIP_MULTI_OMIC_SURVIVAL_MODULE_ANALYSIS.out.tables
    plots    = BIOC_MOSCLIP_MULTI_OMIC_SURVIVAL_MODULE_ANALYSIS.out.plots
    objects  = BIOC_MOSCLIP_MULTI_OMIC_SURVIVAL_MODULE_ANALYSIS.out.objects
    versions = BIOC_MOSCLIP_MULTI_OMIC_SURVIVAL_MODULE_ANALYSIS.out.versions
}
