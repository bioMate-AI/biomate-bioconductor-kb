#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: biodbUniprot — uniprot_functional_annotation
// Retrieve UniProt functional annotations for a list of protein/gene identifiers and merge them with input feature data.
// Input: input.csv
// Container: 1.12.0--r44hdfd78af_0
// R packages: biodb, biodbUniprot
// Bioconductor: 3.20 | R: 4.4
// Requires: biodb, biodbUniprot
// Visualizations: bar plot
// QC: missing-value handling
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIODBUNIPROT_UNIPROT_FUNCTIONAL_ANNOTATION {
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
    .bm_deps <- c("biodb", "biodbUniprot")
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
    
    # --- Load required libraries safely ---
    library(biodb)
    library(biodbUniprot)
    
    # --- Read and parse input defensively ---
    input_file <- "input.csv"
    if (!file.exists(input_file)) {
      stop(paste("Input file not found:", input_file))
    }
    
    input_df <- read.csv(input_file, stringsAsFactors = FALSE, check.names = FALSE)
    
    # Identify the column containing identifiers
    id_col <- NULL
    if ("feature_id" %in% colnames(input_df)) {
      id_col <- "feature_id"
    } else if (ncol(input_df) > 0) {
      # Fallback to the first column
      id_col <- colnames(input_df)[1]
    } else {
      stop("Input CSV is empty or has no readable columns.")
    }
    
    raw_ids <- as.character(input_df[[id_col]])
    
    # Helper function to extract UniProt accession using standard regex
    extract_uniprot_accession <- function(x) {
      # Matches standard UniProt accession formats (e.g., P12345, Q9Y263)
      m <- regexpr("[OPQ][0-9][A-Z0-9]{3}[0-9]|[A-NR-Z][0-9]([A-Z][A-Z0-9]{2}[0-9]){1,2}", x)
      regmatches(x, m)
    }
    
    # Create a mapping table from original IDs to extracted UniProt accessions
    mapping_df <- data.frame(
      original_id = raw_ids,
      accession = NA_character_,
      stringsAsFactors = FALSE
    )
    
    for (i in seq_along(raw_ids)) {
      acc <- extract_uniprot_accession(raw_ids[i])
      if (length(acc) > 0) {
        mapping_df\$accession[i] <- acc
      }
    }
    
    # Filter unique valid accessions for querying
    unique_accessions <- unique(na.omit(mapping_df\$accession))
    
    # --- Initialize biodb and UniProt connector ---
    message("Initializing biodb UniProt connector...")
    bd <- biodb::newBiodb()
    conn <- bd\$getFactory()\$createConn('uniprot')
    
    # --- Query UniProt database ---
    annot_df <- data.frame()
    
    if (length(unique_accessions) > 0) {
      message(paste("Querying UniProt for", length(unique_accessions), "accessions..."))
      
      entries <- tryCatch({
        conn\$getEntry(unique_accessions)
      }, error = function(e) {
        message("Error during UniProt query: ", e\$message)
        NULL
      })
      
      if (!is.null(entries)) {
        # Ensure entries is a list
        if (!is.list(entries) && inherits(entries, "BiodbEntry")) {
          entries <- list(entries)
        }
        
        # Convert entries to data frame
        tryCatch({
          annot_df <- conn\$entriesToDf(entries)
        }, error = function(e) {
          message("Standard entriesToDf failed, falling back to manual extraction...")
          # Manual extraction fallback
          rows <- lapply(entries, function(entry) {
            if (is.null(entry)) return(NULL)
            fields <- c('accession', 'name', 'gene', 'organism', 'description', 'sequence')
            row_data <- lapply(fields, function(f) {
              val <- tryCatch(entry\$getFieldValue(f), error = function(err) NULL)
              if (is.null(val)) return(NA)
              if (length(val) > 1) return(paste(val, collapse="; "))
              return(as.character(val))
            })
            names(row_data) <- fields
            return(as.data.frame(row_data, stringsAsFactors = FALSE))
          })
          annot_df <- do.call(rbind, rows)
        })
      }
    } else {
      message("No valid UniProt accessions detected in the input file.")
    }
    
    # --- Merge annotations back with original data ---
    if (!is.null(annot_df) && nrow(annot_df) > 0) {
      # Ensure accession column is present for merging
      if (!"accession" %in% colnames(annot_df) && "id" %in% colnames(annot_df)) {
        colnames(annot_df)[colnames(annot_df) == "id"] <- "accession"
      }
      
      # Merge mapping with annotations
      full_mapping <- merge(mapping_df, annot_df, by = "accession", all.x = TRUE)
      
      # Merge back with original input data frame
      final_df <- merge(input_df, full_mapping, by.x = id_col, by.y = "original_id", all.x = TRUE)
    } else {
      message("No annotations retrieved. Returning original data with empty annotation columns.")
      final_df <- input_df
      final_df\$accession <- NA
      final_df\$name <- NA
      final_df\$gene <- NA
      final_df\$organism <- NA
      final_df\$description <- NA
      final_df\$sequence <- NA
    }
    
    # Write the annotated dataset
    write.csv(final_df, "annotated_uniprot_features.csv", row.names = FALSE)
    message("Saved annotated features to annotated_uniprot_features.csv")
    
    # --- Visualization and Diagnostics ---
    pdf("uniprot_summary.pdf", width = 8, height = 6)
    
    if (!is.null(annot_df) && nrow(annot_df) > 0) {
      # Plot 1: Organism distribution
      if ("organism" %in% colnames(annot_df)) {
        org_counts <- table(annot_df\$organism)
        if (length(org_counts) > 0) {
          # Limit to top 10 organisms to keep plot clean
          org_counts <- sort(org_counts, decreasing = TRUE)
          if (length(org_counts) > 10) {
            org_counts <- c(org_counts[1:10], "Other" = sum(org_counts[11:length(org_counts)]))
          }
          par(mar = c(5, 12, 4, 2))
          barplot(org_counts, las = 2, horiz = TRUE, col = "skyblue",
                  main = "Organism Distribution of Annotated Proteins",
                  xlab = "Count")
        }
      }
      
      # Plot 2: Sequence length distribution
      if ("sequence" %in% colnames(annot_df)) {
        seq_lengths <- nchar(na.omit(annot_df\$sequence))
        if (length(seq_lengths) > 0) {
          par(mar = c(5, 5, 4, 2))
          hist(seq_lengths, breaks = 20, col = "lightgreen",
               main = "Distribution of Protein Sequence Lengths",
               xlab = "Sequence Length (amino acids)", ylab = "Frequency")
        }
      }
    } else {
      # Fallback empty plot with message
      plot(1, 1, type = "n", xlab = "", ylab = "", axes = FALSE,
           main = "No UniProt Annotations Found")
      text(1, 1, "Could not retrieve UniProt annotations for the provided identifiers.\nCheck that your input contains valid UniProt Accessions.", cex = 1.2)
    }
    
    dev.off()
    message("Saved summary plots to uniprot_summary.pdf")
    
    # Clean up biodb instance
    bd\$terminate()

    writeLines(c(
        '"BIOC_BIODBUNIPROT_UNIPROT_FUNCTIONAL_ANNOTATION":',
        paste0('    biodbUniprot: ', as.character(packageVersion('biodbUniprot')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_uniprot_functional_annotation.csv versions.yml
    """
}

workflow BIOC_BIODBUNIPROT_UNIPROT_FUNCTIONAL_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BIODBUNIPROT_UNIPROT_FUNCTIONAL_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_BIODBUNIPROT_UNIPROT_FUNCTIONAL_ANNOTATION.out.tables
    plots    = BIOC_BIODBUNIPROT_UNIPROT_FUNCTIONAL_ANNOTATION.out.plots
    objects  = BIOC_BIODBUNIPROT_UNIPROT_FUNCTIONAL_ANNOTATION.out.objects
    versions = BIOC_BIODBUNIPROT_UNIPROT_FUNCTIONAL_ANNOTATION.out.versions
}
