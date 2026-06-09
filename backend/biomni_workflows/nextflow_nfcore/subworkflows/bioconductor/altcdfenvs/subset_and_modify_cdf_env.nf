#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: altcdfenvs — subset_and_modify_cdf_env
// Wrap an existing CDF environment package into a CdfEnvAffy object, subset it to keep only specific probe sets of interest, and rename the environment.
// Input: plasmodiumanophelescdf, Plasmodium-Probeset-IDs.txt
// Container: quay.io/biocontainers/bioconductor-altcdfenvs:2.72.0--r45hdfd78af_0
// Requires: altcdfenvs, plasmodiumanophelescdf
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Wrap the existing CDF environment using wrapCdfEnvAffy
//  * 2. [Core Analysis] Retrieve gene/probe set names using geneNames
//  * 3. [Core Analysis] Subset the CDF environment using standard [ indexing
//  * 4. [Core Analysis] Modify the environment name slot @envName

nextflow.enable.dsl = 2

process BIOC_ALTCDFENVS_SUBSET_AND_MODIFY_CDF_ENV {
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
    library(altcdfenvs)
    
    # ==========================================
    # 1. READ USER INPUTS FROM WORKING DIRECTORY
    # ==========================================
    
    # Load the plasmodiumanophelescdf environment/package
    if (file.exists("plasmodiumanophelescdf")) {
      # If it is a saved RDS or RData file
      plasmodiumanophelescdf <- tryCatch({
        readRDS("plasmodiumanophelescdf")
      }, error = function(e) {
        env <- new.env()
        load("plasmodiumanophelescdf", envir = env)
        objs <- ls(env)
        if (length(objs) > 0) {
          env[[objs[1]]]
        } else {
          stop("No objects found in RData file 'plasmodiumanophelescdf'")
        }
      })
    } else if (dir.exists("plasmodiumanophelescdf")) {
      # If it is an unpacked package directory
      tryCatch({
        install.packages("plasmodiumanophelescdf", repos = NULL, type = "source")
        library(plasmodiumanophelescdf)
      }, error = function(e) {
        rda_path <- file.path("plasmodiumanophelescdf", "data", "plasmodiumanophelescdf.rda")
        if (file.exists(rda_path)) {
          load(rda_path)
        } else {
          stop("Could not load plasmodiumanophelescdf from directory")
        }
      })
    } else {
      # Fallback to loading the installed package
      library(plasmodiumanophelescdf)
    }
    
    # Ensure the object is available in the current environment
    if (!exists("plasmodiumanophelescdf")) {
      plasmodiumanophelescdf <- get("plasmodiumanophelescdf")
    }
    
    # Read the probe set IDs of interest from the user-provided text file
    if (file.exists("Plasmodium-Probeset-IDs.txt")) {
      user_ids <- scan(file = "Plasmodium-Probeset-IDs.txt", what = "", quiet = TRUE)
    } else {
      stop("Required input file 'Plasmodium-Probeset-IDs.txt' not found in the working directory.")
    }
    
    # ==========================================
    # 2. EXECUTE DOCUMENTED WORKFLOW
    # ==========================================
    
    # Stage 1: Wrap the existing CDF environment
    planocdf <- wrapCdfEnvAffy(plasmodiumanophelescdf, 712, 712, "plasmodiumanophelescdf")
    
    # Stage 2: Retrieve gene/probe set names
    ids <- geneNames(planocdf)
    ids.pf <- ids[grep("^Pf", ids)]
    
    # Adapt to use the user-provided probe set IDs of interest while preserving the documented code structure
    if (length(user_ids) > 0) {
      ids.pf <- user_ids
    }
    
    # Stage 3: Subset the CDF environment
    plcdf <- planocdf[ids.pf]
    
    # Stage 4: Modify the environment name slot
    plcdf@envName <- "Plasmodium ids only"
    
    # ==========================================
    # 3. WRITE OUTPUTS TO WORKING DIRECTORY
    # ==========================================
    
    # Save the modified CdfEnvAffy object as an RDS file
    saveRDS(plcdf, file = "plcdf_subset.rds")
    
    # Save the subsetted probe set IDs as a CSV table
    write.csv(
      data.frame(ProbeSetID = geneNames(plcdf)),
      file = "subset_probesets.csv",
      row.names = FALSE
    )
    
    cat("Workflow completed successfully. Outputs saved to 'plcdf_subset.rds' and 'subset_probesets.csv'.\n")

    writeLines(c(
        '"BIOC_ALTCDFENVS_SUBSET_AND_MODIFY_CDF_ENV":',
        paste0('    altcdfenvs: ', as.character(packageVersion('altcdfenvs')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_subset_and_modify_cdf_env.csv versions.yml
    """
}

workflow BIOC_ALTCDFENVS_SUBSET_AND_MODIFY_CDF_ENV_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ plasmodiumanophelescdf, Plasmodium-Probeset-IDs.txt ] ]

    main:
    BIOC_ALTCDFENVS_SUBSET_AND_MODIFY_CDF_ENV(ch_input)

    emit:
    tables   = BIOC_ALTCDFENVS_SUBSET_AND_MODIFY_CDF_ENV.out.tables
    plots    = BIOC_ALTCDFENVS_SUBSET_AND_MODIFY_CDF_ENV.out.plots
    objects  = BIOC_ALTCDFENVS_SUBSET_AND_MODIFY_CDF_ENV.out.objects
    versions = BIOC_ALTCDFENVS_SUBSET_AND_MODIFY_CDF_ENV.out.versions
}
