#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: agilp — agilent_microarray_preprocessing_pipeline
// Extract, normalize, and map raw Agilent microarray scanner data using a template-driven pipeline.
// Input: scanner_files.txt, sample_template.txt, annotations_sample.txt
// Container: quay.io/biocontainers/bioconductor-agilp:3.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: agilp
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract raw signals and average replicate probes using AAProcess
//  * 2. [Core Analysis] Generate a list of extracted filenames using filenamex to populate the template
//  * 3. [Core Analysis] Generate a normalization baseline file using Baseline
//  * 4. [Core Analysis] Select and merge or copy processed files using Loader
//  * 5. [Core Analysis] Perform LOESS normalization against the baseline using AALoess
//  * 6. [Core Analysis] Swap probe identifiers to target IDs (e.g., Ensembl IDs) using IDswop
//  * 7. [Core Analysis] Equalize files using Equaliser

nextflow.enable.dsl = 2

process BIOC_AGILP_AGILENT_MICROARRAY_PREPROCESSING_PIPELINE {
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
    .bm_deps <- c("agilp")
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
        
        # Load the required Bioconductor package
        library(agilp)
        
        # Define directory paths for the pipeline stages
        scanner_input_dir   <- "scanner_input/"
        processed_raw_dir   <- "processed_raw/"
        filename_output_dir <- "filename_output/"
        loader_output_dir   <- "loader_output/"
        loess_output_dir    <- "loess_output/"
        swapped_output_dir  <- "swapped_output/"
        equalised_output_dir <- "equalised_output/"
        
        # Create the directories if they do not exist
        dir.create(scanner_input_dir, showWarnings = FALSE, recursive = TRUE)
        dir.create(processed_raw_dir, showWarnings = FALSE, recursive = TRUE)
        dir.create(filename_output_dir, showWarnings = FALSE, recursive = TRUE)
        dir.create(loader_output_dir, showWarnings = FALSE, recursive = TRUE)
        dir.create(loess_output_dir, showWarnings = FALSE, recursive = TRUE)
        dir.create(swapped_output_dir, showWarnings = FALSE, recursive = TRUE)
        dir.create(equalised_output_dir, showWarnings = FALSE, recursive = TRUE)
        
        # Validate and prepare the user input files
        if (!file.exists("scanner_files.txt")) {
          stop("Required input file 'scanner_files.txt' not found in the working directory.")
        }
        if (!file.exists("sample_template.txt")) {
          stop("Required input file 'sample_template.txt' not found in the working directory.")
        }
        if (!file.exists("annotations_sample.txt")) {
          stop("Required input file 'annotations_sample.txt' not found in the working directory.")
        }
        
        # Copy the raw scanner file to the scanner input directory for processing
        file.copy("scanner_files.txt", file.path(scanner_input_dir, "scanner_file_1.txt"), overwrite = TRUE)
        
        # Define file paths for template and annotation inputs
        template_path <- "sample_template.txt"
        annotation_path <- "annotations_sample.txt"
        outputbase <- "testbase.txt"
        
        # 1. Extract raw signals and average replicate probes using AAProcess
        message("Stage 1: Running AAProcess...")
        AAProcess(input = scanner_input_dir, output = processed_raw_dir, s = 9)
        
        # 2. Generate a list of extracted filenames using filenamex to populate the template
        message("Stage 2: Running filenamex...")
        filenamex(input = processed_raw_dir, output = filename_output_dir)
        
        # 3. Generate a normalization baseline file using Baseline
        message("Stage 3: Running Baseline...")
        Baseline(NORM = "LOG", allfiles = "TRUE", r = 2, A = 2, B = 3, input = processed_raw_dir, baseout = outputbase, t = template_path)
        
        # 4. Select and merge or copy processed files using Loader
        message("Stage 4: Running Loader...")
        Loader(input = processed_raw_dir, output = loader_output_dir, t = template_path, f = "TRUE", r = 2, A = 2, B = 5)
        
        # 5. Perform LOESS normalization against the baseline using AALoess
        message("Stage 5: Running AALoess...")
        AALoess(input = loader_output_dir, output = loess_output_dir, baseline = outputbase, LOG = "TRUE")
        
        # 6. Swap probe identifiers to target IDs (e.g., Ensembl IDs) using IDswop
        message("Stage 6: Running IDswop...")
        IDswop(input = loess_output_dir, output = swapped_output_dir, annotation = annotation_path, source_ID = "ProbeID", target_ID = "EnsemblID", ERR = 0.2)
        
        # 7. Equalize files using Equaliser
        message("Stage 7: Running Equaliser...")
        Equaliser(input = swapped_output_dir, output = equalised_output_dir)
        
        message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_AGILP_AGILENT_MICROARRAY_PREPROCESSING_PIPELINE":',
        paste0('    agilp: ', as.character(packageVersion('agilp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_agilent_microarray_preprocessing_pipeline.csv versions.yml
    """
}

workflow BIOC_AGILP_AGILENT_MICROARRAY_PREPROCESSING_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ scanner_files.txt, sample_template.txt, annotations_sample.txt ] ]

    main:
    BIOC_AGILP_AGILENT_MICROARRAY_PREPROCESSING_PIPELINE(ch_input)

    emit:
    tables   = BIOC_AGILP_AGILENT_MICROARRAY_PREPROCESSING_PIPELINE.out.tables
    plots    = BIOC_AGILP_AGILENT_MICROARRAY_PREPROCESSING_PIPELINE.out.plots
    objects  = BIOC_AGILP_AGILENT_MICROARRAY_PREPROCESSING_PIPELINE.out.objects
    versions = BIOC_AGILP_AGILENT_MICROARRAY_PREPROCESSING_PIPELINE.out.versions
}
