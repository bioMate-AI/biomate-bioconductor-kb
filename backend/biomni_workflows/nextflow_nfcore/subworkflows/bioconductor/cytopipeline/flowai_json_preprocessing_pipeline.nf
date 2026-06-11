#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cytopipeline — flowai_json_preprocessing_pipeline
// Build and execute a flow cytometry preprocessing pipeline using flowAI for quality control via a JSON configuration file.
// Input: sampleFiles, OMIP021_flowAI_pipeline.json
// Container: quay.io/biocontainers/bioconductor-cytopipeline:1.10.0--r45hdfd78af_0
// R packages: CytoPipeline
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CYTOPIPELINE_FLOWAI_JSON_PREPROCESSING_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-cytopipeline:1.10.0--r45hdfd78af_0"

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
    .bm_deps <- c("CytoPipeline")
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
    
    library(CytoPipeline)
    
    # Define input files from the working directory
    jsonFile <- "OMIP021_flowAI_pipeline.json"
    sampleFiles <- list.files(path = ".", pattern = "\\\\.fcs\$", full.names = TRUE)
    
    # Ensure files exist
    if (!file.exists(jsonFile)) {
      stop(paste("Required JSON configuration file missing:", jsonFile))
    }
    if (length(sampleFiles) == 0) {
      stop("No .fcs sample files found in the working directory.")
    }
    
    # Define output/cache directory
    workDir <- "cytopipeline_cache"
    if (!dir.exists(workDir)) {
      dir.create(workDir, recursive = TRUE)
    }
    
    # --- Initialize CytoPipeline from JSON ---
    pipL_flowAI <- CytoPipeline(
      jsonFile,
      experimentName = "OMIP021_flowAI",
      sampleFiles = sampleFiles
    )
    
    # --- Execute pipeline ---
    execute(pipL_flowAI, path = workDir)
    
    # --- Visualize processing queues ---
    # Plot workflow graph - flowAI - scale transformList
    pdf("workflow_scale_transform.pdf")
    tryCatch({
      plotCytoPipelineProcessingQueue(
        pipL_flowAI,
        whichQueue = "scale transform",
        path = workDir
      )
    }, error = function(e) {
      warning("Could not plot scale transform queue: ", e\$message)
    })
    dev.off()
    
    # Plot workflow graph - flowAI - pre-processing
    pdf("workflow_preprocessing.pdf")
    tryCatch({
      plotCytoPipelineProcessingQueue(
        pipL_flowAI,
        whichQueue = "pre-processing",
        sampleFile = 1,
        path = workDir
      )
    }, error = function(e) {
      warning("Could not plot pre-processing queue: ", e\$message)
    })
    dev.off()
    
    # --- Retrieve and save meaningful results ---
    # Save the pipeline object
    saveRDS(pipL_flowAI, file = "pipL_flowAI.rds")
    
    # Collect and save retained events
    ret <- tryCatch({
      CytoPipeline::collectNbOfRetainedEvents(
        experimentName = "OMIP021_flowAI",
        path = workDir
      )
    }, error = function(e) {
      warning("Could not collect retained events: ", e\$message)
      NULL
    })
    
    if (!is.null(ret)) {
      write.csv(ret, "retained_events_flowAI.csv", row.names = TRUE)
    }
    
    # Get object information and save
    infos <- tryCatch({
      getCytoPipelineObjectInfos(
        pipL_flowAI,
        path = workDir,
        whichQueue = "pre-processing",
        sampleFile = sampleFiles[1]
      )
    }, error = function(e) {
      warning("Could not get object infos: ", e\$message)
      NULL
    })
    
    if (!is.null(infos)) {
      write.csv(infos, "flowAI_object_infos.csv", row.names = FALSE)
      
      # Retrieve the last processed flowFrame and save it
      last_obj_name <- tail(infos\$ObjectName, 1)
      if (length(last_obj_name) > 0) {
        ff <- tryCatch({
          getCytoPipelineFlowFrame(
            pipL_flowAI,
            whichQueue = "pre-processing",
            sampleFile = 1,
            objectName = last_obj_name,
            path = workDir
          )
        }, error = function(e) {
          warning("Could not retrieve final flowFrame: ", e\$message)
          NULL
        })
        
        if (!is.null(ff)) {
          saveRDS(ff, file = "preprocessed_flowframe_sample1.rds")
        }
      }
    }

    writeLines(c(
        '"BIOC_CYTOPIPELINE_FLOWAI_JSON_PREPROCESSING_PIPELINE":',
        paste0('        cytopipeline: ', as.character(packageVersion("cytopipeline")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowai_json_preprocessing_pipeline.csv versions.yml
    """
}

workflow BIOC_CYTOPIPELINE_FLOWAI_JSON_PREPROCESSING_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sampleFiles, OMIP021_flowAI_pipeline.json ] ]

    main:
    BIOC_CYTOPIPELINE_FLOWAI_JSON_PREPROCESSING_PIPELINE(ch_input)

    emit:
    tables   = BIOC_CYTOPIPELINE_FLOWAI_JSON_PREPROCESSING_PIPELINE.out.tables
    plots    = BIOC_CYTOPIPELINE_FLOWAI_JSON_PREPROCESSING_PIPELINE.out.plots
    objects  = BIOC_CYTOPIPELINE_FLOWAI_JSON_PREPROCESSING_PIPELINE.out.objects
    versions = BIOC_CYTOPIPELINE_FLOWAI_JSON_PREPROCESSING_PIPELINE.out.versions
}
