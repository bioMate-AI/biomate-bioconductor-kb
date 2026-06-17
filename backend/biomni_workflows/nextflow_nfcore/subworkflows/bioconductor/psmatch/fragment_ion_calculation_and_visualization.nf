#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PSMatch — fragment_ion_calculation_and_visualization
// Calculate theoretical fragment ions for a peptide sequence and visualize matched b- and y-ion fragments on an experimental MS2 spectrum.
// Input: file.mzML.gz, file.mzid
// Container: quay.io/biocontainers/bioconductor-psmatch:1.14.0--r45hdfd78af_0
// R packages: PSMatch, Spectra
// Bioconductor: 3.20 | R: 4.4
// Requires: PSMatch, PTMods, Spectra
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load raw MS data and identification data
//  * 2. [Visualization & Output] Filter identification data and merge with raw spectra
//  * 3. [Visualization & Output] Extract a specific precursor scan and its MS2 scan
//  * 4. [Visualization & Output] Calculate theoretical fragment ions for the matched
//  * 5. [Visualization & Output] Plot the annotated MS2 spectrum with PTM modifications

nextflow.enable.dsl = 2

process BIOC_PSMATCH_FRAGMENT_ION_CALCULATION_AND_VISUALIZATION {
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
    .bm_deps <- c("PSMatch", "Spectra")
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
    library(Spectra)
    library(PSMatch)
    
    # Define input files as specified by the user
    spf <- "file.mzML.gz"
    idf <- "file.mzid"
    
    # --- Load raw MS data and identification data ---
    sp <- Spectra(spf)
    id <- PSM(idf) |> filterPSMs()
    
    # --- Filter identification data and merge with raw spectra ---
    sp <- joinSpectraData(sp, id, by.x = "spectrumId", by.y = "spectrumID")
    
    # --- Extract a specific precursor scan and its MS2 scan ---
    # Dynamically find the first scan with a matched peptide sequence
    target_scan <- sp\$scanIndex[!is.na(sp\$sequence)][1]
    sp_target <- filterPrecursorScan(sp, target_scan)
    
    # Identify indices for MS1 and MS2 scans
    ms2_idx <- which(!is.na(sp_target\$sequence))[1]
    if (is.na(ms2_idx)) ms2_idx <- length(sp_target)
    
    ms1_idx <- which(msLevel(sp_target) == 1)[1]
    if (is.na(ms1_idx)) ms1_idx <- 1
    
    target_seq <- sp_target\$sequence[ms2_idx]
    
    # --- Calculate theoretical fragment ions for the matched ---
    frags <- calculateFragments(target_seq, addCarbamidomethyl = FALSE)
    
    # Save calculated fragments to CSV
    write.csv(as.data.frame(frags), "calculated_fragments.csv", row.names = FALSE)
    
    # Calculate fragments with variable modifications if PTMods is available
    if (requireNamespace("PTMods", quietly = TRUE)) {
        var_seq <- PTMods::addVariableModifications(target_seq,
            variableModifications = c(C = 57.02146, T = 79.966)
        )
        var_frags <- calculateFragments(var_seq)
        write.csv(as.data.frame(var_frags), "calculated_fragments_variable_mods.csv", row.names = FALSE)
    }
    
    # --- Plot the annotated MS2 spectrum with PTM modifications ---
    dataOrigin(sp_target)[ms2_idx] <- basename(spf)
    
    # Open PDF device to save the visualizations
    pdf("fragment_ion_plots.pdf", width = 10, height = 8)
    
    # Plot precursor scan
    plotSpectra(sp_target[ms1_idx], xlim = c(400, 600))
    abline(v = precursorMz(sp_target)[ms2_idx], col = "red", lty = "dotted")
    
    # Plot MS2 scan as is
    plotSpectra(sp_target[ms2_idx])
    
    # Plot annotated MS2 spectrum with fixed modifications
    plotSpectraPTM(sp_target[ms2_idx],
        fixedModifications = c(C = "Carbamidomethyl")
    )
    
    # Plot annotated MS2 spectrum comparing with and without carbamidomethylation
    plotSpectraPTM(sp_target[ms2_idx],
        variableModifications = c(C = "Carbamidomethyl"),
        addCarbamidomethyl = FALSE,
        asp = 1/2,
        deltaMz = FALSE,
        main = c(paste("Scan", target_scan, "without carbamidomethyl"), 
                 paste("Scan", target_scan, "with carbamidomethyl"))
    )
    
    dev.off()
    
    # Save processed R objects for downstream analysis
    saveRDS(sp_target, "sp_target.rds")
    saveRDS(id, "filtered_id.rds")

    writeLines(c(
        '"BIOC_PSMATCH_FRAGMENT_ION_CALCULATION_AND_VISUALIZATION":',
        paste0('    PSMatch: ', as.character(packageVersion('PSMatch')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fragment_ion_calculation_and_visualization.csv versions.yml
    """
}

workflow BIOC_PSMATCH_FRAGMENT_ION_CALCULATION_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file.mzML.gz, file.mzid ] ]

    main:
    BIOC_PSMATCH_FRAGMENT_ION_CALCULATION_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_PSMATCH_FRAGMENT_ION_CALCULATION_AND_VISUALIZATION.out.tables
    plots    = BIOC_PSMATCH_FRAGMENT_ION_CALCULATION_AND_VISUALIZATION.out.plots
    objects  = BIOC_PSMATCH_FRAGMENT_ION_CALCULATION_AND_VISUALIZATION.out.objects
    versions = BIOC_PSMATCH_FRAGMENT_ION_CALCULATION_AND_VISUALIZATION.out.versions
}
