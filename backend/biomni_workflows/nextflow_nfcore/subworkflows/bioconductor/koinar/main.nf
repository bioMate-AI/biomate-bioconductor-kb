#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: koinar — peptide_fragment_intensity_prediction
// Predict peptide fragment ion intensities and m/z values using a remote Koina model.
// Input: peptide_data.csv
// Container: quay.io/biocontainers/bioconductor-koinar:1.4.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: koinar
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize the Koina client with a specific model and server using koinar::Koina()
//  * 2. [Input & Preparation] Prepare the input data frame with peptide sequences, collision energies, and precursor charges
//  * 3. [Input & Preparation] Fetch predictions using the $predict() method or koinar::predictWithKoinaModel()

nextflow.enable.dsl = 2

process BIOC_KOINAR_PEPTIDE_FRAGMENT_INTENSITY_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Check for required input file
    input_file <- "peptide_data.csv"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    # Read user input data
    input <- read.csv(input_file, stringsAsFactors = FALSE)
    
    # Ensure correct column types
    input\$peptide_sequences <- as.character(input\$peptide_sequences)
    input\$collision_energies <- as.numeric(input\$collision_energies)
    input\$precursor_charges <- as.integer(input\$precursor_charges)
    
    # 1. Initialize the Koina client with a specific model and server
    prosit2019 <- koinar::Koina(
      model_name = "Prosit_2019_intensity",
      server_url = "koina.wilhelmlab.org"
    )
    
    # 2. Fetch predictions using the \$predict() method
    prediction_results <- prosit2019\$predict(input)
    
    # 3. Fetch predictions using the alternative functional interface
    prediction_results_alt <- koinar::predictWithKoinaModel(prosit2019, input)
    
    # Save the prediction results to a CSV file
    write.csv(prediction_results, "prediction_results.csv", row.names = FALSE)
    
    # Generate a PDF plot of the predicted spectra for the first peptide in the input
    if (nrow(prediction_results) > 0) {
      pdf("predicted_spectra.pdf", width = 10, height = 7)
      
      # Get the first unique peptide sequence
      first_pep <- unique(prediction_results\$peptide_sequences)[1]
      pep_data <- prediction_results[prediction_results\$peptide_sequences == first_pep, ]
      
      # Plot the spectrum
      plot(pep_data\$intensities ~ pep_data\$mz,
        type = "n",
        ylim = c(0, 1.2),
        main = paste("Predicted Fragment Ion Spectrum for", first_pep),
        xlab = "m/z",
        ylab = "Relative Intensity"
      )
      
      # Highlight y-ions in red and other ions (like b-ions) in blue
      yIdx <- grepl("y", pep_data\$annotation)
      points(pep_data\$mz[yIdx], pep_data\$intensities[yIdx],
        col = "red", type = "h", lwd = 2
      )
      points(pep_data\$mz[!yIdx], pep_data\$intensities[!yIdx],
        col = "blue", type = "h", lwd = 2
      )
      
      # Add text labels for the fragment annotations
      text(pep_data\$mz, pep_data\$intensities,
        labels = pep_data\$annotation,
        las = 2, cex = 0.8, pos = 3
      )
      
      legend("topright", legend = c("y-ions", "b-ions/others"), col = c("red", "blue"), lwd = 2)
      
      dev.off()
    }
    
    message("Pipeline completed successfully. Outputs saved to 'prediction_results.csv' and 'predicted_spectra.pdf'.")

    writeLines(c(
        '"BIOC_KOINAR_PEPTIDE_FRAGMENT_INTENSITY_PREDICTION":',
        paste0('    koinar: ', as.character(packageVersion('koinar')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peptide_fragment_intensity_prediction.csv versions.yml
    """
}

workflow BIOC_KOINAR_PEPTIDE_FRAGMENT_INTENSITY_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peptide_data.csv ] ]

    main:
    BIOC_KOINAR_PEPTIDE_FRAGMENT_INTENSITY_PREDICTION(ch_input)

    emit:
    tables   = BIOC_KOINAR_PEPTIDE_FRAGMENT_INTENSITY_PREDICTION.out.tables
    plots    = BIOC_KOINAR_PEPTIDE_FRAGMENT_INTENSITY_PREDICTION.out.plots
    objects  = BIOC_KOINAR_PEPTIDE_FRAGMENT_INTENSITY_PREDICTION.out.objects
    versions = BIOC_KOINAR_PEPTIDE_FRAGMENT_INTENSITY_PREDICTION.out.versions
}
