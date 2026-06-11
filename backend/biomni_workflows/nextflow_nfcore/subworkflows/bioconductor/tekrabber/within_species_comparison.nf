#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TEKRABber — within_species_comparison
// Compare gene and transposable element (TE) expression and estimate their correlations between control and treatment samples within the same species.
// Input: geneInputDE, teInputDE
// Container: quay.io/biocontainers/bioconductor-tekrabber:1.14.1--r45ha27e39d_0
// R packages: TEKRABber
// Bioconductor: 3.20 | R: 4.4
// Requires: TEKRABber
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform differential expression analysis using DEgeneTE() with expDesign = FALSE
//  * 2. [Core Analysis] Estimate correlations between genes and TEs using corrOrthologTE()
//  * 3. [Visualization & Output] Visualize results using appTEKRABber()

nextflow.enable.dsl = 2

process BIOC_TEKRABBER_WITHIN_SPECIES_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("TEKRABber")
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
        library(TEKRABber)
        
        # Helper function to robustly read input files from the working directory
        # and format them with the first column (Ensembl IDs / TE names) as rownames
        read_input_table <- function(filepath) {
          if (!file.exists(filepath)) {
            stop(paste("Required input file not found in working directory:", filepath))
          }
          
          # Try reading as CSV first
          df <- tryCatch({
            read.csv(filepath, header = TRUE, check.names = FALSE, stringsAsFactors = FALSE)
          }, error = function(e) NULL)
          
          # If it has only 1 column or failed, try reading as TSV
          if (is.null(df) || ncol(df) <= 1) {
            df <- read.delim(filepath, header = TRUE, check.names = FALSE, stringsAsFactors = FALSE)
          }
          
          if (is.null(df) || ncol(df) <= 1) {
            stop(paste("Failed to read", filepath, "properly. Please ensure it is a valid CSV or TSV file."))
          }
          
          # Set the first column as rownames and remove it from the data frame
          rownames(df) <- df[, 1]
          df <- df[, -1, drop = FALSE]
          return(df)
        }
        
        # 1. Read user input files
        geneInputDE <- read_input_table("geneInputDE")
        teInputDE <- read_input_table("teInputDE")
        
        # 2. Dynamically construct metadata based on the input columns
        samples <- colnames(geneInputDE)
        is_control <- grepl("control", samples, ignore.case = TRUE)
        is_treatment <- grepl("treatment", samples, ignore.case = TRUE)
        
        if (sum(is_control) > 0 || sum(is_treatment) > 0) {
          experiment_vec <- character(length(samples))
          experiment_vec[is_control] <- "control"
          experiment_vec[is_treatment] <- "treatment"
          # Fallback for any columns that don't match
          experiment_vec[experiment_vec == ""] <- "control"
        } else {
          # Fallback if no keywords are found: assume first half is control, second half is treatment
          half <- length(samples) / 2
          experiment_vec <- c(rep("control", floor(half)), rep("treatment", ceiling(half)))
        }
        
        metaExp <- data.frame(experiment = experiment_vec)
        rownames(metaExp) <- colnames(geneInputDE)
        metaExp\$experiment <- factor(
            metaExp\$experiment, 
            levels = c("control", "treatment")
        )
        
        # 3. Perform differential expression analysis
        resultDE <- DEgeneTE(
            geneTable = geneInputDE,
            teTable = teInputDE,
            metadata = metaExp,
            expDesign = FALSE
        )
        
        # 4. Estimate correlations for control samples
        controlCorr <- corrOrthologTE(
            geneInput = resultDE\$geneCorrInputRef,
            teInput = resultDE\$teCorrInputRef,
            numCore = 1,
            corrMethod = "pearson",
            padjMethod = "fdr"
        )
        
        # 5. Estimate correlations for treatment samples
        treatmentCorr <- corrOrthologTE(
            geneInput = resultDE\$geneCorrInputCompare,
            teInput = resultDE\$teCorrInputCompare,
            numCore = 1,
            corrMethod = "pearson",
            padjMethod = "fdr"
        )
        
        # 6. Save meaningful results to the working directory
        write.csv(controlCorr, "control_correlation_results.csv", row.names = TRUE)
        write.csv(treatmentCorr, "treatment_correlation_results.csv", row.names = TRUE)
        saveRDS(resultDE, "resultDE.rds")
        saveRDS(controlCorr, "controlCorr.rds")
        saveRDS(treatmentCorr, "treatmentCorr.rds")
        
        # 7. Visualize results using appTEKRABber (only in interactive sessions)
        if (interactive()) {
            appTEKRABber(
                corrRef = controlCorr,
                corrCompare = treatmentCorr,
                DEobject = resultDE
            )
        } else {
            message("Skipping interactive appTEKRABber() launch because session is non-interactive.")
        }

    writeLines(c(
        '"BIOC_TEKRABBER_WITHIN_SPECIES_COMPARISON":',
        paste0('    TEKRABber: ', as.character(packageVersion('TEKRABber')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_within_species_comparison.csv versions.yml
    """
}

workflow BIOC_TEKRABBER_WITHIN_SPECIES_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ geneInputDE, teInputDE ] ]

    main:
    BIOC_TEKRABBER_WITHIN_SPECIES_COMPARISON(ch_input)

    emit:
    tables   = BIOC_TEKRABBER_WITHIN_SPECIES_COMPARISON.out.tables
    plots    = BIOC_TEKRABBER_WITHIN_SPECIES_COMPARISON.out.plots
    objects  = BIOC_TEKRABBER_WITHIN_SPECIES_COMPARISON.out.objects
    versions = BIOC_TEKRABBER_WITHIN_SPECIES_COMPARISON.out.versions
}
