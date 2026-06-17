#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: STATegRa — holistic_differential_expression
// Identify genes that are differentially expressed or associated with an outcome across multiple omics modalities using Non-Parametric Combination (NPC).
// Input: TCGA_BRCA_Data
// Container: quay.io/biocontainers/bioconductor-stategra:1.46.0--r45hdfd78af_0
// R packages: Biobase, STATegRa
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, STATegRa
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define data types for each modality (e.g., "count", "continuous")
//  * 2. [Core Analysis] Specify combining methods (e.g., "Fisher", "Liptak", "Tippett")
//  * 3. [Core Analysis] Set permutation parameters (numPerms, numCores, verbose)
//  * 4. [Core Analysis] Run the holistic association analysis using omicsNPC

nextflow.enable.dsl = 2

process BIOC_STATEGRA_HOLISTIC_DIFFERENTIAL_EXPRESSION {
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
    .bm_deps <- c("Biobase", "STATegRa")
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
    library(STATegRa)
    library(Biobase)
    
    # ==========================================
    # 1. Load User Input
    # ==========================================
    # The pipeline expects 'TCGA_BRCA_Data' in the working directory.
    # We handle multiple potential formats (RDS, RData, or extensionless files).
    input_file <- "TCGA_BRCA_Data"
    TCGA_BRCA_Data <- NULL
    
    if (file.exists(input_file)) {
      TCGA_BRCA_Data <- tryCatch({
        readRDS(input_file)
      }, error = function(e) {
        env <- new.env()
        load(input_file, envir = env)
        if (exists("TCGA_BRCA_Data", envir = env)) {
          env\$TCGA_BRCA_Data
        } else {
          env[[names(env)[1]]]
        }
      })
    } else if (file.exists(paste0(input_file, ".rds"))) {
      TCGA_BRCA_Data <- readRDS(paste0(input_file, ".rds"))
    } else if (file.exists(paste0(input_file, ".RData"))) {
      env <- new.env()
      load(paste0(input_file, ".RData"), envir = env)
      if (exists("TCGA_BRCA_Data", envir = env)) {
        TCGA_BRCA_Data <- env\$TCGA_BRCA_Data
      } else {
        TCGA_BRCA_Data <- env[[names(env)[1]]]
      }
    } else {
      stop("Error: Required input file 'TCGA_BRCA_Data' (RDS or RData format) not found in the working directory.")
    }
    
    # Verify that the loaded object is a list of ExpressionSets
    if (!is.list(TCGA_BRCA_Data) || !all(sapply(TCGA_BRCA_Data, inherits, "ExpressionSet"))) {
      stop("Error: Loaded 'TCGA_BRCA_Data' must be a list of ExpressionSet objects.")
    }
    
    # ==========================================
    # 2. Run Documented Workflow
    # ==========================================
    
    # Stage 1: Define data types for each modality
    dataTypes <- c("count", "count", "continuous")
    
    # Stage 2: Specify combining methods
    combMethods <- c("Fisher", "Liptak", "Tippett")
    
    # Stage 3: Set permutation parameters
    numPerms <- 1000
    numCores <- 1
    verbose <- TRUE
    
    # Stage 4: Run the holistic association analysis using omicsNPC
    results <- omicsNPC(dataInput=TCGA_BRCA_Data, dataTypes=dataTypes,
                        combMethods=combMethods, numPerms=numPerms,
                        numCores=numCores, verbose=verbose)
    
    # ==========================================
    # 3. Save Outputs
    # ==========================================
    
    # Save the complete results object as an RDS file
    saveRDS(results, "omicsNPC_results.rds")
    
    # Export p-values and statistics to CSV files if available
    if (is.list(results)) {
      if ("pvalues" %in% names(results)) {
        write.csv(results\$pvalues, "omicsNPC_pvalues.csv", row.names = TRUE)
        
        # Generate a PDF plot of the p-value distributions
        pdf("omicsNPC_pvalue_histograms.pdf", width = 10, height = 8)
        pvals <- results\$pvalues
        num_cols <- ncol(pvals)
        grid_dim <- ceiling(sqrt(num_cols))
        par(mfrow = c(grid_dim, grid_dim))
        for (col in colnames(pvals)) {
          hist(pvals[, col], 
               main = paste("P-values:", col), 
               xlab = "p-value", 
               col = "lightblue", 
               breaks = 20, 
               xlim = c(0, 1))
        }
        dev.off()
      }
      
      if ("statistics" %in% names(results)) {
        write.csv(results\$statistics, "omicsNPC_statistics.csv", row.names = TRUE)
      }
    }

    writeLines(c(
        '"BIOC_STATEGRA_HOLISTIC_DIFFERENTIAL_EXPRESSION":',
        paste0('    STATegRa: ', as.character(packageVersion('STATegRa')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_holistic_differential_expression.csv versions.yml
    """
}

workflow BIOC_STATEGRA_HOLISTIC_DIFFERENTIAL_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ TCGA_BRCA_Data ] ]

    main:
    BIOC_STATEGRA_HOLISTIC_DIFFERENTIAL_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_STATEGRA_HOLISTIC_DIFFERENTIAL_EXPRESSION.out.tables
    plots    = BIOC_STATEGRA_HOLISTIC_DIFFERENTIAL_EXPRESSION.out.plots
    objects  = BIOC_STATEGRA_HOLISTIC_DIFFERENTIAL_EXPRESSION.out.objects
    versions = BIOC_STATEGRA_HOLISTIC_DIFFERENTIAL_EXPRESSION.out.versions
}
