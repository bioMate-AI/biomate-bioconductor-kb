#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MBCB — illumina_beadarray_background_correction
// Parse, background-correct, and normalize Illumina BeadArray expression data using model-based techniques.
// Input: signal.txt, negative.control.txt
// Container: quay.io/biocontainers/bioconductor-mbcb:1.64.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MBCB
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Parse the input signal and negative control files
//  * 2. [Input & Preparation] Define background correction method logical flags
//  * 3. [Core Analysis] Perform background correction using mbcb.correct or mbcb.main
//  * 4. [Visualization & Output] Apply normalization (quantile or median) and read the corrected output files

nextflow.enable.dsl = 2

process BIOC_MBCB_ILLUMINA_BEADARRAY_BACKGROUND_CORRECTION {
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
    .bm_deps <- c("MBCB")
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
    library(MBCB)
    
    # Verify input files exist
    if (!file.exists("signal.txt") || !file.exists("negative.control.txt")) {
      stop("Required input files 'signal.txt' and/or 'negative.control.txt' are missing in the working directory.")
    }
    
    # 1. Parse the input signal and negative control files
    data <- mbcb.parseFile('signal.txt', 'negative.control.txt');
    signal <- data\$sig;
    negCon <- data\$con;
    
    # Map parsed data to the variables used in the documented code
    expressionSignal <- signal;
    negativeControl <- negCon;
    
    # 2. Define background correction method logical flags
    nonparametric <- TRUE;
    RMA<- TRUE;
    MLE <- TRUE;
    GMLE <- FALSE;
    MCMC <- FALSE;
    
    # 3. Perform background correction using mbcb.correct or mbcb.main
    cor <- mbcb.correct(expressionSignal, negativeControl, nonparametric, RMA, MLE, MCMC, GMLE);
    
    # Save the correction object
    saveRDS(cor, "mbcb_corrected_object.rds")
    
    # Run mbcb.main with values set
    mbcb.main(expressionSignal, negativeControl, nonparametric, RMA, MLE, MCMC, GMLE, "param-est", "bgCorrected");
    
    # Run default mbcb.main
    mbcb.main(expressionSignal, negativeControl, paramEstFile="param-est", bgCorrectedFile="bgCorrected");
    
    # 4. Apply normalization (quantile or median) and read the corrected output files
    # Quantile normalization
    mbcb.main(expressionSignal, negativeControl, normMethod="quant");
    quant_np <- read.csv("bgCorrected-NP.csv", row.names=1)
    write.csv(quant_np, "quant_np_normalized.csv")
    
    # Median normalization
    mbcb.main(expressionSignal, negativeControl, normMethod="median");
    median_np <- read.csv("bgCorrected-NP.csv", row.names=1)
    write.csv(median_np, "median_np_normalized.csv")
    
    # Generate diagnostic plots
    pdf("mbcb_diagnostic_plots.pdf", width=10, height=10)
    
    # Plot 1: Background corrections
    ylimits <- c(10, 60000);
    par(mfrow=c(2,2), mar=c(4,4,3,1))
    boxplot(expressionSignal, log="y", ylim=ylimits, main="Raw Expression")
    boxplot(cor\$NP, log="y", ylim=ylimits, main="NP-corrected")
    boxplot(cor\$RMA, log="y", ylim=ylimits, main="RMA-corrected")
    boxplot(cor\$MLE, log="y", ylim=ylimits, main="MLE-corrected")
    
    # Plot 2: Normalization comparison
    par(mfrow=c(2,2), mar=c(4,4,3,1))
    boxplot(expressionSignal, log="y", main="Raw Expression")
    boxplot(cor\$NP, log="y", main="Non-normalized NP")
    boxplot(median_np, log="y", main="Quantile Norm, NP-corrected")
    boxplot(quant_np, log="y", main="Median Norm, NP-corrected")
    
    dev.off()

    writeLines(c(
        '"BIOC_MBCB_ILLUMINA_BEADARRAY_BACKGROUND_CORRECTION":',
        paste0('    MBCB: ', as.character(packageVersion('MBCB')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_illumina_beadarray_background_correction.csv versions.yml
    """
}

workflow BIOC_MBCB_ILLUMINA_BEADARRAY_BACKGROUND_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ signal.txt, negative.control.txt ] ]

    main:
    BIOC_MBCB_ILLUMINA_BEADARRAY_BACKGROUND_CORRECTION(ch_input)

    emit:
    tables   = BIOC_MBCB_ILLUMINA_BEADARRAY_BACKGROUND_CORRECTION.out.tables
    plots    = BIOC_MBCB_ILLUMINA_BEADARRAY_BACKGROUND_CORRECTION.out.plots
    objects  = BIOC_MBCB_ILLUMINA_BEADARRAY_BACKGROUND_CORRECTION.out.objects
    versions = BIOC_MBCB_ILLUMINA_BEADARRAY_BACKGROUND_CORRECTION.out.versions
}
