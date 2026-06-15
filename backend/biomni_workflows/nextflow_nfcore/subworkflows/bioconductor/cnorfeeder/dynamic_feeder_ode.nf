#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CNORfeeder — dynamic_feeder_ode
// Identify poorly-fitted measurements in a dynamic ODE model, search for missing links in a database or infer them from data, integrate them, and perform paramete
// Input: CNOlistToy_Gene, ToyModel_Gene, database
// Container: quay.io/biocontainers/bioconductor-cnorfeeder:1.50.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CNORfeeder, CNORode, CellNOptR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create ODE parameters using createLBodeContPars
//  * 2. [Core Analysis] Estimate parameters for the initial model using parEstimationLBode
//  * 3. [Visualization & Output] Simulate and plot initial fit using plotLBodeFitness
//  * 4. [Core Analysis] Identify poorly-fitted measurements using identifyMisfitIndices
//  * 5. [Input & Preparation] Build feeder object using buildFeederObjectDynamic
//  * 6. [Core Analysis] Integrate links using integrateLinks
//  * 7. [Core Analysis] Run dynamic feeder optimization with penalties using runDynamicFeeder
//  * 8. [Visualization & Output] Plot final fit using plotLBodeFitness

nextflow.enable.dsl = 2

process BIOC_CNORFEEDER_DYNAMIC_FEEDER_ODE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("CellNOptR", "MEIGOR", "CNORode", "CNORfeeder")
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
    library(CellNOptR)
    library(MEIGOR)
    library(CNORode)
    library(CNORfeeder)
    
    # Helper function to read input files from the working directory
    read_input <- function(filename) {
      if (file.exists(filename)) {
        return(readRDS(filename))
      } else if (file.exists(paste0(filename, ".rds"))) {
        return(readRDS(paste0(filename, ".rds")))
      } else if (file.exists(paste0(filename, ".RData"))) {
        env <- new.env()
        load(paste0(filename, ".RData"), envir = env)
        return(get(ls(env)[1], envir = env))
      } else {
        stop(paste("Required input file not found in working directory:", filename))
      }
    }
    
    # Read user input files
    CNOlistToy_Gene <- read_input("CNOlistToy_Gene")
    model <- read_input("ToyModel_Gene")
    database <- read_input("database")
    
    # Define paramsSSm as specified in the vignette
    paramsSSm = defaultParametersSSm()
    paramsSSm\$local_solver = "DHC"
    paramsSSm\$maxtime = 60
    paramsSSm\$maxeval = Inf
    paramsSSm\$atol = 1e-6
    paramsSSm\$reltol = 1e-6
    paramsSSm\$nan_fac = 1000
    paramsSSm\$dim_refset = 30
    paramsSSm\$n_diverse = 1000
    paramsSSm\$maxStepSize = Inf
    paramsSSm\$maxNumSteps = 10000
    paramsSSm\$transfer_function = 4
    paramsSSm\$lambda_tau = 0.1
    paramsSSm\$lambda_k = 0.01
    paramsSSm\$bootstrap = FALSE
    paramsSSm\$SSpenalty_fac = 0
    paramsSSm\$SScontrolPenalty_fac = 0
    
    # 1. Create ODE parameters using createLBodeContPars
    ode_parameters = createLBodeContPars(
      model, 
      LB_n = 1, 
      LB_k = 0, 
      LB_tau = 0, 
      UB_n = 3, 
      UB_k = 1, 
      UB_tau = 1, 
      default_n = 3, 
      default_k = 0.5, 
      default_tau = 0.01, 
      opt_n = FALSE, 
      opt_k = TRUE, 
      opt_tau = TRUE, 
      random = TRUE
    )
    
    # 2. Estimate parameters for the initial model using parEstimationLBode
    opt_pars = parEstimationLBode(
      CNOlistToy_Gene, 
      model, 
      method = "essm", 
      ode_parameters = ode_parameters, 
      paramsSSm = paramsSSm
    )
    saveRDS(opt_pars, "opt_pars.rds")
    
    # 3. Simulate and plot initial fit using plotLBodeFitness
    pdf("initial_fit_plot.pdf", width = 10, height = 8)
    simData = plotLBodeFitness(
      cnolist = CNOlistToy_Gene, 
      model = model, 
      ode_parameters = opt_pars, 
      transfer_function = 4
    )
    dev.off()
    saveRDS(simData, "simData.rds")
    
    # 4. Identify poorly-fitted measurements using identifyMisfitIndices
    indices = identifyMisfitIndices(
      cnolist = CNOlistToy_Gene, 
      model = model, 
      simData = simData, 
      mseThresh = 0.05
    )
    saveRDS(indices, "misfit_indices.rds")
    
    # 5. Build feeder object using buildFeederObjectDynamic
    feederObject = buildFeederObjectDynamic(
      model = model, 
      cnolist = CNOlistToy_Gene, 
      indices = indices, 
      database = database, 
      DDN = TRUE, 
      pathLength = 2
    )
    saveRDS(feederObject, "feederObject.rds")
    
    # 6. Integrate links using integrateLinks
    integratedModel = integrateLinks(
      feederObject = feederObject, 
      cnolist = CNOlistToy_Gene, 
      database = database
    )
    saveRDS(integratedModel, "integratedModel.rds")
    
    # Plot integrated model
    pdf("integrated_model_plot.pdf", width = 10, height = 8)
    plotModel(
      model = integratedModel\$model, 
      CNOlist = CNOlistToy_Gene, 
      indexIntegr = integratedModel\$integLinksIdx
    )
    dev.off()
    
    # Re-create ODE parameters for the integrated model
    ode_parameters = createLBodeContPars(
      integratedModel\$model, 
      LB_n = 1, 
      LB_k = 0, 
      LB_tau = 0, 
      UB_n = 3, 
      UB_k = 1, 
      UB_tau = 1, 
      default_n = 3, 
      default_k = 0.5, 
      default_tau = 0.01, 
      opt_n = FALSE, 
      opt_k = TRUE, 
      opt_tau = TRUE, 
      random = TRUE
    )
    
    # 7. Run dynamic feeder optimization with penalties using runDynamicFeeder
    res1 = runDynamicFeeder(
      cnolist = CNOlistToy_Gene, 
      integratedModel = integratedModel, 
      ode_parameters = ode_parameters, 
      paramsSSm = paramsSSm, 
      penFactor_k = 2, 
      penFactorPIN_k = 0.1, 
      penFactor_tau = 1
    )
    saveRDS(res1, "dynamic_feeder_results.rds")
    
    # 8. Plot final fit using plotLBodeFitness
    pdf("final_fit_plot.pdf", width = 10, height = 8)
    plotLBodeFitness(
      cnolist = res1\$CNOList, 
      model = res1\$`Integrated-Model`\$model, 
      ode_parameters = res1\$Parameters, 
      transfer_function = 4
    )
    dev.off()

    writeLines(c(
        '"BIOC_CNORFEEDER_DYNAMIC_FEEDER_ODE":',
        paste0('    CNORfeeder: ', as.character(packageVersion('CNORfeeder')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dynamic_feeder_ode.csv versions.yml
    """
}

workflow BIOC_CNORFEEDER_DYNAMIC_FEEDER_ODE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ CNOlistToy_Gene, ToyModel_Gene, database ] ]

    main:
    BIOC_CNORFEEDER_DYNAMIC_FEEDER_ODE(ch_input)

    emit:
    tables   = BIOC_CNORFEEDER_DYNAMIC_FEEDER_ODE.out.tables
    plots    = BIOC_CNORFEEDER_DYNAMIC_FEEDER_ODE.out.plots
    objects  = BIOC_CNORFEEDER_DYNAMIC_FEEDER_ODE.out.objects
    versions = BIOC_CNORFEEDER_DYNAMIC_FEEDER_ODE.out.versions
}
