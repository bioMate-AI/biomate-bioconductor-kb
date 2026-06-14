#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: AssessORF — assess_orf_predictions
// Map evolutionary conservation and/or proteomics evidence to a central genome and assess the quality of predicted gene boundaries.
// Input: databaseFile, geneLeftPos, geneRightPos, geneStrand
// Container: quay.io/biocontainers/bioconductor-assessorf:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: AssessORF, RSQLite
// Visualizations: mosaic plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Inputs
//  * 2. [Visualization & Output] Extract Identifiers from the SQLite Database
//  * 3. [Visualization & Output] Map Evolutionary Conservation Data
//  * 4. [Visualization & Output] Assess Predicted Genes
//  * 5. [Visualization & Output] Visualize and Save Results
//  * 6. [Visualization & Output] Compare Results with an Alternative Prediction Set

nextflow.enable.dsl = 2

process BIOC_ASSESSORF_ASSESS_ORF_PREDICTIONS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("DECIPHER", "AssessORF", "RSQLite")
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
    
    library(DECIPHER)
    library(AssessORF)
    library(RSQLite)
    
    # -----------------------------------------------------------------------------
    # --- Read User Inputs ---
    # -----------------------------------------------------------------------------
    databaseFile <- "databaseFile"
    if (!file.exists(databaseFile) && file.exists("databaseFile.sqlite")) {
      databaseFile <- "databaseFile.sqlite"
    }
    
    if (!file.exists(databaseFile)) {
      stop("Error: databaseFile not found in the working directory.")
    }
    
    if (!file.exists("geneLeftPos") || !file.exists("geneRightPos") || !file.exists("geneStrand")) {
      stop("Error: geneLeftPos, geneRightPos, or geneStrand files not found in the working directory.")
    }
    
    geneLeftPos <- as.numeric(readLines("geneLeftPos"))
    geneRightPos <- as.numeric(readLines("geneRightPos"))
    geneStrand <- readLines("geneStrand")
    
    # -----------------------------------------------------------------------------
    # --- Extract Identifiers from the SQLite Database ---
    # -----------------------------------------------------------------------------
    dbConn <- dbConnect(SQLite(), databaseFile)
    tables <- dbListTables(dbConn)
    if ("Seqs" %in% tables) {
      identifiers <- dbGetQuery(dbConn, "SELECT DISTINCT identifier FROM Seqs")\$identifier
    } else {
      stop("Error: 'Seqs' table not found in the provided DECIPHER database.")
    }
    dbDisconnect(dbConn)
    
    if (length(identifiers) < 1) {
      stop("Error: No genome identifiers found in the database.")
    }
    
    # -----------------------------------------------------------------------------
    # --- Map Evolutionary Conservation Data ---
    # -----------------------------------------------------------------------------
    # If there are no related genomes, fallback to using the central genome identifier
    related_IDs <- identifiers[-1]
    if (length(related_IDs) == 0) {
      related_IDs <- identifiers[1]
    }
    
    myMapObj <- MapAssessmentData(databaseFile,
                                  central_ID = identifiers[1],
                                  related_IDs = related_IDs,
                                  speciesName = "Central Species",
                                  useProt = FALSE)
    
    currMapObj <- myMapObj
    
    # -----------------------------------------------------------------------------
    # --- Assess Predicted Genes ---
    # -----------------------------------------------------------------------------
    prodigalLeft <- geneLeftPos
    prodigalRight <- geneRightPos
    prodigalStrand <- geneStrand
    
    currResObj <- AssessGenes(geneLeftPos = prodigalLeft,
                              geneRightPos = prodigalRight,
                              geneStrand = prodigalStrand,
                              inputMapObj = currMapObj,
                              geneSource = "Prodigal")
    
    # -----------------------------------------------------------------------------
    # --- Visualize and Save Results ---
    # -----------------------------------------------------------------------------
    # Print summary to console and save to text file
    print(currResObj)
    summary_text <- capture.output(print(currResObj))
    writeLines(summary_text, "assessment_summary.txt")
    
    # Save RDS objects
    saveRDS(currMapObj, "assessment_map_object.rds")
    saveRDS(currResObj, "assessment_results_object.rds")
    
    # Determine a safe range for the genome viewer plot based on central genome length
    genome_length <- 150000
    tryCatch({
      dbConn <- dbConnect(SQLite(), databaseFile)
      seq_len_query <- dbGetQuery(dbConn, sprintf("SELECT SUM(width) as total_width FROM Seqs WHERE identifier = '%s'", identifiers[1]))
      if (nrow(seq_len_query) > 0 && !is.na(seq_len_query\$total_width[1])) {
        genome_length <- seq_len_query\$total_width[1]
      }
      dbDisconnect(dbConn)
    }, error = function(e) {})
    
    rangeStart_GV <- 106000
    rangeEnd_GV <- 120000
    
    if (genome_length < 120000) {
      rangeStart_GV <- 1
      rangeEnd_GV <- min(50000, genome_length)
    }
    
    # Save plots to PDF
    pdf("assessment_plots.pdf", width = 11, height = 8.5)
    
    plot(currResObj)
    
    plot(currMapObj, currResObj, interactive_GV = FALSE,
         rangeStart_GV = rangeStart_GV, rangeEnd_GV = rangeEnd_GV)
    
    mosaicplot(currResObj)
    
    dev.off()
    
    # -----------------------------------------------------------------------------
    # --- Compare Results with an Alternative Prediction Set ---
    # -----------------------------------------------------------------------------
    # Simulate a second prediction program (e.g., GeneMarkS2) using a subset of the genes
    half_idx <- seq(1, length(geneLeftPos), by = 2)
    resObj2 <- AssessGenes(geneLeftPos = geneLeftPos[half_idx],
                           geneRightPos = geneRightPos[half_idx],
                           geneStrand = geneStrand[half_idx],
                           inputMapObj = currMapObj,
                           geneSource = "GeneMarkS2")
    
    comparison <- CompareAssessmentResults(currResObj, resObj2)
    print(comparison)
    
    comparison_text <- capture.output(CompareAssessmentResults(currResObj, resObj2))
    writeLines(comparison_text, "assessment_comparison.txt")

    writeLines(c(
        '"BIOC_ASSESSORF_ASSESS_ORF_PREDICTIONS":',
        paste0('    AssessORF: ', as.character(packageVersion('AssessORF')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_assess_orf_predictions.csv versions.yml
    """
}

workflow BIOC_ASSESSORF_ASSESS_ORF_PREDICTIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ databaseFile, geneLeftPos, geneRightPos, geneStrand ] ]

    main:
    BIOC_ASSESSORF_ASSESS_ORF_PREDICTIONS(ch_input)

    emit:
    tables   = BIOC_ASSESSORF_ASSESS_ORF_PREDICTIONS.out.tables
    plots    = BIOC_ASSESSORF_ASSESS_ORF_PREDICTIONS.out.plots
    objects  = BIOC_ASSESSORF_ASSESS_ORF_PREDICTIONS.out.objects
    versions = BIOC_ASSESSORF_ASSESS_ORF_PREDICTIONS.out.versions
}
