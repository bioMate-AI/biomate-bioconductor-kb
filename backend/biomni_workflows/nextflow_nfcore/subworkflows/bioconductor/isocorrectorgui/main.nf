#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: IsoCorrectoRGUI — isocorrectorgui_isotope_correction
// Perform natural stable isotope abundance and tracer purity correction on mass spectrometry data from stable isotope labeling experiments, and visualize the corr
// Input: intensity.csv, coldata.csv
// Container: 1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: IsoCorrectoR, IsoCorrectoRGUI
// Visualizations: box plot, enrichment plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISOCORRECTORGUI_ISOCORRECTORGUI_ISOTOPE_CORRECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("IsoCorrectoRGUI", "IsoCorrectoR")
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
    library(IsoCorrectoRGUI)
    library(IsoCorrectoR)
    
    # ==========================================
    # --- Load and Align User Input Data ---
    # ==========================================
    message("Stage 1: Loading and aligning input files...")
    
    # Read user input files
    intensity <- read.csv("intensity.csv", check.names = FALSE, stringsAsFactors = FALSE)
    coldata <- read.csv("coldata.csv", check.names = FALSE, stringsAsFactors = FALSE)
    
    # Identify the feature ID column
    if ("feature_id" %in% colnames(intensity)) {
      feat_col <- "feature_id"
    } else {
      feat_col <- colnames(intensity)[1]
    }
    
    # Set row names and extract numeric intensity matrix
    rownames(intensity) <- intensity[[feat_col]]
    intensity_data <- intensity[, setdiff(colnames(intensity), feat_col), drop = FALSE]
    
    # Align samples between intensity matrix and coldata
    common_samples <- intersect(colnames(intensity_data), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("Error: No matching samples found between intensity.csv and coldata.csv")
    }
    
    intensity_data <- intensity_data[, common_samples, drop = FALSE]
    coldata <- coldata[coldata\$sample %in% common_samples, ]
    
    # ==========================================
    # --- Construct IsoCorrectoR Input Files ---
    # ==========================================
    message("Stage 2: Generating molecule, measurement, and element files...")
    
    # Group features into simulated molecules of size 3 (representing M+0, M+1, M+2 isotopologues)
    n_rows <- nrow(intensity_data)
    block_size <- 3
    n_blocks <- ceiling(n_rows / block_size)
    
    new_row_names <- c()
    molecule_rows <- list()
    
    for (i in 1:n_blocks) {
      start_idx <- (i - 1) * block_size + 1
      end_idx <- min(i * block_size, n_rows)
      block_len <- end_idx - start_idx + 1
      
      mol_name <- paste0("Mol", i)
      block_names <- paste0(mol_name, "_", 0:(block_len - 1))
      new_row_names <- c(new_row_names, block_names)
      
      # Generate sum formula with appropriate tracer element core (LabC)
      # e.g., C6H12O2N1LabC2 for a 3-isotopologue block
      formula <- paste0("C6H12O2N1LabC", block_len - 1)
      molecule_rows[[i]] <- data.frame(
        Molecule = mol_name,
        `MS ion or MS/MS product ion` = formula,
        `MS/MS neutral loss` = "",
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
    }
    
    # Create measurement data frame with correct nomenclature
    measurement_df <- intensity_data
    rownames(measurement_df) <- new_row_names
    measurement_df <- cbind(`Measurements/Samples` = rownames(measurement_df), measurement_df)
    
    # Combine molecule definitions
    molecule_df <- do.call(rbind, molecule_rows)
    
    # Create standard element information file (resolution independent)
    element_df <- data.frame(
      Element = c("C", "H", "O", "N"),
      `Isotope abundance_Mass shift` = c(
        "0.0107_1/0.9893_0",
        "0.000115_1/0.999885_0",
        "0.99757_0/0.00038_1/0.00205_2",
        "0.99632_0/0.00368_1"
      ),
      `Tracer isotope mass shift` = c(1, NA, NA, NA),
      `Tracer purity` = c(0.99, NA, NA, NA),
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
    
    # Write temporary files required by the correction algorithm
    write.csv(measurement_df, "temp_measurement.csv", row.names = FALSE)
    write.csv(molecule_df, "temp_molecule.csv", row.names = FALSE)
    write.csv(element_df, "temp_element.csv", row.names = FALSE, na = "")
    
    # ==========================================
    # --- Perform Isotope Correction ---
    # ==========================================
    message("Stage 3: Running IsoCorrectoR algorithm...")
    
    # Check and log GUI status
    gui_status <- IsoCorrectoRGUI::GetGUIstatus()
    message("GUI Status: ", gui_status)
    
    # Run the core correction algorithm
    results <- IsoCorrectoR::IsoCorrection(
      MeasurementFile = "temp_measurement.csv",
      ElementFile = "temp_element.csv",
      MoleculeFile = "temp_molecule.csv",
      CorrectTracerImpurity = TRUE,
      CorrectTracerElementCore = TRUE,
      CalculateMeanEnrichment = TRUE,
      UltraHighRes = FALSE,
      DirOut = ".",
      FileOut = "corrected_results",
      FileOutFormat = "csv",
      ReturnResultsObject = TRUE,
      verbose = TRUE
    )
    
    # Clean up temporary input files
    file.remove("temp_measurement.csv", "temp_molecule.csv", "temp_element.csv")
    
    # ==========================================
    # --- Export Corrected Results ---
    # ==========================================
    message("Stage 4: Exporting corrected data...")
    
    corrected_data <- results\$results\$Corrected
    corrected_fractions <- results\$results\$CorrectedFractions
    mean_enrichment <- results\$results\$MeanEnrichment
    
    write.csv(corrected_data, "corrected_intensities.csv", row.names = TRUE)
    write.csv(corrected_fractions, "corrected_fractions.csv", row.names = TRUE)
    write.csv(mean_enrichment, "mean_enrichment.csv", row.names = TRUE)
    
    # ==========================================
    # --- Visualization of Mean Enrichment ---
    # ==========================================
    message("Stage 5: Generating diagnostic visualization...")
    
    pdf("mean_enrichment_plots.pdf", width = 8, height = 6)
    par(mfrow = c(2, 2), mar = c(4, 4, 3, 1))
    
    # Plot mean enrichment for the top molecules across conditions
    mols_to_plot <- head(rownames(mean_enrichment), 4)
    for (mol in mols_to_plot) {
      enrich_vals <- as.numeric(mean_enrichment[mol, coldata\$sample])
      
      # Generate boxplot grouped by experimental condition
      boxplot(enrich_vals ~ coldata\$condition,
              main = paste("Mean Enrichment:", mol),
              xlab = "Condition", 
              ylab = "Enrichment Fraction",
              col = c("#A6CEE3", "#B2DF8A"),
              outline = FALSE)
      
      # Overlay individual sample points
      stripchart(enrich_vals ~ coldata\$condition,
                 vertical = TRUE, 
                 method = "jitter",
                 add = TRUE, 
                 pch = 19, 
                 col = "darkgray")
    }
    dev.off()
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_ISOCORRECTORGUI_ISOCORRECTORGUI_ISOTOPE_CORRECTION":',
        paste0('    IsoCorrectoRGUI: ', as.character(packageVersion('IsoCorrectoRGUI')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_isocorrectorgui_isotope_correction.csv versions.yml
    """
}

workflow BIOC_ISOCORRECTORGUI_ISOCORRECTORGUI_ISOTOPE_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_ISOCORRECTORGUI_ISOCORRECTORGUI_ISOTOPE_CORRECTION(ch_input)

    emit:
    tables   = BIOC_ISOCORRECTORGUI_ISOCORRECTORGUI_ISOTOPE_CORRECTION.out.tables
    plots    = BIOC_ISOCORRECTORGUI_ISOCORRECTORGUI_ISOTOPE_CORRECTION.out.plots
    objects  = BIOC_ISOCORRECTORGUI_ISOCORRECTORGUI_ISOTOPE_CORRECTION.out.objects
    versions = BIOC_ISOCORRECTORGUI_ISOCORRECTORGUI_ISOTOPE_CORRECTION.out.versions
}
