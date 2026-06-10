#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: msnbase — isobaric_tagging_quantitation
// Import raw MS data, integrate peptide identifications, clean spectra, quantify reporter ions, correct for isotopic impurities, normalize, and aggregate spectrum
// Input: quantFile.mzXML, identFile.mzid
// Container: quay.io/biocontainers/bioconductor-msnbase:2.36.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSNBASE_ISOBARIC_TAGGING_QUANTITATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-msnbase:2.36.0--r45ha27e39d_0"

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
    .bm_deps <- c("biocparallel", "biocstyle", "doparallel", "ggplot2", "msnbase", "rdisop")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(MSnbase)
    
    # Define input file paths in the working directory
    quantFile <- "quantFile.mzXML"
    identFile <- "identFile.mzid"
    
    # Verify that input files exist before proceeding
    if (!file.exists(quantFile)) {
      stop(paste("Required raw MS data file missing:", quantFile))
    }
    if (!file.exists(identFile)) {
      stop(paste("Required identification file missing:", identFile))
    }
    
    # Define standard iTRAQ 4-plex impurity matrix for purity correction
    # Rows correspond to reporters 114, 115, 116, 117
    impurities <- matrix(c(
      0.929, 0.059, 0.002, 0.000,
      0.020, 0.923, 0.056, 0.001,
      0.000, 0.030, 0.924, 0.045,
      0.000, 0.001, 0.040, 0.929
    ), nrow = 4, byrow = TRUE)
    rownames(impurities) <- colnames(impurities) <- c("114", "115", "116", "117")
    
    # 1. Import raw MS data
    msexp <- readMSData(quantFile, verbose = FALSE)
    
    # 2. Integrate peptide identification data
    msexp <- addIdentificationData(msexp, id = identFile)
    
    # 3. Filter out unidentified spectra
    msexp <- removeNoId(msexp)
    
    # 4. Clean low-intensity peaks and remove empty data points
    experiment <- removePeaks(msexp, t = 400, verbose = FALSE)
    experiment <- clean(experiment, verbose = FALSE)
    
    # 5. Focus on the reporter ion m/z range
    experiment <- filterMz(experiment, mzlim = c(112,120))
    
    # 6. Quantify reporter ions
    qnt <- quantify(experiment, method = "trap", reporters = iTRAQ4, strict = FALSE, verbose = FALSE)
    
    # 7. Filter out features with missing values
    qnt <- filterNA(qnt, pNA = 0)
    
    # 8. Correct for isotopic impurities
    qnt.crct <- purityCorrect(qnt, impurities)
    
    # 9. Normalize reporter intensities
    qnt.max <- normalise(qnt, "max")
    
    # 10. Aggregate spectrum-level quantitation to protein-level abundances
    gb <- fData(qnt)\$ProteinAccession
    qnt2 <- combineFeatures(qnt, groupBy = gb, method = "median")
    
    # --- Export Results ---
    
    # Save quantitative data as CSV tables
    write.csv(exprs(qnt2), file = "protein_abundances.csv", row.names = TRUE)
    write.csv(exprs(qnt.crct), file = "spectrum_purity_corrected.csv", row.names = TRUE)
    write.csv(exprs(qnt.max), file = "spectrum_normalized_max.csv", row.names = TRUE)
    
    # Save R objects for downstream analysis
    saveRDS(qnt2, file = "protein_abundances.rds")
    saveRDS(qnt.crct, file = "spectrum_purity_corrected.rds")
    saveRDS(qnt.max, file = "spectrum_normalized_max.rds")
    
    # Generate a PDF plot of the final protein-level abundances
    pdf("protein_abundance_heatmap.pdf", width = 7, height = 7)
    if (nrow(qnt2) > 1) {
      heatmap(exprs(qnt2), main = "Protein Abundances (iTRAQ4)", Colv = NA)
    } else {
      barplot(exprs(qnt2), main = "Protein Abundances (iTRAQ4)", beside = TRUE, legend.text = TRUE)
    }
    dev.off()
    
    cat("Pipeline completed successfully. Outputs written to working directory.\n")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MSNBASE_ISOBARIC_TAGGING_QUANTITATION":
        msnbase: \$(Rscript -e 'cat(as.character(packageVersion("msnbase")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_isobaric_tagging_quantitation.csv versions.yml
    """
}

workflow BIOC_MSNBASE_ISOBARIC_TAGGING_QUANTITATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ quantFile.mzXML, identFile.mzid ] ]

    main:
    BIOC_MSNBASE_ISOBARIC_TAGGING_QUANTITATION(ch_input)

    emit:
    tables   = BIOC_MSNBASE_ISOBARIC_TAGGING_QUANTITATION.out.tables
    plots    = BIOC_MSNBASE_ISOBARIC_TAGGING_QUANTITATION.out.plots
    objects  = BIOC_MSNBASE_ISOBARIC_TAGGING_QUANTITATION.out.objects
    versions = BIOC_MSNBASE_ISOBARIC_TAGGING_QUANTITATION.out.versions
}
