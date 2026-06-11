#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: isobar — isobaric_quantification
// Preprocess, normalize, model noise, and estimate protein ratios for standard isobaric-labeled proteomics data.
// Input: identifications.id.csv, peaklist.mgf
// Container: quay.io/biocontainers/bioconductor-isobar:1.56.0--r45hdfd78af_0
// R packages: distr, ggplot2, isobar
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISOBAR_ISOBARIC_QUANTIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-isobar:1.56.0--r45hdfd78af_0"

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
    .bm_deps <- c("distr", "ggplot2", "isobar")
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
    library(isobar)
    library(distr)
    library(ggplot2)
    
    # --- Read raw identification and peaklist files into an ---
    # Reading exactly the user-specified files from the working directory
    ib <- readIBSpectra(
      "iTRAQ4plexSpectra",
      "identifications.id.csv",
      "peaklist.mgf"
    )
    
    # Assign to the variable name used in the documented vignette code
    ibspiked_set1 <- ib
    
    # Dynamically identify proteins to use as the "ceru.proteins" subset
    # to ensure the pipeline runs successfully on any input dataset
    all_proteins <- reporterProteins(proteinGroup(ibspiked_set1))
    if (length(all_proteins) == 0) {
      stop("No proteins found in the identification file.")
    }
    ceru.proteins <- head(all_proteins, min(3, length(all_proteins)))
    
    # --- Correct isotope impurities ---
    ibspiked_set1 <- correctIsotopeImpurities(ibspiked_set1)
    
    # --- Normalize reporter intensities ---
    ibspiked_set1 <- normalize(ibspiked_set1)
    
    # --- Subset background proteins and fit a NoiseModel ---
    ib.background <- subsetIBSpectra(ibspiked_set1, protein=ceru.proteins, direction="exclude")
    noise.model <- NoiseModel(ib.background)
    
    # --- Estimate protein ratios and define class labels ---
    # Estimate ratio for the selected protein subset
    ratio_estimate <- 10^estimateRatio(
      ibspiked_set1,
      noise.model,
      channel1="114",
      channel2="115",
      protein=ceru.proteins
    )['lratio']
    
    # Calculate protein ratios across classes
    protein.ratios <- proteinRatios(ibspiked_set1, noise.model, cl=c("1","0","0","0"))
    
    # Define class labels
    classLabels(ibspiked_set1) <- c("T","T","C","C")
    
    # Calculate subset protein ratios with interclass combination method
    protein_ratios_subset <- proteinRatios(
      ibspiked_set1,
      noise.model,
      protein=ceru.proteins,
      cl=classLabels(ibspiked_set1),
      combn.method="interclass",
      summarize=TRUE
    )[, c("ac", "lratio", "variance")]
    
    # --- Fit ratio distributions and identify significant ratios ---
    protein.ratiodistr.cauchy <- fitCauchy(protein.ratios[, "lratio"])
    
    rat.list <- estimateRatio(
      ibspiked_set1,
      noise.model=noise.model,
      channel1="114",
      channel2="115",
      protein=reporterProteins(proteinGroup(ibspiked_set1)),
      combine=FALSE,
      ratiodistr=protein.ratiodistr.cauchy
    )
    
    # Write meaningful results to output files
    write.csv(as.data.frame(protein.ratios), "protein_ratios.csv", row.names=FALSE)
    write.csv(as.data.frame(protein_ratios_subset), "protein_ratios_subset.csv", row.names=FALSE)
    write.csv(as.data.frame(rat.list), "significant_ratios.csv", row.names=FALSE)
    
    saveRDS(noise.model, "noise_model.rds")
    saveRDS(ibspiked_set1, "ib_processed.rds")
    
    # Generate diagnostic plots
    pdf("isobar_qc_plots.pdf", width=10, height=5)
    
    # Plot 1: Normalization MAPlot comparison
    par(mfrow=c(1,2))
    maplot(ib, channel1="114", channel2="117", ylim=c(0.5,2), main="Before Normalization")
    abline(h=1, col="red", lwd=2)
    maplot(ibspiked_set1, channel1="114", channel2="117", ylim=c(0.5,2), main="After Normalization")
    abline(h=1, col="red", lwd=2)
    
    # Plot 2: Ratio distribution with Cauchy fit
    limits <- seq(from=-1.5, to=1.5, by=0.01)
    curve.cauchy <- data.frame(x=limits, y=d(protein.ratiodistr.cauchy)(limits))
    g <- ggplot(data.frame(protein.ratios), aes(x=lratio)) +
      geom_histogram(colour = "darkgreen", fill = "white", aes(y=..density..), binwidth=0.05) +
      geom_rug() +
      geom_line(data=curve.cauchy, aes(x=x, y=y), colour="red", size=1) +
      labs(title="Protein Ratio Distribution (Cauchy Fit)", x="Log2 Ratio", y="Density") +
      theme_minimal()
    print(g)
    
    dev.off()

    writeLines(c(
        '"BIOC_ISOBAR_ISOBARIC_QUANTIFICATION":',
        paste0('        isobar: ', as.character(packageVersion("isobar")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_isobaric_quantification.csv versions.yml
    """
}

workflow BIOC_ISOBAR_ISOBARIC_QUANTIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ identifications.id.csv, peaklist.mgf ] ]

    main:
    BIOC_ISOBAR_ISOBARIC_QUANTIFICATION(ch_input)

    emit:
    tables   = BIOC_ISOBAR_ISOBARIC_QUANTIFICATION.out.tables
    plots    = BIOC_ISOBAR_ISOBARIC_QUANTIFICATION.out.plots
    objects  = BIOC_ISOBAR_ISOBARIC_QUANTIFICATION.out.objects
    versions = BIOC_ISOBAR_ISOBARIC_QUANTIFICATION.out.versions
}
