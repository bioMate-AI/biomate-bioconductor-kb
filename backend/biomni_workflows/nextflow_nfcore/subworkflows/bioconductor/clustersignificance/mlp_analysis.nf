#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ClusterSignificance — mlp_analysis
// Assess class cluster separation in a maximum of 2 dimensions and 2 classes using Mean Line Projection.
// Input: mlpMatrix, classes
// Container: quay.io/biocontainers/bioconductor-clustersignificance:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ClusterSignificance
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Project data onto a regression line using mlp
//  * 2. [Core Analysis] Classify and score the separation using classify
//  * 3. [Core Analysis] Run permutation testing using permute
//  * 4. [Core Analysis] Extract p-values and confidence intervals using pvalue and conf.int

nextflow.enable.dsl = 2

process BIOC_CLUSTERSIGNIFICANCE_MLP_ANALYSIS {
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
    .bm_deps <- c("ClusterSignificance")
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
    library(ClusterSignificance)
    
    # Helper function to read the mlpMatrix input robustly
    read_mlp_matrix <- function() {
      possible_files <- c("mlpMatrix.rds", "mlpMatrix.csv", "mlpMatrix.tsv", "mlpMatrix.txt", "mlpMatrix")
      for (f in possible_files) {
        if (file.exists(f)) {
          if (grepl("\\\\.rds\$", f, ignore.case = TRUE)) {
            return(readRDS(f))
          } else if (grepl("\\\\.csv\$", f, ignore.case = TRUE)) {
            return(as.matrix(read.csv(f, row.names = 1, check.names = FALSE)))
          } else {
            # Try reading as table
            return(as.matrix(read.table(f, header = TRUE, row.names = 1, check.names = FALSE)))
          }
        }
      }
      stop("Required input file 'mlpMatrix' (RDS, CSV, or TXT) not found in the working directory.")
    }
    
    # Helper function to read the classes input robustly
    read_classes_vector <- function() {
      possible_files <- c("classes.rds", "classes.csv", "classes.txt", "classes")
      for (f in possible_files) {
        if (file.exists(f)) {
          if (grepl("\\\\.rds\$", f, ignore.case = TRUE)) {
            return(readRDS(f))
          } else if (grepl("\\\\.csv\$", f, ignore.case = TRUE)) {
            df <- read.csv(f, header = FALSE)
            return(as.character(df[[1]]))
          } else {
            return(readLines(f))
          }
        }
      }
      stop("Required input file 'classes' (RDS, CSV, or TXT) not found in the working directory.")
    }
    
    # 1. Read User Inputs
    mlpMatrix <- read_mlp_matrix()
    classes_input <- read_classes_vector()
    
    # Ensure the matrix rownames match the classes vector to align with the vignette's assumption
    if (length(classes_input) != nrow(mlpMatrix)) {
      stop(paste("Dimension mismatch: 'classes' has length", length(classes_input), 
                 "but 'mlpMatrix' has", nrow(mlpMatrix), "rows."))
    }
    rownames(mlpMatrix) <- classes_input
    
    # 2. Execute Documented Workflow Exactly as Specified
    classes <- rownames(mlpMatrix)
    
    # Stage 1: Project data onto a regression line using mlp
    prj <- mlp(mlpMatrix, classes)
    
    pdf("mlp_projection_plot.pdf")
    plot(prj)
    dev.off()
    
    # Stage 2: Classify and score the separation using classify
    cl <- classify(prj)
    
    pdf("classification_plot.pdf")
    plot(cl)
    dev.off()
    
    # Stage 3: Run permutation testing using permute
    iterations <- 500 
    pe <- permute(
        mat = mlpMatrix, 
        iter = iterations, 
        classes = classes, 
        projmethod = "mlp"
    )
    
    pdf("permutation_plot.pdf")
    plot(pe)
    dev.off()
    
    # Stage 4: Extract p-values and confidence intervals
    p_vals <- pvalue(pe)
    conf_ints <- conf.int(pe)
    
    # 3. Write Meaningful Outputs
    # Save the permutation results object
    saveRDS(pe, "permutation_results.rds")
    
    # Save p-values to CSV
    p_val_df <- data.frame(
      Comparison = names(p_vals),
      P_Value = as.numeric(p_vals),
      stringsAsFactors = FALSE
    )
    write.csv(p_val_df, "pvalue_results.csv", row.names = FALSE)
    
    # Save confidence intervals to CSV
    if (is.matrix(conf_ints) || is.data.frame(conf_ints)) {
      write.csv(as.data.frame(conf_ints), "confidence_intervals.csv", row.names = TRUE)
    } else {
      conf_df <- data.frame(
        Metric = names(conf_ints),
        Value = as.numeric(conf_ints),
        stringsAsFactors = FALSE
      )
      write.csv(conf_df, "confidence_intervals.csv", row.names = FALSE)
    }
    
    cat("Pipeline completed successfully. Outputs written to working directory.\n")

    writeLines(c(
        '"BIOC_CLUSTERSIGNIFICANCE_MLP_ANALYSIS":',
        paste0('    ClusterSignificance: ', as.character(packageVersion('ClusterSignificance')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mlp_analysis.csv versions.yml
    """
}

workflow BIOC_CLUSTERSIGNIFICANCE_MLP_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mlpMatrix, classes ] ]

    main:
    BIOC_CLUSTERSIGNIFICANCE_MLP_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CLUSTERSIGNIFICANCE_MLP_ANALYSIS.out.tables
    plots    = BIOC_CLUSTERSIGNIFICANCE_MLP_ANALYSIS.out.plots
    objects  = BIOC_CLUSTERSIGNIFICANCE_MLP_ANALYSIS.out.objects
    versions = BIOC_CLUSTERSIGNIFICANCE_MLP_ANALYSIS.out.versions
}
