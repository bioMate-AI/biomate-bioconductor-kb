#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: basecallqc — sample_sheet_prep_and_command_generation
// Clean and validate an Illumina sample sheet, generate base masks, and construct the bcl2fastq execution command.
// Input: runParameters.xml, config.ini, SampleSheet.csv
// Container: quay.io/biocontainers/bioconductor-basecallqc:1.34.0--r45hdfd78af_0
// R packages: basecallQC
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BASECALLQC_SAMPLE_SHEET_PREP_AND_COMMAND_GENERATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-basecallqc:1.34.0--r45hdfd78af_0"

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
    .bm_deps <- c("basecallQC")
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
    library(basecallQC)
    
    # Define exact input file paths in the working directory
    runXML <- "runParameters.xml"
    config <- "config.ini"
    sampleSheet <- "SampleSheet.csv"
    
    # Validate existence of required input files
    required_files <- c(runXML, config, sampleSheet)
    missing_files <- required_files[!file.exists(required_files)]
    if (length(missing_files) > 0) {
      stop(paste("Missing required input file(s) in the working directory:", 
                 paste(missing_files, collapse = ", ")))
    }
    
    # 1. Initialize run parameters using BCL2FastQparams
    message("Initializing BCL2FastQ parameters...")
    bcl2fastqparams <- BCL2FastQparams(runXML, config, runDir = getwd(), verbose = FALSE)
    
    # 2. Clean and validate the sample sheet using validateBCLSheet
    message("Validating and cleaning sample sheet...")
    cleanedSampleSheet <- validateBCLSheet(sampleSheet, param = bcl2fastqparams)
    
    # 3. Generate base masks using createBasemasks
    message("Generating base masks...")
    baseMasks <- createBasemasks(cleanedSampleSheet, param = bcl2fastqparams)
    
    # 4. Create the bcl2fastq execution command using createBCLcommand
    message("Constructing bcl2fastq execution command...")
    toSubmit <- createBCLcommand(bcl2fastqparams, cleanedSampleSheet, baseMasks)
    
    # Write outputs to the working directory
    message("Writing output files...")
    
    # Save the cleaned sample sheet as a CSV
    write.csv(cleanedSampleSheet, file = "cleaned_SampleSheet.csv", row.names = FALSE)
    
    # Save the generated base masks as a CSV
    write.csv(baseMasks, file = "baseMasks.csv", row.names = FALSE)
    
    # Save the bcl2fastq command to a shell script
    writeLines(toSubmit, con = "bcl2fastq_command.sh")
    
    # Save the BCL2FastQparams object as an RDS file for downstream QC steps
    saveRDS(bcl2fastqparams, file = "bcl2fastqparams.rds")
    
    message("Pipeline completed successfully. Outputs generated:")
    message("- cleaned_SampleSheet.csv")
    message("- baseMasks.csv")
    message("- bcl2fastq_command.sh")
    message("- bcl2fastqparams.rds")

    writeLines(c(
        '"BIOC_BASECALLQC_SAMPLE_SHEET_PREP_AND_COMMAND_GENERATION":',
        paste0('        basecallqc: ', as.character(packageVersion("basecallqc")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sample_sheet_prep_and_command_generation.csv versions.yml
    """
}

workflow BIOC_BASECALLQC_SAMPLE_SHEET_PREP_AND_COMMAND_GENERATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ runParameters.xml, config.ini, SampleSheet.csv ] ]

    main:
    BIOC_BASECALLQC_SAMPLE_SHEET_PREP_AND_COMMAND_GENERATION(ch_input)

    emit:
    tables   = BIOC_BASECALLQC_SAMPLE_SHEET_PREP_AND_COMMAND_GENERATION.out.tables
    plots    = BIOC_BASECALLQC_SAMPLE_SHEET_PREP_AND_COMMAND_GENERATION.out.plots
    objects  = BIOC_BASECALLQC_SAMPLE_SHEET_PREP_AND_COMMAND_GENERATION.out.objects
    versions = BIOC_BASECALLQC_SAMPLE_SHEET_PREP_AND_COMMAND_GENERATION.out.versions
}
