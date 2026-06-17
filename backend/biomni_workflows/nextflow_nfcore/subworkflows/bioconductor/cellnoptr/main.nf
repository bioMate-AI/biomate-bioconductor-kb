#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CellNOptR — single_time_point_ga
// Perform boolean logic network optimization for a single time-point dataset using a genetic algorithm.
// Input: ToyPKNMMB.sif, ToyDataMMB.csv
// Container: quay.io/biocontainers/bioconductor-cellnoptr:1.56.0--r45h01b2380_0
// R packages: CellNOptR, doParallel, stringr
// Bioconductor: 3.20 | R: 4.4
// Requires: CellNOptR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load perturbation data and convert to CNOlist
//  * 2. [Input & Preparation] Load prior knowledge network
//  * 3. [Core Analysis] Check compatibility between data and network
//  * 4. [Core Analysis] Preprocess the model (cut non-observable/non-controllable nodes, compress, and expand gates)
//  * 5. [Core Analysis] Compute residual error
//  * 6. [Core Analysis] Run genetic algorithm optimization
//  * 7. [Visualization & Output] Plot results and fit
//  * 8. [Core Analysis] Map back optimized model to PKN
//  * 9. [Visualization & Output] Write results and generate HTML report

nextflow.enable.dsl = 2

process BIOC_CELLNOPTR_SINGLE_TIME_POINT_GA {
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
    .bm_deps <- c("CellNOptR", "doParallel", "stringr")
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
    
    # Verify that the required user input files exist in the working directory
    if (!file.exists("ToyDataMMB.csv")) {
        stop("Error: Input file 'ToyDataMMB.csv' not found in the working directory.")
    }
    if (!file.exists("ToyPKNMMB.sif")) {
        stop("Error: Input file 'ToyPKNMMB.sif' not found in the working directory.")
    }
    
    # 1. Load perturbation data and convert to CNOlist
    dataToy <- readMIDAS("ToyDataMMB.csv", verbose=FALSE)
    CNOlistToy <- makeCNOlist(dataToy, subfield=FALSE, verbose=FALSE)
    
    # 2. Load prior knowledge network
    pknmodel <- readSIF("ToyPKNMMB.sif")
    
    # 3. Check compatibility between data and network
    checkSignals(CNOlistToy, pknmodel)
    
    # Generate the initial ToyModelGraph.pdf required for the final report
    pdf("ToyModelGraph.pdf")
    plotModel(pknmodel, CNOlistToy)
    dev.off()
    
    # 4. Preprocess the model (cut non-observable/non-controllable nodes, compress, and expand gates)
    model <- preprocessing(CNOlistToy, pknmodel, expansion=TRUE,
        compression=TRUE, cutNONC=TRUE, verbose=FALSE)
    
    # 5. Compute residual error
    resECNOlistToy <- residualError(CNOlistToy)
    
    # 6. Run genetic algorithm optimization
    initBstring <- rep(1, length(model\$reacID))
    ToyT1opt <- gaBinaryT1(CNOlist=CNOlistToy, model=model,
        initBstring=initBstring, verbose=FALSE)
    
    # 7. Plot results and fit
    # This call generates "SimResultsT1_1.pdf" automatically when plotPDF=TRUE
    cutAndPlot(model=model, bStrings=list(ToyT1opt\$bString),
        CNOlist=CNOlistToy, plotPDF=TRUE)
    
    # Generate the evolFitToyT1.pdf required for the final report
    pdf("evolFitToyT1.pdf")
    plotFit(optRes=ToyT1opt)
    dev.off()
    
    # Plot the optimized model structure
    pdf("ToyModel_optimized.pdf")
    plotModel(model, CNOlistToy, bString=ToyT1opt\$bString)
    dev.off()
    
    # 8. Map back optimized model to PKN
    bs <- mapBack(model, pknmodel, ToyT1opt\$bString)
    
    pdf("ToyModel_mapped.pdf")
    plotModel(pknmodel, CNOlistToy, bs, compressed=model\$speciesCompressed)
    dev.off()
    
    # 9. Write results and generate HTML report
    writeScaffold(
        modelComprExpanded=model,
        optimResT1=ToyT1opt,
        optimResT2=NA,
        modelOriginal=pknmodel,
        CNOlist=CNOlistToy)
    
    writeNetwork(
        modelOriginal=pknmodel,
        modelComprExpanded=model,
        optimResT1=ToyT1opt,
        optimResT2=NA,
        CNOlist=CNOlistToy)
    
    namesFilesToy <- list(
        dataPlot="ToyModelGraph.pdf",
        evolFitT1="evolFitToyT1.pdf",
        evolFitT2=NA,
        simResultsT1="SimResultsT1_1.pdf",
        simResultsT2=NA,
        scaffold="Scaffold.sif",
        scaffoldDot="Scaffold.dot",
        tscaffold="TimesScaffold.EA",
        wscaffold="weightsScaffold.EA",
        PKN="PKN.sif",
        PKNdot="PKN.dot",
        wPKN="TimesPKN.EA",
        nPKN="nodesPKN.NA")
    
    writeReport(
        modelOriginal=pknmodel,
        modelOpt=model,
        optimResT1=ToyT1opt,
        optimResT2=NA,
        CNOlist=CNOlistToy,
        directory="testToy",
        namesFiles=namesFilesToy,
        namesData=list(CNOlist="Toy", model="ToyModel"))
    
    # Save key outputs as RDS objects for downstream analysis
    saveRDS(CNOlistToy, file="CNOlistToy.rds")
    saveRDS(model, file="processed_model.rds")
    saveRDS(ToyT1opt, file="ToyT1opt.rds")
    saveRDS(bs, file="mapped_back_bitstring.rds")
    
    cat("Pipeline completed successfully. Outputs written to 'testToy' directory and working directory.\n")

    writeLines(c(
        '"BIOC_CELLNOPTR_SINGLE_TIME_POINT_GA":',
        paste0('    CellNOptR: ', as.character(packageVersion('CellNOptR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_time_point_ga.csv versions.yml
    """
}

workflow BIOC_CELLNOPTR_SINGLE_TIME_POINT_GA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ToyPKNMMB.sif, ToyDataMMB.csv ] ]

    main:
    BIOC_CELLNOPTR_SINGLE_TIME_POINT_GA(ch_input)

    emit:
    tables   = BIOC_CELLNOPTR_SINGLE_TIME_POINT_GA.out.tables
    plots    = BIOC_CELLNOPTR_SINGLE_TIME_POINT_GA.out.plots
    objects  = BIOC_CELLNOPTR_SINGLE_TIME_POINT_GA.out.objects
    versions = BIOC_CELLNOPTR_SINGLE_TIME_POINT_GA.out.versions
}
