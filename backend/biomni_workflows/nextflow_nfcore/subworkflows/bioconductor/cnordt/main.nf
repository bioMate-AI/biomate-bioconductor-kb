#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CNORdt — time_course_logic_modeling
// Train and optimize a boolean logic model of a signaling network using time-course experimental data.
// Input: CNOlistPB, modelPB
// Container: quay.io/biocontainers/bioconductor-cnordt:1.52.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CNORdt, CellNOptR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load libraries and data
//  * 2. [Core Analysis] Preprocess the model against the dataset
//  * 3. [Core Analysis] Run genetic algorithm optimization with time-scaling parameters
//  * 4. [Visualization & Output] Plot and visualize the fit of the optimized model
//  * 5. [Visualization & Output] Export the optimized network and scaffold files

nextflow.enable.dsl = 2

process BIOC_CNORDT_TIME_COURSE_LOGIC_MODELING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("CellNOptR", "CNORdt")
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
    
    # 1. Load libraries and data
    library(CellNOptR)
    library(CNORdt)
    
    # Read the user-provided input files from the working directory
    if (file.exists("CNOlistPB.rds")) {
      CNOlistPB <- readRDS("CNOlistPB.rds")
    } else {
      stop("Required input file 'CNOlistPB.rds' not found in the working directory.")
    }
    
    if (file.exists("modelPB.rds")) {
      modelPB <- readRDS("modelPB.rds")
    } else {
      stop("Required input file 'modelPB.rds' not found in the working directory.")
    }
    
    # 2. Preprocess the model against the dataset
    model = preprocessing(CNOlistPB, modelPB)
    initBstring <- rep(1, length(model\$reacID))
    
    # Save preprocessed model
    saveRDS(model, "preprocessed_model.rds")
    
    # 3. Run genetic algorithm optimization with time-scaling parameters
    opt1 <- gaBinaryDT(CNOlist=CNOlistPB, model=model, initBstring=initBstring,
    verbose=FALSE, boolUpdates=10, maxTime=30, lowerB=0.8, upperB=10)
    
    # Save optimization results
    saveRDS(opt1, "optimization_results.rds")
    
    # 4. Plot and visualize the fit of the optimized model
    pdf("optimized_fit_plot.pdf", width=11, height=8)
    cutAndPlotResultsDT(
    	model=model,
    	CNOlist=CNOlistPB,
    	bString=opt1\$bString,
    	plotPDF=FALSE,
    	boolUpdates=10,
    	lowerB=0.8,
    	upperB=10
    )
    dev.off()
    
    # 5. Export the optimized network and scaffold files
    writeScaffold(
    	modelComprExpanded=model,
    	optimResT1=opt1,
    	optimResT2=NA,
    	modelOriginal=modelPB,
    	CNOlist=CNOlistPB
    )
    
    writeNetwork(
    	modelOriginal=modelPB,
    	modelComprExpanded=model,
    	optimResT1=opt1,
    	CNOlist=CNOlistPB
    )

    writeLines(c(
        '"BIOC_CNORDT_TIME_COURSE_LOGIC_MODELING":',
        paste0('    CNORdt: ', as.character(packageVersion('CNORdt')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_time_course_logic_modeling.csv versions.yml
    """
}

workflow BIOC_CNORDT_TIME_COURSE_LOGIC_MODELING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ CNOlistPB, modelPB ] ]

    main:
    BIOC_CNORDT_TIME_COURSE_LOGIC_MODELING(ch_input)

    emit:
    tables   = BIOC_CNORDT_TIME_COURSE_LOGIC_MODELING.out.tables
    plots    = BIOC_CNORDT_TIME_COURSE_LOGIC_MODELING.out.plots
    objects  = BIOC_CNORDT_TIME_COURSE_LOGIC_MODELING.out.objects
    versions = BIOC_CNORDT_TIME_COURSE_LOGIC_MODELING.out.versions
}
