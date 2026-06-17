#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CellNOptR — two_time_point_ga
// Optimize a boolean logic model across two sequential time points to capture slow regulatory mechanisms like negative feedback.
// Input: ToyModel2, CNOlistToy2
// Container: quay.io/biocontainers/bioconductor-cellnoptr:1.56.0--r45h01b2380_0
// R packages: CellNOptR
// Bioconductor: 3.20 | R: 4.4
// Requires: CellNOptR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load two-time-point data and PKN
//  * 2. [Core Analysis] Preprocess the model
//  * 3. [Core Analysis] Optimize the first time point (T1) using gaBinaryT1
//  * 4. [Visualization & Output] Plot T1 fit
//  * 5. [Core Analysis] Optimize the second time point (TN) using gaBinaryTN, passing the T1 optimized bitstring
//  * 6. [Visualization & Output] Plot combined results for both time points

nextflow.enable.dsl = 2

process BIOC_CELLNOPTR_TWO_TIME_POINT_GA {
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
    
    # Load required library
    library(CellNOptR)
    
    # Helper function to safely read the input RDS files
    read_input <- function(filename) {
      if (file.exists(filename)) {
        return(readRDS(filename))
      } else if (file.exists(paste0(filename, ".rds"))) {
        return(readRDS(paste0(filename, ".rds")))
      } else {
        stop(paste("Error: Input file", filename, "not found in the working directory."))
      }
    }
    
    # 1. Load two-time-point data and PKN from user input files
    CNOlistToy2 <- read_input("CNOlistToy2")
    ToyModel2 <- read_input("ToyModel2")
    
    pknmodel = ToyModel2
    cnolist = CNOlist(CNOlistToy2)
    
    # Plot and save the initial CNOlist data
    pdf("CNOlist_data_plot.pdf")
    plot(cnolist)
    dev.off()
    
    # 2. Preprocess the model
    model = preprocessing(cnolist, pknmodel, verbose=FALSE)
    saveRDS(model, "preprocessed_model.rds")
    
    # 3. Optimize the first time point (T1) using gaBinaryT1
    T1opt <- gaBinaryT1(cnolist, model, stallGenMax=10, maxTime=60, verbose=FALSE)
    saveRDS(T1opt, "T1_optimization_results.rds")
    
    # Plot T1 fit simulation (cutAndPlot with plotPDF=TRUE automatically writes a PDF)
    sim <- cutAndPlot(model=model, bStrings=list(T1opt\$bString),
        CNOlist=cnolist, plotPDF=TRUE)
    
    # 4. Plot T1 fit evolution
    pdf("T1_fit_evolution.pdf")
    plotFit(optRes=T1opt)
    dev.off()
    
    # 5. Optimize the second time point (TN) using gaBinaryTN, passing the T1 optimized bitstring
    T2opt<-gaBinaryTN(cnolist, model,  bStrings=list(T1opt\$bString),
        stallGenMax=10, maxTime=60, verbose=FALSE)
    saveRDS(T2opt, "T2_optimization_results.rds")
    
    # 6. Plot combined results for both time points
    res <- cutAndPlot(
        model=model,
        bStrings=list(T1opt\$bString, T2opt\$bString),
        CNOlist=cnolist,
        plotPDF=TRUE, plotParams=list(cex=0.8, cmap_scale=0.5, margin=0.2))
    
    # Export the optimized bitstrings to a CSV file
    results_df <- data.frame(
      Reaction = model\$reacID,
      T1_Active = T1opt\$bString,
      T2_Active = T2opt\$bString
    )
    write.csv(results_df, "optimized_bitstrings.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_CELLNOPTR_TWO_TIME_POINT_GA":',
        paste0('    CellNOptR: ', as.character(packageVersion('CellNOptR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_time_point_ga.csv versions.yml
    """
}

workflow BIOC_CELLNOPTR_TWO_TIME_POINT_GA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ToyModel2, CNOlistToy2 ] ]

    main:
    BIOC_CELLNOPTR_TWO_TIME_POINT_GA(ch_input)

    emit:
    tables   = BIOC_CELLNOPTR_TWO_TIME_POINT_GA.out.tables
    plots    = BIOC_CELLNOPTR_TWO_TIME_POINT_GA.out.plots
    objects  = BIOC_CELLNOPTR_TWO_TIME_POINT_GA.out.objects
    versions = BIOC_CELLNOPTR_TWO_TIME_POINT_GA.out.versions
}
