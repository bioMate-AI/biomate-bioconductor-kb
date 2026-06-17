#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: survcomp — performance_comparison_meta_analysis
// Statistically compare the concordance indices of different risk predictors across multiple datasets using meta-analysis.
// Input: Concordance index objects computed for multiple genes across multiple datasets.
// Container: quay.io/biocontainers/bioconductor-survcomp:1.60.0--r45ha27e39d_0
// R packages: Biobase, rmeta, survcomp
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, rmeta, survcomp
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute concordance index objects for each gene in each dataset using concordance.index
//  * 2. [Input & Preparation] Construct lists of concordance index objects for the two predictors to be compared
//  * 3. [Core Analysis] Compare the lists of concordance indices across datasets using cindex.comp.meta

nextflow.enable.dsl = 2

process BIOC_SURVCOMP_PERFORMANCE_COMPARISON_META_ANALYSIS {
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
    .bm_deps <- c("Biobase", "rmeta", "survcomp")
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
    library(survcomp)
    library(Biobase)
    library(rmeta)
    library(grid)
    
    # Check for required user input files in the working directory
    input_file_mainz <- "cindex_mainz.rds"
    input_file_transbig <- "cindex_transbig.rds"
    
    if (!file.exists(input_file_mainz) || !file.exists(input_file_transbig)) {
      stop(paste("Error: Missing required input files in the working directory.",
                 "Please ensure 'cindex_mainz.rds' and 'cindex_transbig.rds' are present.",
                 "These files should contain ExpressionSet objects or lists with 'exprs' and 'pData'."))
    }
    
    # Read the user input files
    mainz_input <- readRDS(input_file_mainz)
    transbig_input <- readRDS(input_file_transbig)
    
    # Robustly construct ExpressionSet objects from the input
    if (inherits(mainz_input, "ExpressionSet")) {
      mainz7g <- mainz_input
    } else if (is.list(mainz_input) && !is.null(mainz_input\$exprs) && !is.null(mainz_input\$pData)) {
      mainz7g <- Biobase::ExpressionSet(
        assayData = as.matrix(mainz_input\$exprs),
        phenoData = Biobase::AnnotatedDataFrame(as.data.frame(mainz_input\$pData))
      )
    } else {
      stop("Input 'cindex_mainz.rds' must be an ExpressionSet or a list containing 'exprs' and 'pData'.")
    }
    
    if (inherits(transbig_input, "ExpressionSet")) {
      transbig7g <- transbig_input
    } else if (is.list(transbig_input) && !is.null(transbig_input\$exprs) && !is.null(transbig_input\$pData)) {
      transbig7g <- Biobase::ExpressionSet(
        assayData = as.matrix(transbig_input\$exprs),
        phenoData = Biobase::AnnotatedDataFrame(as.data.frame(transbig_input\$pData))
      )
    } else {
      stop("Input 'cindex_transbig.rds' must be an ExpressionSet or a list containing 'exprs' and 'pData'.")
    }
    
    # Extract gene symbols/names
    gsList <- rownames(Biobase::exprs(mainz7g))
    if (is.null(gsList)) {
      gsList <- paste0("Gene", 1:nrow(Biobase::exprs(mainz7g)))
    }
    num_genes <- length(gsList)
    
    # Extract survival data dynamically to support generic user-provided data
    extract_surv_data <- function(pd) {
      cnames <- tolower(colnames(pd))
      
      time_idx <- which(cnames %in% c("time", "surv.time", "surv_time", "t.dmfs", "t.rfs", "os.time", "survival_time"))[1]
      if (is.na(time_idx)) {
        num_cols <- which(sapply(pd, is.numeric))
        time_idx <- if (length(num_cols) > 0) num_cols[1] else 1
      }
      
      event_idx <- which(cnames %in% c("event", "surv.event", "surv_event", "e.dmfs", "e.rfs", "os.event", "status", "survival_status"))[1]
      if (is.na(event_idx)) {
        num_cols <- which(sapply(pd, is.numeric))
        event_idx <- if (length(num_cols) > 1) num_cols[2] else 2
      }
      
      list(time = pd[[time_idx]], event = pd[[event_idx]])
    }
    
    mainz_surv <- extract_surv_data(pData(mainz7g))
    transbig_surv <- extract_surv_data(pData(transbig7g))
    
    # Stage 1: Compute concordance index objects for each gene in each dataset using concordance.index
    cindexMetaMainz <- t(apply(X=exprs(mainz7g), MARGIN=1, function(x, y, z) { 
      tt <- concordance.index(x=x, surv.time=y, surv.event=z, method="noether", na.rm=TRUE); 
      return(tt); 
    }, y=mainz_surv\$time, z=mainz_surv\$event))
    
    cindexMetaTransbig <- t(apply(X=exprs(transbig7g), MARGIN=1, function(x, y, z) { 
      tt <- concordance.index(x=x, surv.time=y, surv.event=z, method="noether", na.rm=TRUE); 
      return(tt); 
    }, y=transbig_surv\$time, z=transbig_surv\$event))
    
    # Stages 2 & 3: Construct lists of concordance index objects and compare them using cindex.comp.meta
    ccmData <- NULL
    for (i in 1:num_genes) {
      tt <- NULL
      for (j in 1:num_genes) {
        # Construct lists of concordance index objects for the two predictors to be compared
        listOne <- list("mainz" = cindexMetaMainz[[i]], "transbig" = cindexMetaTransbig[[i]])
        listTwo <- list("mainz" = cindexMetaMainz[[j]], "transbig" = cindexMetaTransbig[[j]])
        
        # Compare the lists of concordance indices across datasets using cindex.comp.meta
        rr <- cindex.comp.meta(list.cindex1=listOne, list.cindex2=listTwo)
        tt <- cbind(tt, rr\$p.value)
      }
      ccmData <- rbind(ccmData, tt)
    }
    
    # Format the comparison matrix
    ccmData <- as.data.frame(ccmData)
    colnames(ccmData) <- gsList
    rownames(ccmData) <- gsList
    
    # Write the comparison matrix to CSV and RDS
    write.csv(ccmData, "cindex_comparison_matrix.csv", row.names = TRUE)
    saveRDS(ccmData, "cindex_comparison_results.rds")
    
    # Combine concordance indices across datasets for visualization
    combined_cindices <- as.data.frame(NULL)
    for (i in 1:num_genes) {
      combined_cindices <- rbind(
        combined_cindices,
        combine.est(
          x = cbind(cindexMetaMainz[[i]]\$c.index, cindexMetaTransbig[[i]]\$c.index),
          x.se = cbind(cindexMetaMainz[[i]]\$se, cindexMetaTransbig[[i]]\$se),
          na.rm = TRUE
        )
      )
    }
    combined_cindices\$lower <- combined_cindices\$estimate + qnorm(0.025, lower.tail=TRUE) * combined_cindices\$se
    combined_cindices\$upper <- combined_cindices\$estimate + qnorm(0.025, lower.tail=FALSE) * combined_cindices\$se
    rownames(combined_cindices) <- gsList
    colnames(combined_cindices) <- c("cindex", "cindex.se", "lower", "upper")
    
    write.csv(combined_cindices, "combined_concordance_indices.csv", row.names = TRUE)
    
    # Generate Forest Plot of the combined concordance indices
    pdf("concordance_index_forestplot.pdf", width = 7, height = 5)
    labeltext <- cbind(c("Gene Symbol", gsList), c(rep(" ", num_genes + 1)))
    bs <- rep(0.5, nrow(labeltext))
    r.mean <- c(NA, combined_cindices\$cindex)
    r.lower <- c(NA, combined_cindices\$lower)
    r.upper <- c(NA, combined_cindices\$upper)
    
    forestplot.surv(
      labeltext = labeltext, 
      mean = r.mean, 
      lower = r.lower, 
      upper = r.upper, 
      zero = 0.5,
      align = c("l"), 
      graphwidth = grid::unit(2, "inches"), 
      x.ticks = seq(0.4, 0.8, 0.05), 
      xlab = "Combined Concordance Index",
      col = rmeta::meta.colors(box="royalblue", line="darkblue", zero="darkred"), 
      box.size = bs, 
      clip = c(0.3, 1.0)
    )
    dev.off()
    
    cat("Pipeline completed successfully. Outputs written:\n")
    cat("- cindex_comparison_matrix.csv\n")
    cat("- cindex_comparison_results.rds\n")
    cat("- combined_concordance_indices.csv\n")
    cat("- concordance_index_forestplot.pdf\n")

    writeLines(c(
        '"BIOC_SURVCOMP_PERFORMANCE_COMPARISON_META_ANALYSIS":',
        paste0('    survcomp: ', as.character(packageVersion('survcomp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_performance_comparison_meta_analysis.csv versions.yml
    """
}

workflow BIOC_SURVCOMP_PERFORMANCE_COMPARISON_META_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Concordance index objects computed for multiple genes across multiple datasets. ] ]

    main:
    BIOC_SURVCOMP_PERFORMANCE_COMPARISON_META_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SURVCOMP_PERFORMANCE_COMPARISON_META_ANALYSIS.out.tables
    plots    = BIOC_SURVCOMP_PERFORMANCE_COMPARISON_META_ANALYSIS.out.plots
    objects  = BIOC_SURVCOMP_PERFORMANCE_COMPARISON_META_ANALYSIS.out.objects
    versions = BIOC_SURVCOMP_PERFORMANCE_COMPARISON_META_ANALYSIS.out.versions
}
