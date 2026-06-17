#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BRAIN — single_molecule_isotopic_distribution
// Calculate and plot the aggregated isotopic distribution, monoisotopic mass, and average mass for a single chemical substance or peptide sequence.
// Input: chemical_composition.txt
// Container: quay.io/biocontainers/bioconductor-brain:1.56.0--r45hdfd78af_0
// R packages: BRAIN, lattice
// Bioconductor: 3.20 | R: 4.4
// Requires: BRAIN
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the atomic composition list
//  * 2. [Core Analysis] Calculate the theoretical monoisotopic mass
//  * 3. [Core Analysis] Calculate the theoretical average mass
//  * 4. [Core Analysis] Estimate the required number of peaks
//  * 5. [Core Analysis] Compute isotopic probabilities with various stopping criteria
//  * 6. [Visualization & Output] Run the global useBRAIN function to obtain masses and abundances for plotting

nextflow.enable.dsl = 2

process BIOC_BRAIN_SINGLE_MOLECULE_ISOTOPIC_DISTRIBUTION {
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
    .bm_deps <- c("BRAIN", "lattice")
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
    
    # Load required library
    library(BRAIN)
    
    # ----------------------------------------------------------------------
    # 1. Read and Parse User Input File: chemical_composition.txt
    # ----------------------------------------------------------------------
    if (!file.exists("chemical_composition.txt")) {
      stop("Error: 'chemical_composition.txt' not found in the working directory.")
    }
    
    # Attempt to read the file robustly (handles space, tab, or comma separation)
    raw_data <- tryCatch({
      read.table("chemical_composition.txt", header = TRUE, stringsAsFactors = FALSE)
    }, error = function(e) {
      read.csv("chemical_composition.txt", header = TRUE, stringsAsFactors = FALSE)
    })
    
    # Parse the composition into a named list
    angiotensineII <- list()
    target_elements <- c("C", "H", "N", "O", "S")
    
    # Check if the input is in key-value format (e.g., columns: Element, Count)
    if (ncol(raw_data) >= 2 && any(c("ELEMENT", "COUNT") %in% toupper(colnames(raw_data)))) {
      colnames(raw_data) <- toupper(colnames(raw_data))
      element_col <- grep("ELEMENT", colnames(raw_data), value = TRUE)[1]
      count_col <- grep("COUNT", colnames(raw_data), value = TRUE)[1]
      
      raw_data[[element_col]] <- toupper(trimws(raw_data[[element_col]]))
      for (el in target_elements) {
        val <- raw_data[[count_col]][raw_data[[element_col]] == el]
        if (length(val) > 0) {
          angiotensineII[[el]] <- as.numeric(val[1])
        }
      }
    } else {
      # Wide format (e.g., columns: C, H, N, O, S)
      colnames(raw_data) <- toupper(colnames(raw_data))
      for (el in target_elements) {
        if (el %in% colnames(raw_data)) {
          angiotensineII[[el]] <- as.numeric(raw_data[1, el])
        }
      }
    }
    
    # Clean up list (remove NA values and keep only defined elements)
    angiotensineII <- angiotensineII[!is.na(angiotensineII)]
    
    # Validate that we have at least some elements to calculate
    if (length(angiotensineII) == 0) {
      stop("Error: No valid chemical elements (C, H, N, O, S) parsed from chemical_composition.txt.")
    }
    
    # ----------------------------------------------------------------------
    # 2. Calculate Theoretical Monoisotopic Mass
    # ----------------------------------------------------------------------
    monoisotopicMassAngiotensineII <- calculateMonoisotopicMass(aC = angiotensineII)
    print("Monoisotopic Mass:")
    print(monoisotopicMassAngiotensineII)
    
    # ----------------------------------------------------------------------
    # 3. Calculate Theoretical Average Mass
    # ----------------------------------------------------------------------
    averageMassAngiotensineII <- calculateAverageMass(aC = angiotensineII)
    print("Average Mass:")
    print(averageMassAngiotensineII)
    
    # ----------------------------------------------------------------------
    # 4. Estimate Required Number of Peaks
    # ----------------------------------------------------------------------
    nrPeaksAngiotensineII <- calculateNrPeaks(aC = angiotensineII)
    print("Estimated Number of Peaks:")
    print(nrPeaksAngiotensineII)
    
    # ----------------------------------------------------------------------
    # 5. Compute Isotopic Probabilities with Various Stopping Criteria
    # ----------------------------------------------------------------------
    # With default options
    prob1 <- calculateIsotopicProbabilities(aC = angiotensineII)
    
    # With user defined number of requested aggregated isotopic variants
    prob2 <- calculateIsotopicProbabilities(aC = angiotensineII, nrPeaks=20)
    
    # With user-defined coverage as stopping criterion
    prob3 <- calculateIsotopicProbabilities(aC = angiotensineII, stopOption = "coverage", coverage = 0.99)
    
    # With user-defined abundantEstim as stopping criterion
    prob4 <- calculateIsotopicProbabilities(aC = angiotensineII, stopOption = "abundantEstim", abundantEstim = 10)
    
    # ----------------------------------------------------------------------
    # 6. Run Global useBRAIN Function and Plot Results
    # ----------------------------------------------------------------------
    res <- useBRAIN(aC= angiotensineII)
    
    # Write meaningful tabular outputs to CSV files
    mass_results <- data.frame(
      Metric = c("Monoisotopic Mass", "Average Mass", "Estimated Number of Peaks"),
      Value = c(monoisotopicMassAngiotensineII, averageMassAngiotensineII, nrPeaksAngiotensineII)
    )
    write.csv(mass_results, "mass_results.csv", row.names = FALSE)
    
    write.csv(data.frame(Probability = prob1), "prob_default.csv", row.names = FALSE)
    write.csv(data.frame(Probability = prob2), "prob_20peaks.csv", row.names = FALSE)
    write.csv(data.frame(Probability = prob3), "prob_coverage_99.csv", row.names = FALSE)
    write.csv(data.frame(Probability = prob4), "prob_abundant_10.csv", row.names = FALSE)
    
    brain_df <- data.frame(
      Mass = res\$masses,
      Abundance = res\$isoDistr
    )
    write.csv(brain_df, "brain_results.csv", row.names = FALSE)
    
    # Generate the isotopic distribution plot
    pdf("isotopic_distribution_plot.pdf", width = 8, height = 6)
    
    # Dynamically construct plot title expression based on parsed composition
    title_parts <- sapply(names(angiotensineII), function(name) {
      paste0(name, "[", angiotensineII[[name]], "]")
    })
    headr <- parse(text = paste("paste(", paste(title_parts, collapse = ", "), ")"))
    
    # Plot isotopic distribution
    plot(res\$masses, res\$isoDistr, xlab="mass", ylab="abundances", type="h", 
         xlim=c(min(res\$masses)-1, max(res\$masses)+1.5))
    title(headr)
    
    labelMono <- paste("mono-isotopic mass:", round(res\$monoisotopicMass, 4), "Da", sep=" ")
    labelAvg <- paste("average mass:", round(res\$avgMass, 4), "Da", sep=" ")
    
    # Dynamically position text labels to avoid hardcoding coordinates
    x_text_pos <- min(res\$masses) + (max(res\$masses) - min(res\$masses)) * 0.4
    y_text_pos1 <- max(res\$isoDistr) * 0.9
    y_text_pos2 <- max(res\$isoDistr) * 0.8
    
    text(x=x_text_pos, y=y_text_pos1, labelMono, col="purple", pos = 4)
    text(x=x_text_pos, y=y_text_pos2, labelAvg, col="blue", pos = 4)
    
    # Draw indicator lines
    lines(x=rep(res\$monoisotopicMass[1],2), y=c(0, res\$isoDistr[1]), col = "purple")
    lines(x=rep(res\$avgMass,2), y=c(0, max(res\$isoDistr)), col = "blue", lty=2)
    
    dev.off()
    
    print("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_BRAIN_SINGLE_MOLECULE_ISOTOPIC_DISTRIBUTION":',
        paste0('    BRAIN: ', as.character(packageVersion('BRAIN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_molecule_isotopic_distribution.csv versions.yml
    """
}

workflow BIOC_BRAIN_SINGLE_MOLECULE_ISOTOPIC_DISTRIBUTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chemical_composition.txt ] ]

    main:
    BIOC_BRAIN_SINGLE_MOLECULE_ISOTOPIC_DISTRIBUTION(ch_input)

    emit:
    tables   = BIOC_BRAIN_SINGLE_MOLECULE_ISOTOPIC_DISTRIBUTION.out.tables
    plots    = BIOC_BRAIN_SINGLE_MOLECULE_ISOTOPIC_DISTRIBUTION.out.plots
    objects  = BIOC_BRAIN_SINGLE_MOLECULE_ISOTOPIC_DISTRIBUTION.out.objects
    versions = BIOC_BRAIN_SINGLE_MOLECULE_ISOTOPIC_DISTRIBUTION.out.versions
}
