#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: biodbNci — nci_cactus_annotation
// Annotate a list of chemical identifiers (names, CAS, or NSC numbers) with structural and chemical metadata from the NCI CACTUS database.
// Input: input.csv
// Container: 1.10.0--r44he5774e6_0
// R packages: biodb, biodbNci
// Bioconductor: 3.20 | R: 4.4
// Requires: biodb, biodbNci
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIODBNCI_NCI_CACTUS_ANNOTATION {
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
    .bm_deps <- c("biodb", "biodbNci")
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
    
    # --- Load required libraries safely ---
    library(biodb)
    library(biodbNci)
    
    # --- Read and parse input defensively ---
    input_file <- "input.csv"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    data <- read.csv(input_file, stringsAsFactors = FALSE, check.names = FALSE)
    
    # Extract identifiers from the input
    # Supports: 'feature_id' column, single-column list, or row names
    if ("feature_id" %in% colnames(data)) {
      ids <- data\$feature_id
    } else if (ncol(data) == 1) {
      ids <- data[[1]]
    } else {
      ids <- rownames(data)
    }
    
    # Clean and deduplicate identifiers
    ids <- unique(as.character(ids))
    ids <- ids[ids != "" & !is.na(ids)]
    
    if (length(ids) == 0) {
      stop("No valid chemical identifiers found in the input file.")
    }
    
    message(paste("Loaded", length(ids), "unique identifiers for NCI CACTUS annotation."))
    
    # --- Initialize biodb and the NCI connector ---
    bd <- biodb::newBiodb()
    conn <- bd\$getFactory()\$createConn('nci')
    
    # --- Query NCI CACTUS database with error handling ---
    entries <- list()
    for (id in ids) {
      message(paste("Querying NCI CACTUS for:", id))
      tryCatch({
        # Retrieve entry using the biodb connector
        entry <- conn\$getEntry(id)
        if (!is.null(entry)) {
          entries <- c(entries, entry)
        }
      }, error = function(e) {
        warning(paste("Failed to retrieve entry for:", id, "-", e\$message))
      })
    }
    
    # --- Process results and build output dataframe ---
    if (length(entries) > 0) {
      # Convert retrieved biodb entries to a standard data frame
      df_entries <- bd\$entriesToDataframe(entries)
      message(paste("Successfully annotated", nrow(df_entries), "compounds."))
    } else {
      warning("No annotations could be retrieved from NCI CACTUS.")
      # Fallback to an empty dataframe with expected columns
      df_entries <- data.frame(
        query_id = ids,
        name = NA,
        formula = NA,
        molecular.weight = NA,
        smiles = NA,
        inchi = NA,
        stringsAsFactors = FALSE
      )
    }
    
    # Write the annotation results to CSV
    write.csv(df_entries, "nci_annotations.csv", row.names = FALSE)
    message("Saved annotations to 'nci_annotations.csv'.")
    
    # --- Generate diagnostic visualization ---
    pdf("mass_distribution.pdf", width = 7, height = 5)
    
    # Check if molecular weight column exists and has numeric values
    mw_col <- grep("molecular.weight|mass|mw", colnames(df_entries), value = TRUE, ignore.case = TRUE)
    has_mw <- FALSE
    
    if (length(mw_col) > 0) {
      mw_values <- as.numeric(df_entries[[mw_col[1]]])
      mw_values <- mw_values[!is.na(mw_values)]
      if (length(mw_values) > 0) {
        has_mw <- TRUE
        hist(mw_values, 
             col = "skyblue", 
             border = "white",
             main = "Molecular Weight Distribution of Annotated Compounds",
             xlab = "Molecular Weight (g/mol)",
             ylab = "Frequency")
      }
    }
    
    if (!has_mw) {
      # Fallback plot if no molecular weight data is available
      plot(1, type = "n", axes = FALSE, xlab = "", ylab = "")
      text(1, 1, "No Molecular Weight data available\nfor visualization.", cex = 1.2, col = "red")
    }
    
    dev.off()
    message("Saved visualization to 'mass_distribution.pdf'.")
    
    # --- Clean up biodb instance ---
    bd\$terminate()
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_BIODBNCI_NCI_CACTUS_ANNOTATION":',
        paste0('    biodbNci: ', as.character(packageVersion('biodbNci')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nci_cactus_annotation.csv versions.yml
    """
}

workflow BIOC_BIODBNCI_NCI_CACTUS_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BIODBNCI_NCI_CACTUS_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_BIODBNCI_NCI_CACTUS_ANNOTATION.out.tables
    plots    = BIOC_BIODBNCI_NCI_CACTUS_ANNOTATION.out.plots
    objects  = BIOC_BIODBNCI_NCI_CACTUS_ANNOTATION.out.objects
    versions = BIOC_BIODBNCI_NCI_CACTUS_ANNOTATION.out.versions
}
