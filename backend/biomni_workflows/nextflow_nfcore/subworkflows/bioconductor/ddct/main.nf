#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ddct — ddct_high_level_pipeline
// Run the end-to-end ddCt analysis pipeline using a single parameter list and the high-level wrapper function ddCtExec.
// Input: Experiment1.txt, SampleAnno.txt, ddCt.conf
// Container: quay.io/biocontainers/bioconductor-ddct:1.66.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DDCT_DDCT_HIGH_LEVEL_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ddct:1.66.0--r45hdfd78af_0"

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
    .bm_deps <- c("biobase", "ddct", "lattice", "rcolorbrewer")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(Biobase)
    library(lattice)
    library(RColorBrewer)
    library(ddCt)
    
    # Locate the ddCt.R script within the package installation directory without using system.file
    ddct_path <- find.package("ddCt")
    script_path <- file.path(ddct_path, "scripts", "ddCt.R")
    
    if (!file.exists(script_path)) {
      stop("Could not find ddCt.R script in the package directory.")
    }
    
    # Source the ddCt execution script
    source(script_path)
    
    # Define input files from the working directory
    input_file <- "Experiment1.txt"
    anno_file <- "SampleAnno.txt"
    conf_file <- "ddCt.conf"
    
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "is missing from the working directory."))
    }
    
    # Set up the parameter list as documented, adapting paths to the working directory
    params <- list(
      loadPath = getwd(),
      savePath = getwd()
    )
    
    # Configure optional files if they exist in the working directory
    if (file.exists(conf_file)) {
      params\$confFile <- conf_file
    } else {
      # Fallback to the default configuration file from the package if local is not present
      default_conf <- file.path(ddct_path, "scripts", "ddCt.conf")
      params\$confFile <- if (file.exists(default_conf)) default_conf else NULL
    }
    
    params\$inputFile <- input_file
    
    if (file.exists(anno_file)) {
      params\$sampleAnnotationFile <- anno_file
    } else {
      params\$sampleAnnotationFile <- NULL
    }
    
    # Reproduce the documented parameters faithfully
    params\$columnForGrouping    <- NULL
    params\$onlyFromAnnotation   <- FALSE
    params\$referenceGene        <- c("Gene1", "Gene2")
    params\$referenceSample      <- c("Sample1")
    params\$threshold            <- 40
    params\$mode                 <- "median"
    params\$plotMode             <- c("level", "Ct")
    params\$genesRemainInOutput   <- NULL
    params\$samplesRemainInOutput <- NULL
    params\$genesNotInOutput      <- NULL
    params\$samplesNotInOutput    <- NULL
    params\$groupingBySamples    <- FALSE
    params\$plotPerObject        <- TRUE
    params\$legende              <- TRUE
    params\$ttestPerform         <- FALSE
    
    # Execute the high-level pipeline
    # ddCtExec will process the files and write the outputs (CSV, PDF, RData) to the savePath (getwd())
    ddCtExec(params)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_DDCT_DDCT_HIGH_LEVEL_PIPELINE":
        ddct: \$(Rscript -e 'cat(as.character(packageVersion("ddct")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ddct_high_level_pipeline.csv versions.yml
    """
}

workflow BIOC_DDCT_DDCT_HIGH_LEVEL_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Experiment1.txt, SampleAnno.txt, ddCt.conf ] ]

    main:
    BIOC_DDCT_DDCT_HIGH_LEVEL_PIPELINE(ch_input)

    emit:
    tables   = BIOC_DDCT_DDCT_HIGH_LEVEL_PIPELINE.out.tables
    plots    = BIOC_DDCT_DDCT_HIGH_LEVEL_PIPELINE.out.plots
    objects  = BIOC_DDCT_DDCT_HIGH_LEVEL_PIPELINE.out.objects
    versions = BIOC_DDCT_DDCT_HIGH_LEVEL_PIPELINE.out.versions
}
