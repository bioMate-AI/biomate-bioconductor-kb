#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: altcdfenvs — create_alternative_cdf_from_fasta
// Read custom target sequences from a FASTA file, match them against Affymetrix probe sequences, build a new alternative CDF environment, and prepare it for use w
// Input: sample.fasta, hgu133aprobe, abatch
// Container: quay.io/biocontainers/bioconductor-altcdfenvs:2.72.0--r45hdfd78af_0
// R packages: Biostrings, affy, altcdfenvs, hgu133acdf, hgu133aprobe, RColorBrewer, Rgraphviz
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, affy, altcdfenvs, hgu133aprobe
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Count FASTA entries using countskip.FASTA.entries
//  * 2. [Input & Preparation] Read FASTA entries using read.n.FASTA.entries.split
//  * 3. [Core Analysis] Match probes to target sequences using matchAffyProbes
//  * 4. [Input & Preparation] Build the alternative CDF environment using buildCdfEnv.biostrings
//  * 5. [Core Analysis] Validate and assign the new CDF environment to an AffyBatch object

nextflow.enable.dsl = 2

process BIOC_ALTCDFENVS_CREATE_ALTERNATIVE_CDF_FROM_FASTA {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Biostrings", "affy", "altcdfenvs", "hgu133acdf", "hgu133aprobe", "RColorBrewer", "Rgraphviz")
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
    library(altcdfenvs)
    library(affy)
    library(Biostrings)
    
    # 1. Read inputs from the working directory
    fasta.filename <- "sample.fasta"
    
    if (!file.exists(fasta.filename)) {
      stop("Error: 'sample.fasta' file not found in the working directory.")
    }
    
    # Read abatch object
    if (file.exists("abatch")) {
      abatch <- readRDS("abatch")
    } else if (file.exists("abatch.rds")) {
      abatch <- readRDS("abatch.rds")
    } else {
      stop("Error: 'abatch' file not found in the working directory.")
    }
    
    # Read hgu133aprobe object/package
    if (file.exists("hgu133aprobe")) {
      hgu133aprobe <- readRDS("hgu133aprobe")
    } else {
      # Fallback to loading the package if the file is not directly an RDS
      library(hgu133aprobe)
      hgu133aprobe <- get("hgu133aprobe")
    }
    
    # 2. Execute documented workflow exactly as specified
    con <- file(fasta.filename, open="r")
    n <- countskip.FASTA.entries(con)
    close(con)
    
    con <- file(fasta.filename, open="r")
    my.entries <- read.n.FASTA.entries.split(con, n)
    close(con)
    
    targets <- my.entries\$sequences
    names(targets) <-  sub(">.+\\\\|(Hs\\#|NM_)([^[:blank:]\\\\|]+).+", 
                           "\\1\\2", my.entries\$headers)
    
    m <- matchAffyProbes(hgu133aprobe, targets, "HG-U133A")
    
    alt.cdf <- 
      buildCdfEnv.biostrings(m, nrow.chip = 712, ncol.chip = 712)
    
    validAffyBatch(abatch, alt.cdf)
    
    alt.cdfenv <- alt.cdf@envir
    abatch@cdfName <- "alt.cdfenv"
    
    # Assign the environment to the global environment so that AffyBatch can resolve it by name
    assign("alt.cdfenv", alt.cdfenv, envir = .GlobalEnv)
    
    # 3. Save outputs
    saveRDS(abatch, "remapped_abatch.rds")
    saveRDS(alt.cdf, "alt_cdf.rds")
    
    cat("Workflow completed successfully. Outputs saved to 'remapped_abatch.rds' and 'alt_cdf.rds'.\n")

    writeLines(c(
        '"BIOC_ALTCDFENVS_CREATE_ALTERNATIVE_CDF_FROM_FASTA":',
        paste0('    altcdfenvs: ', as.character(packageVersion('altcdfenvs')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_create_alternative_cdf_from_fasta.csv versions.yml
    """
}

workflow BIOC_ALTCDFENVS_CREATE_ALTERNATIVE_CDF_FROM_FASTA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample.fasta, hgu133aprobe, abatch ] ]

    main:
    BIOC_ALTCDFENVS_CREATE_ALTERNATIVE_CDF_FROM_FASTA(ch_input)

    emit:
    tables   = BIOC_ALTCDFENVS_CREATE_ALTERNATIVE_CDF_FROM_FASTA.out.tables
    plots    = BIOC_ALTCDFENVS_CREATE_ALTERNATIVE_CDF_FROM_FASTA.out.plots
    objects  = BIOC_ALTCDFENVS_CREATE_ALTERNATIVE_CDF_FROM_FASTA.out.objects
    versions = BIOC_ALTCDFENVS_CREATE_ALTERNATIVE_CDF_FROM_FASTA.out.versions
}
