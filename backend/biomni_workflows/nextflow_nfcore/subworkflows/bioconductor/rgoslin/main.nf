#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rgoslin — lipid_nomenclature_normalization
// Parse, validate, and normalize lipid shorthand names from a feature matrix, and aggregate abundance data by lipid class.
// Input: input.csv
// Container: 1.14.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: rgoslin
// Visualizations: bar plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RGOSLIN_LIPID_NOMENCLATURE_NORMALIZATION {
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
    .bm_deps <- c("rgoslin")
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
    
    # --- Load libraries and inspect available grammars ---
    library(rgoslin)
    
    message("Available grammars in rgoslin:")
    print(listAvailableGrammars())
    
    # --- Read and defensively preprocess input data ---
    if (!file.exists("input.csv")) {
      stop("Staged input file 'input.csv' not found.")
    }
    
    # Read input.csv defensively
    data <- read.csv("input.csv", stringsAsFactors = FALSE, check.names = FALSE)
    
    # Identify the column containing lipid names
    lipid_col <- NULL
    if ("feature_id" %in% colnames(data)) {
      lipid_col <- "feature_id"
    } else if (ncol(data) == 1) {
      lipid_col <- colnames(data)[1]
    } else {
      # Search for the first character column as a candidate for lipid names
      char_cols <- sapply(data, is.character)
      if (any(char_cols)) {
        lipid_col <- names(char_cols)[which(char_cols)[1]]
      } else {
        # Fallback to row names if no character columns exist
        data\$feature_id <- rownames(data)
        lipid_col <- "feature_id"
      }
    }
    
    message(paste("Using column '", lipid_col, "' for lipid nomenclature parsing.", sep = ""))
    raw_lipid_names <- as.character(data[[lipid_col]])
    
    # Clean common non-standard suffixes/prefixes (e.g., deuterated standards, ionization modes)
    # to maximize parsing success rate, following recommended practices
    clean_names <- raw_lipid_names
    clean_names <- gsub("\\\\(d[0-9]+\\\\)", "", clean_names) # Remove deuterated tags like (d7), (d9)
    clean_names <- gsub(" NEG\$", "", clean_names)         # Remove negative mode suffix
    clean_names <- gsub(" POS\$", "", clean_names)         # Remove positive mode suffix
    clean_names <- gsub("Sa1P", "SPBP", clean_names)      # Align sphinganine-1-phosphate with SPBP
    clean_names <- gsub("So1P", "SPBP", clean_names)      # Align sphingosine-1-phosphate with SPBP
    clean_names <- trimws(clean_names)
    
    # --- Validate and Parse Lipid Names ---
    message("Validating lipid names...")
    is_valid <- sapply(clean_names, isValidLipidName)
    
    # Parse valid lipid names
    parsed_results <- NULL
    valid_indices <- which(is_valid)
    
    if (length(valid_indices) > 0) {
      unique_valid_names <- unique(clean_names[valid_indices])
      message(paste("Parsing", length(unique_valid_names), "unique valid lipid names..."))
      
      parsed_results <- tryCatch({
        parseLipidNames(unique_valid_names)
      }, error = function(e) {
        message("Batch parsing failed. Attempting individual parsing fallback...")
        individual_list <- lapply(unique_valid_names, function(nm) {
          tryCatch({
            parseLipidNames(nm)
          }, error = function(err) {
            NULL
          })
        })
        do.call(rbind, individual_list)
      })
    } else {
      message("Warning: No lipid names passed initial validation.")
    }
    
    # --- Merge Parsed Metadata with Original Data ---
    mapping_df <- data.frame(
      Original_Input_Name = raw_lipid_names,
      Cleaned_Name = clean_names,
      Is_Valid = is_valid,
      stringsAsFactors = FALSE
    )
    
    if (!is.null(parsed_results) && nrow(parsed_results) > 0) {
      # Merge parsed results back to the mapping using the Cleaned_Name matching Original.Name
      merged_mapping <- merge(mapping_df, parsed_results, by.x = "Cleaned_Name", by.y = "Original.Name", all.x = TRUE)
      # Reorder to match original input row order
      final_metadata <- merged_mapping[match(raw_lipid_names, merged_mapping\$Original_Input_Name), ]
    } else {
      final_metadata <- mapping_df
    }
    
    # Combine original data with the parsed metadata
    output_data <- cbind(data, final_metadata)
    write.csv(output_data, "normalized_lipids.csv", row.names = FALSE)
    message("Saved normalized lipid metadata to 'normalized_lipids.csv'")
    
    # --- Downstream Abundance Aggregation (if numeric sample ---
    num_cols <- sapply(data, is.numeric)
    sample_cols <- names(num_cols)[num_cols]
    
    if (length(sample_cols) > 0 && "Lipid.Maps.Main.Class" %in% colnames(output_data)) {
      message("Aggregating sample intensities by Lipid Maps Main Class...")
      # Handle missing or unparsed classes
      classes <- output_data\$Lipid.Maps.Main.Class
      classes[is.na(classes) | classes == ""] <- "Unparsed/Unknown"
      
      class_abundance <- aggregate(output_data[, sample_cols, drop = FALSE], 
                                   by = list(Class = classes), 
                                   FUN = sum, na.rm = TRUE)
      write.csv(class_abundance, "lipid_class_abundance.csv", row.names = FALSE)
    } else {
      write.csv(data.frame(Message = "No numeric sample columns or Lipid.Maps.Main.Class found for aggregation"), 
                "lipid_class_abundance.csv", row.names = FALSE)
    }
    
    # --- Structural Summary Statistics ---
    if (all(c("Total.C", "Total.DB", "Lipid.Maps.Main.Class") %in% colnames(output_data))) {
      valid_parsed <- output_data[!is.na(output_data\$Normalized.Name), ]
      if (nrow(valid_parsed) > 0) {
        summary_stats <- aggregate(cbind(Total.C, Total.DB) ~ Lipid.Maps.Main.Class, 
                                   data = valid_parsed, 
                                   FUN = function(x) c(Mean = mean(x, na.rm = TRUE), Min = min(x, na.rm = TRUE), Max = max(x, na.rm = TRUE)))
        
        # Flatten the aggregated matrix columns
        summary_df <- data.frame(
          Class = summary_stats\$Lipid.Maps.Main.Class,
          Mean_Carbon = summary_stats\$Total.C[, "Mean"],
          Min_Carbon = summary_stats\$Total.C[, "Min"],
          Max_Carbon = summary_stats\$Total.C[, "Max"],
          Mean_DoubleBonds = summary_stats\$Total.DB[, "Mean"],
          Min_DoubleBonds = summary_stats\$Total.DB[, "Min"],
          Max_DoubleBonds = summary_stats\$Total.DB[, "Max"]
        )
        write.csv(summary_df, "lipid_structural_summary.csv", row.names = FALSE)
      } else {
        write.csv(data.frame(Message = "No successfully parsed lipids to summarize"), "lipid_structural_summary.csv", row.names = FALSE)
      }
    } else {
      write.csv(data.frame(Message = "Required structural columns (Total.C, Total.DB, Lipid.Maps.Main.Class) not found"), 
                "lipid_structural_summary.csv", row.names = FALSE)
    }
    
    # --- Diagnostic Visualizations ---
    pdf("lipid_analysis_plots.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2), mar = c(6, 4, 4, 2) + 0.1)
    
    # Plot 1: Lipid Class Distribution Barplot
    if ("Lipid.Maps.Main.Class" %in% colnames(output_data)) {
      classes_for_plot <- output_data\$Lipid.Maps.Main.Class
      classes_for_plot[is.na(classes_for_plot) | classes_for_plot == ""] <- "Unparsed"
      class_counts <- table(classes_for_plot)
      
      barplot(class_counts, las = 2, col = "skyblue", 
              main = "Lipid Class Distribution", 
              ylab = "Number of Features", cex.names = 0.7)
    } else {
      plot(1, 1, type = "n", xlab = "", ylab = "", main = "No Class Data Available")
      text(1, 1, "No Class Data")
    }
    
    # Plot 2: Structural Space Scatter Plot (Carbon vs Double Bonds)
    if (all(c("Total.C", "Total.DB") %in% colnames(output_data))) {
      valid_struct <- output_data[!is.na(output_data\$Total.C) & !is.na(output_data\$Total.DB), ]
      if (nrow(valid_struct) > 0) {
        # Jitter points slightly to prevent overplotting on discrete values
        jitter_c <- jitter(valid_struct\$Total.C, amount = 0.15)
        jitter_db <- jitter(valid_struct\$Total.DB, amount = 0.08)
        
        if ("Lipid.Maps.Main.Class" %in% colnames(valid_struct)) {
          class_factor <- as.factor(valid_struct\$Lipid.Maps.Main.Class)
          palette_colors <- rainbow(length(levels(class_factor)))
          
          plot(jitter_c, jitter_db, col = palette_colors[class_factor], pch = 19,
               xlab = "Total Carbons", ylab = "Total Double Bonds",
               main = "Lipid Structural Space")
          legend("topleft", legend = levels(class_factor), col = palette_colors, pch = 19, cex = 0.6, bty = "n")
        } else {
          plot(jitter_c, jitter_db, pch = 19, col = "darkblue",
               xlab = "Total Carbons", ylab = "Total Double Bonds",
               main = "Lipid Structural Space")
        }
      } else {
        plot(1, 1, type = "n", xlab = "", ylab = "", main = "No Structural Data Available")
        text(1, 1, "No Structural Data")
      }
    } else {
      plot(1, 1, type = "n", xlab = "", ylab = "", main = "No Structural Data Available")
      text(1, 1, "No Structural Data")
    }
    
    dev.off()
    message("Saved diagnostic plots to 'lipid_analysis_plots.pdf'")
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_RGOSLIN_LIPID_NOMENCLATURE_NORMALIZATION":',
        paste0('    rgoslin: ', as.character(packageVersion('rgoslin')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lipid_nomenclature_normalization.csv versions.yml
    """
}

workflow BIOC_RGOSLIN_LIPID_NOMENCLATURE_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_RGOSLIN_LIPID_NOMENCLATURE_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_RGOSLIN_LIPID_NOMENCLATURE_NORMALIZATION.out.tables
    plots    = BIOC_RGOSLIN_LIPID_NOMENCLATURE_NORMALIZATION.out.plots
    objects  = BIOC_RGOSLIN_LIPID_NOMENCLATURE_NORMALIZATION.out.objects
    versions = BIOC_RGOSLIN_LIPID_NOMENCLATURE_NORMALIZATION.out.versions
}
