#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CNORfuzzy — constrained_fuzzy_logic_training
// Train a prior knowledge network to quantitative experimental data using constrained fuzzy logic over multiple optimization runs, select an optimal reduction thr
// Input: CNOlistDREAM, DreamModel
// Container: quay.io/biocontainers/bioconductor-cnorfuzzy:1.52.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CNORfuzzy, CellNOptR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Initialize default fuzzy parameters using defaultParametersFuzzy. 2. Customize Genetic Algorithm, Hill transfer function (Type 1 a

nextflow.enable.dsl = 2

process BIOC_CNORFUZZY_CONSTRAINED_FUZZY_LOGIC_TRAINING {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(CNORfuzzy)
    library(CellNOptR)
    
    # Helper function to read input objects from the working directory
    read_input_object <- function(name) {
      possible_files <- c(
        name,
        paste0(name, ".rds"),
        paste0(name, ".RDS"),
        paste0(name, ".RData"),
        paste0(name, ".rdata")
      )
      for (f in possible_files) {
        if (file.exists(f)) {
          if (grepl("\\\\.RData\$|\\\\.rdata\$", f, ignore.case = TRUE)) {
            tmp_env <- new.env()
            load(f, envir = tmp_env)
            vars <- ls(envir = tmp_env)
            if (length(vars) > 0) {
              return(tmp_env[[vars[1]]])
            }
          } else {
            return(readRDS(f))
          }
        }
      }
      stop(paste("Error: Input file for", name, "not found in the working directory."))
    }
    
    # Load user inputs
    CNOlistDREAM <- read_input_object("CNOlistDREAM")
    DreamModel <- read_input_object("DreamModel")
    
    # Ensure CNOlistDREAM is a CNOlist object
    if (!inherits(CNOlistDREAM, "CNOlist")) {
      CNOlistDREAM <- CNOlist(CNOlistDREAM)
    }
    
    # Initialize default fuzzy parameters
    paramsList = defaultParametersFuzzy(CNOlistDREAM, DreamModel)
    
    # Customize Genetic Algorithm parameters
    paramsList\$popSize      = 50
    paramsList\$maxTime      = 5*60
    paramsList\$maxGens      = 200
    paramsList\$stallGenMax  = 50
    paramsList\$verbose      = FALSE
    
    # Default Fuzzy Logic Type1 parameters (Hill transfer functions)
    nrow = 7
    paramsList\$type1Funs = matrix(data = NaN,nrow=nrow,ncol=3)
    paramsList\$type1Funs[,1] = 1
    paramsList\$type1Funs[,2] = c(3, 3, 3, 3, 3, 3, 1.01)
    paramsList\$type1Funs[,3] = c(0.2, 0.3, 0.4, 0.55, 0.72,1.03, 68.5098)
    
    # Default Fuzzy Logic Type2 parameters
    nrow = 7
    paramsList\$type2Funs = matrix(data = NaN,nrow=nrow,ncol=3)
    paramsList\$type2Funs[,1] = seq(from=0.2, to=0.8, length=nrow)
    paramsList\$type2Funs[,2] = 1
    paramsList\$type2Funs[,3] = 1
    
    paramsList\$redThres = c(0, 0.0001, 0.0005, 0.001,  0.003, 0.005, 0.01)
    
    paramsList\$optimisation\$algorithm = "NLOPT_LN_SBPLX"
    paramsList\$optimisation\$xtol_abs = 0.001
    paramsList\$optimisation\$maxeval =  10000
    paramsList\$optimisation\$maxtime = 60*5
    
    # Run multiple independent optimization loops to avoid local minima
    N = 10
    allRes = list()
    for (i in 1:N){
        Res = CNORwrapFuzzy(CNOlistDREAM, DreamModel, paramsList=paramsList, 
            verbose=TRUE)
        allRes[[i]] = Res
    }
    
    # Save raw optimization results
    saveRDS(allRes, "all_optimization_results.rds")
    
    # Compile multi-run optimization results and plot trade-off
    pdf("compile_multi_res_plot.pdf", width=8, height=6)
    summary = compileMultiRes(allRes, show=TRUE)
    dev.off()
    
    # Save compiled summary
    saveRDS(summary, "summary_compiled_results.rds")
    
    # Plot mean fuzzy fit against experimental data
    pdf("mean_fuzzy_fit_plot.pdf", width=10, height=8)
    plotMeanFuzzyFit(0.01, summary\$allFinalMSEs, allRes)
    dev.off()
    
    # Export the optimized network and Cytoscape-compatible files
    writeFuzzyNetwork(0.01, summary\$allFinalMSEs, allRes, "output_dream")
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_CNORFUZZY_CONSTRAINED_FUZZY_LOGIC_TRAINING":',
        paste0('    CNORfuzzy: ', as.character(packageVersion('CNORfuzzy')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_constrained_fuzzy_logic_training.csv versions.yml
    """
}

workflow BIOC_CNORFUZZY_CONSTRAINED_FUZZY_LOGIC_TRAINING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ CNOlistDREAM, DreamModel ] ]

    main:
    BIOC_CNORFUZZY_CONSTRAINED_FUZZY_LOGIC_TRAINING(ch_input)

    emit:
    tables   = BIOC_CNORFUZZY_CONSTRAINED_FUZZY_LOGIC_TRAINING.out.tables
    plots    = BIOC_CNORFUZZY_CONSTRAINED_FUZZY_LOGIC_TRAINING.out.plots
    objects  = BIOC_CNORFUZZY_CONSTRAINED_FUZZY_LOGIC_TRAINING.out.objects
    versions = BIOC_CNORFUZZY_CONSTRAINED_FUZZY_LOGIC_TRAINING.out.versions
}
