#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: koinar — spectral_similarity_comparison
// Compare peptide fragment ion intensity predictions between two different models (e.g., Prosit and MS2PIP).
// Input: peptide_data.csv
// Container: quay.io/biocontainers/bioconductor-koinar:1.4.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: OrgMassSpecR, koinar
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize Koina clients for both models using koinar::Koina()
//  * 2. [Core Analysis] Predict fragment intensities for both models using $predict()
//  * 3. [Core Analysis] Compare the predicted spectra using OrgMassSpecR::SpectrumSimilarity()

nextflow.enable.dsl = 2

process BIOC_KOINAR_SPECTRAL_SIMILARITY_COMPARISON {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("koinar", "OrgMassSpecR")
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
    library(koinar)
    library(OrgMassSpecR)
    
    # 1. Read the user input file
    input_file <- "peptide_data.csv"
    if (!file.exists(input_file)) {
      stop(paste("Error: Required input file", input_file, "not found in the working directory."))
    }
    
    input <- read.csv(input_file, stringsAsFactors = FALSE)
    
    # Ensure required columns exist and are of correct types
    input\$peptide_sequences <- as.character(input\$peptide_sequences)
    input\$collision_energies <- as.numeric(input\$collision_energies)
    input\$precursor_charges <- as.integer(input\$precursor_charges)
    
    # 2. Initialize Koina clients for both models
    prosit2019 <- koinar::Koina(
      model_name = "Prosit_2019_intensity",
      server_url = "koina.wilhelmlab.org"
    )
    
    ms2pip <- koinar::Koina(
      model_name = "ms2pip_HCD2021",
      server_url = "koina.wilhelmlab.org"
    )
    
    # 3. Predict fragment intensities for both models
    pred_prosit <- prosit2019\$predict((input))
    pred_prosit\$model <- "Prosit_2019_intensity"
    
    pred_ms2pip <- ms2pip\$predict(input)
    pred_ms2pip\$model <- "ms2pip_HCD2021"
    
    # Save prediction results to CSV files
    write.csv(pred_prosit, "predictions_prosit.csv", row.names = FALSE)
    write.csv(pred_ms2pip, "predictions_ms2pip.csv", row.names = FALSE)
    
    # 4. Compare the predicted spectra using OrgMassSpecR::SpectrumSimilarity
    # Determine which peptide sequence to use for comparison
    # Default to "ADVTPADFSEWSK" if present, otherwise use the first sequence in the input
    peptide_sequence <- "ADVTPADFSEWSK"
    if (!(peptide_sequence %in% input\$peptide_sequences)) {
      peptide_sequence <- input\$peptide_sequences[1]
    }
    
    # Extract spectra for the selected peptide
    spec_prosit <- pred_prosit[pred_prosit\$peptide_sequences == peptide_sequence, c("mz", "intensities")]
    spec_ms2pip <- pred_ms2pip[pred_ms2pip\$peptide_sequences == peptide_sequence, c("mz", "intensities")]
    
    # Generate and save the similarity plot
    pdf("spectral_similarity_plot.pdf", width = 8, height = 6)
    
    sim <- OrgMassSpecR::SpectrumSimilarity(
      spec_prosit,
      spec_ms2pip,
      top.lab = "Prosit",
      bottom.lab = "MS2PIP",
      b = 25
    )
    title(main = paste(peptide_sequence, "| Spectrum similarity", round(sim, 3)))
    
    dev.off()
    
    # Save the similarity score to a CSV file
    similarity_results <- data.frame(
      peptide_sequence = peptide_sequence,
      similarity_score = sim,
      stringsAsFactors = FALSE
    )
    write.csv(similarity_results, "similarity_score.csv", row.names = FALSE)
    
    # Save the R objects for downstream analysis
    saveRDS(pred_prosit, "pred_prosit.rds")
    saveRDS(pred_ms2pip, "pred_ms2pip.rds")

    writeLines(c(
        '"BIOC_KOINAR_SPECTRAL_SIMILARITY_COMPARISON":',
        paste0('    koinar: ', as.character(packageVersion('koinar')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spectral_similarity_comparison.csv versions.yml
    """
}

workflow BIOC_KOINAR_SPECTRAL_SIMILARITY_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peptide_data.csv ] ]

    main:
    BIOC_KOINAR_SPECTRAL_SIMILARITY_COMPARISON(ch_input)

    emit:
    tables   = BIOC_KOINAR_SPECTRAL_SIMILARITY_COMPARISON.out.tables
    plots    = BIOC_KOINAR_SPECTRAL_SIMILARITY_COMPARISON.out.plots
    objects  = BIOC_KOINAR_SPECTRAL_SIMILARITY_COMPARISON.out.objects
    versions = BIOC_KOINAR_SPECTRAL_SIMILARITY_COMPARISON.out.versions
}
