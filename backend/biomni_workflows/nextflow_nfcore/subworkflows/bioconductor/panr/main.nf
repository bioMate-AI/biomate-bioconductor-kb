#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PANR — pan_inference_and_module_search
// Infer a posterior association network and search for enriched functional gene modules from rich phenotypic screening data.
// Input: Bakal2007, Bakal2007Cluster
// Container: quay.io/biocontainers/bioconductor-panr:1.56.0--r45hdfd78af_0
// R packages: PANR, pvclust, RedeR
// Bioconductor: 3.20 | R: 4.4
// Requires: PANR, RedeR, pvclust
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Input Files
//  * 2. [Visualization & Output] Execute PANR Workflow
//  * 3. [Visualization & Output] Save Outputs

nextflow.enable.dsl = 2

process BIOC_PANR_PAN_INFERENCE_AND_MODULE_SEARCH {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("PANR", "pvclust", "RedeR")
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
    library(PANR)
    library(pvclust)
    library(RedeR)
    
    # ==========================================
    # --- Read User Input Files ---
    # ==========================================
    
    # Read Bakal2007 phenotype matrix
    if (file.exists("Bakal2007")) {
      Bakal2007 <- tryCatch(readRDS("Bakal2007"), error = function(e) {
        as.matrix(read.table("Bakal2007", header = TRUE, row.names = 1))
      })
    } else if (file.exists("Bakal2007.rds")) {
      Bakal2007 <- readRDS("Bakal2007.rds")
    } else if (file.exists("Bakal2007.csv")) {
      Bakal2007 <- as.matrix(read.csv("Bakal2007.csv", row.names = 1))
    } else {
      stop("Required input file 'Bakal2007' not found in the working directory.")
    }
    
    # Read Bakal2007Cluster node color/clustering information
    if (file.exists("Bakal2007Cluster")) {
      Bakal2007Cluster <- tryCatch(readRDS("Bakal2007Cluster"), error = function(e) {
        read.table("Bakal2007Cluster", header = TRUE, row.names = 1)
      })
    } else if (file.exists("Bakal2007Cluster.rds")) {
      Bakal2007Cluster <- readRDS("Bakal2007Cluster.rds")
    } else if (file.exists("Bakal2007Cluster.csv")) {
      Bakal2007Cluster <- read.csv("Bakal2007Cluster.csv", row.names = 1)
    } else {
      stop("Required input file 'Bakal2007Cluster' not found in the working directory.")
    }
    
    # Extract nodeColor vector from Bakal2007Cluster
    if (is.list(Bakal2007Cluster) && "nodeColor" %in% names(Bakal2007Cluster)) {
      nodeColor <- Bakal2007Cluster\$nodeColor
    } else if (is.data.frame(Bakal2007Cluster)) {
      if ("nodeColor" %in% colnames(Bakal2007Cluster)) {
        nodeColor <- setNames(Bakal2007Cluster\$nodeColor, rownames(Bakal2007Cluster))
      } else {
        nodeColor <- setNames(Bakal2007Cluster[[1]], rownames(Bakal2007Cluster))
      }
    } else {
      nodeColor <- Bakal2007Cluster
    }
    
    # ==========================================
    # --- Execute PANR Workflow ---
    # ==========================================
    
    # Initialize BetaMixture object
    bm1 <- new("BetaMixture", pheno = Bakal2007, metric = "cosine", 
               model = "global", order = 1)
    
    # Fit NULL distribution
    bm1 <- fitNULL(bm1, nPerm = 10, thetaNULL = c(alphaNULL = 4, betaNULL = 4),
                   sumMethod = "median", permMethod = "all", verbose = TRUE)
    
    # Fit Beta-Mixture model
    bm1 <- fitBM(bm1, para = list(zInit = NULL, thetaInit = c(alphaNeg = 2, 
                 betaNeg = 4, alphaNULL = bm1@result\$fitNULL\$thetaNULL[["alphaNULL"]], 
                 betaNULL = bm1@result\$fitNULL\$thetaNULL[["betaNULL"]], 
                 alphaPos = 4, betaPos = 2), gamma = NULL), 
                 ctrl = list(fitNULL = FALSE, tol = 1e-1), verbose = TRUE, gradtol = 1e-3)
    
    # Save fitting plots to PDF
    pdf("fitNULL_plot.pdf")
    view(bm1, "fitNULL")
    dev.off()
    
    pdf("fitBM_plot.pdf")
    view(bm1, "fitBM")
    dev.off()
    
    # Save BetaMixture summary
    sink("bm1_summary.txt")
    summarize(bm1, what = "ALL")
    sink()
    
    # Initialize PAN object and infer network
    pan <- new("PAN", bm1 = bm1)
    pan <- infer(pan, para = list(type = "SNR", log = TRUE, sign = TRUE, 
                 cutoff = log(5)), filter = FALSE, verbose = TRUE)
    
    # Build PAN network
    pan <- buildPAN(pan, engine = "RedeR", 
                    para = list(nodeColor = nodeColor, hideNeg = TRUE))
    
    # View PAN graph (wrapped in tryCatch as RedeR requires an active Java server)
    tryCatch({
      viewPAN(pan, what = "graph")
    }, error = function(e) {
      message("RedeR viewPAN (graph) skipped or failed: ", e\$message)
    })
    
    # Search for significant gene modules using multiscale bootstrap resampling
    pan <- pvclustModule(pan, nboot = 1000, metric = "cosine", hclustMethod =
                         "average", filter = TRUE, verbose = TRUE, r = c(5:12/7))
    
    # Identify significant modules
    inds <- sigModules(pan, pValCutoff = 0.01, minSize = 3, 
                       maxSize = 100, sortby = "pval", decreasing = FALSE)
    
    # View significant modules
    tryCatch({
      viewPAN(pan, what = "pvclustModule", moduleID = inds)
    }, error = function(e) {
      message("RedeR viewPAN (pvclustModule) skipped or failed: ", e\$message)
    })
    
    # View nested modules
    tryCatch({
      viewNestedModules(pan, pValCutoff = 0.05, minSize = 3, maxSize = 100)
    }, error = function(e) {
      message("RedeR viewNestedModules skipped or failed: ", e\$message)
    })
    
    # Save PAN summary
    sink("pan_summary.txt")
    summarize(pan, what = "graph")
    sink()
    
    # ==========================================
    # --- Save Outputs ---
    # ==========================================
    saveRDS(bm1, "bm1_fitted.rds")
    saveRDS(pan, "pan_results.rds")
    saveRDS(inds, "significant_modules.rds")
    
    if (is.list(inds)) {
      sink("significant_modules_list.txt")
      print(inds)
      sink()
    }
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_PANR_PAN_INFERENCE_AND_MODULE_SEARCH":',
        paste0('    PANR: ', as.character(packageVersion('PANR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pan_inference_and_module_search.csv versions.yml
    """
}

workflow BIOC_PANR_PAN_INFERENCE_AND_MODULE_SEARCH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Bakal2007, Bakal2007Cluster ] ]

    main:
    BIOC_PANR_PAN_INFERENCE_AND_MODULE_SEARCH(ch_input)

    emit:
    tables   = BIOC_PANR_PAN_INFERENCE_AND_MODULE_SEARCH.out.tables
    plots    = BIOC_PANR_PAN_INFERENCE_AND_MODULE_SEARCH.out.plots
    objects  = BIOC_PANR_PAN_INFERENCE_AND_MODULE_SEARCH.out.objects
    versions = BIOC_PANR_PAN_INFERENCE_AND_MODULE_SEARCH.out.versions
}
