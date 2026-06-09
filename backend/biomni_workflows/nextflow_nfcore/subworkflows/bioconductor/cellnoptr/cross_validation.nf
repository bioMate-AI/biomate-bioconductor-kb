#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CellNOptR — cross_validation
// Assess the predictive performance of boolean models using k-fold cross-validation with parallel processing.
// Input: PKN_ToyPB, CNOlist_ToyPB
// Container: quay.io/biocontainers/bioconductor-cellnoptr:1.56.0--r45h01b2380_0
// Requires: CellNOptR, doParallel
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load data and PKN
//  * 2. [Core Analysis] Preprocess the network
//  * 3. [Core Analysis] Subset timepoints in the CNOlist using cutCNOlist
//  * 4. [Core Analysis] Perform k-fold cross-validation using crossvalidateBoolean with different resampling strategies in parallel or serial mode

nextflow.enable.dsl = 2

process BIOC_CELLNOPTR_CROSS_VALIDATION {
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
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(CellNOptR)
    library(doParallel)
    
    # Helper function to load user input files robustly (RDS or RData/rda)
    read_input_object <- function(filename) {
      # Try exact filename
      if (file.exists(filename)) {
        val <- tryCatch({
          readRDS(filename)
        }, error = function(e) {
          env <- new.env()
          tryCatch({
            load(filename, envir = env)
            vars <- ls(env)
            if (length(vars) > 0) get(vars[1], envir = env) else NULL
          }, error = function(e2) {
            NULL
          })
        })
        if (!is.null(val)) return(val)
      }
      
      # Try with .rds extension
      rds_path <- paste0(filename, ".rds")
      if (file.exists(rds_path)) {
        return(readRDS(rds_path))
      }
      
      # Try with .RData extension
      rdata_path <- paste0(filename, ".RData")
      if (file.exists(rdata_path)) {
        env <- new.env()
        load(rdata_path, envir = env)
        vars <- ls(env)
        if (length(vars) > 0) return(get(vars[1], envir = env))
      }
      
      # Try with .rda extension
      rda_path <- paste0(filename, ".rda")
      if (file.exists(rda_path)) {
        env <- new.env()
        load(rda_path, envir = env)
        vars <- ls(env)
        if (length(vars) > 0) return(get(vars[1], envir = env))
      }
      
      stop(paste("Error: Could not find or load file:", filename))
    }
    
    # 1. Load data and PKN from the working directory
    pknmodel <- read_input_object("PKN_ToyPB")
    cnodata <- read_input_object("CNOlist_ToyPB")
    
    # 2. Preprocess the network
    model = preprocessing(data = cnodata,model = pknmodel,compression = T,expansion = T)
    
    # Save preprocessed model
    saveRDS(model, file = "model_preprocessed.rds")
    
    # Plot and save the preprocessed model
    pdf("model_plot.pdf")
    plotModel(model,cnodata)
    dev.off()
    
    # Plot and save the original CNOlist data
    pdf("cnodata_plot.pdf")
    plot(cnodata)
    dev.off()
    
    # 3. Subset timepoints in the CNOlist using cutCNOlist
    selectedTime = c(0,10)
    cnodata_prep = cutCNOlist(cnodata ,model = model,
                              cutTimeIndices = which(!cnodata@timepoints %in% selectedTime))
    
    # Save preprocessed CNOlist
    saveRDS(cnodata_prep, file = "cnodata_prep.rds")
    
    # Plot and save the subsetted CNOlist data
    pdf("cnodata_prep_plot.pdf")
    plot(cnodata_prep)
    dev.off()
    
    # Perform optimization
    opt = gaBinaryT1(CNOlist = cnodata_prep,model = model)
    saveRDS(opt, file = "opt_results.rds")
    
    # 4. Perform k-fold cross-validation using crossvalidateBoolean
    doParallel::registerDoParallel(cores=3)
    
    # Run parallel cross-validation
    system.time({R1=crossvalidateBoolean(CNOlist = cnodata_prep, model = model,
                                         type="datapoint", nfolds=10, parallel = TRUE)})
    saveRDS(R1, file = "cv_results_R1.rds")
    
    system.time({R2=crossvalidateBoolean(CNOlist = cnodata_prep, model=model,
                                         type="experiment", nfolds=10, parallel = TRUE)})
    saveRDS(R2, file = "cv_results_R2.rds")
    
    system.time({R3=crossvalidateBoolean(CNOlist = cnodata_prep, model=model,
                                         type="observable", nfolds=10, parallel = TRUE)})
    saveRDS(R3, file = "cv_results_R3.rds")
    
    # Run serial cross-validation
    system.time({R4=crossvalidateBoolean(CNOlist = cnodata_prep, model=model,
                                         type="datapoint", nfolds=10, parallel = FALSE)})
    saveRDS(R4, file = "cv_results_R4.rds")
    
    system.time({R5=crossvalidateBoolean(CNOlist = cnodata_prep, model=model,
                                         type="experiment", nfolds=10, parallel = FALSE)})
    saveRDS(R5, file = "cv_results_R5.rds")
    
    system.time({R6=crossvalidateBoolean(CNOlist = cnodata_prep, model=model,
                                         type="observable", nfolds=10, parallel = FALSE)})
    saveRDS(R6, file = "cv_results_R6.rds")

    writeLines(c(
        '"BIOC_CELLNOPTR_CROSS_VALIDATION":',
        paste0('    CellNOptR: ', as.character(packageVersion('CellNOptR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cross_validation.csv versions.yml
    """
}

workflow BIOC_CELLNOPTR_CROSS_VALIDATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ PKN_ToyPB, CNOlist_ToyPB ] ]

    main:
    BIOC_CELLNOPTR_CROSS_VALIDATION(ch_input)

    emit:
    tables   = BIOC_CELLNOPTR_CROSS_VALIDATION.out.tables
    plots    = BIOC_CELLNOPTR_CROSS_VALIDATION.out.plots
    objects  = BIOC_CELLNOPTR_CROSS_VALIDATION.out.objects
    versions = BIOC_CELLNOPTR_CROSS_VALIDATION.out.versions
}
