#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mimager — plm_spatial_artifact_visualization
// Fit a probe-level linear model (PLM) and visualize its residuals or weights to reveal subtle spatial artifacts.
// Input: raw_microarray_data.RData
// Container: quay.io/biocontainers/bioconductor-mimager:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: affy, affyPLM, mimager, oligo
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Fit a probe-level linear model using affyPLM or oligo; 2. Plot the PLM residuals or weights using mimage

nextflow.enable.dsl = 2

process BIOC_MIMAGER_PLM_SPATIAL_ARTIFACT_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("mimager", "affyPLM", "affy", "oligo")
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
    library(mimager)
    library(affyPLM)
    library(affy)
    
    # Input file check
    input_file <- "raw_microarray_data.RData"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    # Load the user input data
    env <- new.env()
    load(input_file, envir = env)
    
    # Identify the AffyBatch or FeatureSet object
    obj_names <- ls(env)
    Dilution <- NULL
    for (name in obj_names) {
      if (inherits(env[[name]], "AffyBatch") || inherits(env[[name]], "FeatureSet")) {
        Dilution <- env[[name]]
        break
      }
    }
    
    # Fallback if no explicit AffyBatch or FeatureSet is found but another object is present
    if (is.null(Dilution) && length(obj_names) > 0) {
      Dilution <- env[[obj_names[1]]]
    }
    
    if (is.null(Dilution)) {
      stop("Could not find a valid microarray data object in the input file.")
    }
    
    # Fit the probe-level linear model (PLM)
    if (inherits(Dilution, "FeatureSet")) {
      library(oligo)
      DilutionPLM <- fitProbeLevelModel(Dilution)
    } else {
      DilutionPLM <- fitPLM(Dilution)
    }
    
    # Save the PLM object
    saveRDS(DilutionPLM, file = "dilution_plm.rds")
    
    # Visualize the PLM residuals/weights and save to PDF
    # Documented code: mimage(DilutionPLM)
    pdf("plm_spatial_artifact_visualization.pdf", width = 8, height = 8)
    mimage(DilutionPLM)
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved: dilution_plm.rds, plm_spatial_artifact_visualization.pdf\n")

    writeLines(c(
        '"BIOC_MIMAGER_PLM_SPATIAL_ARTIFACT_VISUALIZATION":',
        paste0('    mimager: ', as.character(packageVersion('mimager')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_plm_spatial_artifact_visualization.csv versions.yml
    """
}

workflow BIOC_MIMAGER_PLM_SPATIAL_ARTIFACT_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_microarray_data.RData ] ]

    main:
    BIOC_MIMAGER_PLM_SPATIAL_ARTIFACT_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_MIMAGER_PLM_SPATIAL_ARTIFACT_VISUALIZATION.out.tables
    plots    = BIOC_MIMAGER_PLM_SPATIAL_ARTIFACT_VISUALIZATION.out.plots
    objects  = BIOC_MIMAGER_PLM_SPATIAL_ARTIFACT_VISUALIZATION.out.objects
    versions = BIOC_MIMAGER_PLM_SPATIAL_ARTIFACT_VISUALIZATION.out.versions
}
