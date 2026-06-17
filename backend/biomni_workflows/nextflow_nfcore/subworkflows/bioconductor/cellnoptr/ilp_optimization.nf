#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CellNOptR — ilp_optimization
// Train a PKN to perturbation data using Integer Linear Programming (ILP) to retrieve multiple alternative sparse optimal solutions.
// Input: ToyModel, CNOlistToy
// Container: quay.io/biocontainers/bioconductor-cellnoptr:1.56.0--r45h01b2380_0
// R packages: CellNOptR
// Bioconductor: 3.20 | R: 4.4
// Requires: CellNOptR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load data and PKN
//  * 2. [Core Analysis] Preprocess the network
//  * 3. [Core Analysis] Run ILP optimization using ilpBinaryT1 with a specified CPLEX path
//  * 4. [Visualization & Output] Plot and visualize the alternative optimized models and fits

nextflow.enable.dsl = 2

process BIOC_CELLNOPTR_ILP_OPTIMIZATION {
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
    .bm_deps <- c("CellNOptR")
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
    library(CellNOptR)
    
    # 1. Load data and PKN from the working directory
    read_input_rds <- function(filename) {
      if (file.exists(filename)) {
        return(readRDS(filename))
      } else if (file.exists(paste0(filename, ".rds"))) {
        return(readRDS(paste0(filename, ".rds")))
      } else {
        stop("Required input file not found: ", filename)
      }
    }
    
    ToyModel <- read_input_rds("ToyModel")
    CNOlistToy <- read_input_rds("CNOlistToy")
    
    pknmodel = ToyModel
    cnolist = CNOlist(CNOlistToy)
    
    # 2. Preprocess the network
    model = preprocessing(cnolist, pknmodel)
    
    # 3. Run ILP optimization using ilpBinaryT1 with a specified CPLEX path
    # Retrieve CPLEX path from environment variable if set, otherwise use default placeholder
    cplexPath = Sys.getenv("CPLEX_PATH", "path/to/cplex")
    
    resILP <- tryCatch({
      message("Running ILP optimization using CPLEX at: ", cplexPath)
      ilpBinaryT1(cnolist = cnolist, model = model,
                  numSolutions = 3, relGap = 0.05,
                  cplexPath = cplexPath)
    }, error = function(e) {
      warning("ILP optimization failed. This workflow requires a valid IBM-CPLEX installation and license.\nError details: ", e\$message)
      NULL
    })
    
    # 4. Plot and visualize the alternative optimized models and fits (if optimization succeeded)
    if (!is.null(resILP)) {
      # Save the raw optimization results
      saveRDS(resILP, "resILP.rds")
      
      # Export the retrieved bitstrings to a CSV file
      bitstrings_df <- data.frame(
        Solution = 1:length(resILP\$bitstringILP),
        Bitstring = sapply(resILP\$bitstringILP, function(x) paste(x, collapse = ", "))
      )
      write.csv(bitstrings_df, "ILP_solutions_bitstrings.csv", row.names = FALSE)
      
      # Generate plots for Solution 1
      if (length(resILP\$bitstringILP) >= 1) {
        pdf("ILP_solution_1_plots.pdf", width = 10, height = 8)
        cutAndPlot(CNOlist = cnolist, model = model, bStrings = list(resILP\$bitstringILP[[1]]))
        plotModel(model, cnolist, bString=resILP\$bitstringILP[[1]])
        dev.off()
      }
      
      # Generate plots for Solution 2
      if (length(resILP\$bitstringILP) >= 2) {
        pdf("ILP_solution_2_plots.pdf", width = 10, height = 8)
        cutAndPlot(CNOlist = cnolist, model = model, bStrings = list(resILP\$bitstringILP[[2]]))
        plotModel(model, cnolist, bString=resILP\$bitstringILP[[2]])
        dev.off()
      }
      
      # Generate plots for Solution 3
      if (length(resILP\$bitstringILP) >= 3) {
        pdf("ILP_solution_3_plots.pdf", width = 10, height = 8)
        cutAndPlot(CNOlist = cnolist, model = model, bStrings = list(resILP\$bitstringILP[[3]]))
        plotModel(model, cnolist, bString=resILP\$bitstringILP[[3]])
        dev.off()
      }
      
      message("Pipeline completed successfully. Outputs written to 'resILP.rds', 'ILP_solutions_bitstrings.csv', and PDF plot files.")
    } else {
      message("Pipeline finished with warnings. No optimization outputs were generated because CPLEX was unavailable.")
    }

    writeLines(c(
        '"BIOC_CELLNOPTR_ILP_OPTIMIZATION":',
        paste0('    CellNOptR: ', as.character(packageVersion('CellNOptR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ilp_optimization.csv versions.yml
    """
}

workflow BIOC_CELLNOPTR_ILP_OPTIMIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ToyModel, CNOlistToy ] ]

    main:
    BIOC_CELLNOPTR_ILP_OPTIMIZATION(ch_input)

    emit:
    tables   = BIOC_CELLNOPTR_ILP_OPTIMIZATION.out.tables
    plots    = BIOC_CELLNOPTR_ILP_OPTIMIZATION.out.plots
    objects  = BIOC_CELLNOPTR_ILP_OPTIMIZATION.out.objects
    versions = BIOC_CELLNOPTR_ILP_OPTIMIZATION.out.versions
}
