#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: spkTools — spike_in_analysis
// Compare and assess microarray platform performance using spike-in data by evaluating accuracy, precision, and design imbalance.
// Input: SpikeInExpressionSet.RData
// Container: quay.io/biocontainers/bioconductor-spktools:1.66.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: spkTools
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the spike-in expression data
//  * 2. [Visualization & Output] Compute and plot signal detection slopes using spkSlope
//  * 3. [Visualization & Output] Plot empirical densities and ALE strata cut points using spkDensity
//  * 4. [Visualization & Output] Compute and plot log-ratio distributions for a given fold change using spkBox, plotSpkBox, and summarySpkBox
//  * 5. [Visualization & Output] Generate MA plots stratified by ALE groups using spkMA
//  * 6. [Core Analysis] Map nominal concentrations to ALE strata and compute standard deviations using spkVar
//  * 7. [Core Analysis] Assess accuracy, precision, signal-to-noise ratio (SNR), and probability of being at the top (POT) using spkAccSD and spkPot
//  * 8. [Core Analysis] Quantify design imbalance and probe/array effects using spkBal and spkAnova

nextflow.enable.dsl = 2

process BIOC_SPKTOOLS_SPIKE_IN_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("spkTools")
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
    
    # Check for input file
    if (!file.exists("SpikeInExpressionSet.RData")) {
      stop("Error: 'SpikeInExpressionSet.RData' not found in the working directory.")
    }
    
    # Load required library
    library(spkTools)
    
    # 1. Load the spike-in expression data
    loaded_vars <- load("SpikeInExpressionSet.RData")
    
    # Identify the SpikeInExpressionSet object from loaded variables
    object <- NULL
    for (v in loaded_vars) {
      if (inherits(get(v), "SpikeInExpressionSet")) {
        object <- get(v)
        break
      }
    }
    
    if (is.null(object)) {
      # Fallback to the first loaded object if no explicit SpikeInExpressionSet class is found
      object <- get(loaded_vars[1])
    }
    
    # Set parameters
    fc <- 2
    label <- "Affymetrix"
    
    # Open PDF device for plots
    pdf("spike_in_analysis_plots.pdf", width=10, height=8)
    par(mar=c(3,2.5,2,0.5), cex=1.8)
    
    # 2. Compute and plot signal detection slopes using spkSlope
    spkSlopeOut <- spkSlope(object, label, pch="+")
    
    # 3. Plot empirical densities and ALE strata cut points using spkDensity
    spkDensity(object, spkSlopeOut, cuts=TRUE, label)
    
    # 4. Compute and plot log-ratio distributions for a given fold change
    spkBoxOut <- spkBox(object, spkSlopeOut, fc)
    plotSpkBox(spkBoxOut, fc, ylim=c(-1.5,2.5))
    sbox <- summarySpkBox(spkBoxOut)
    
    # 5. Generate MA plots stratified by ALE groups using spkMA
    spkMA(object, spkSlopeOut, fc, label=label, ylim=c(-2.5,2.5))
    
    # Close PDF device
    dev.off()
    
    # 6. Map nominal concentrations to ALE strata and compute standard deviations
    vtmp <- spkVar(object)
    sv <- as.numeric(vtmp[,2][-nrow(vtmp)])
    bin <- c("Low", "Med", "High")
    bins <- bin[spkSlopeOut\$breaks[2,]]
    tab1 <- data.frame(NominalConc=2^spkSlopeOut\$breaks[1,],
                       AvgExp=round(spkSlopeOut\$avgExp,1),
                       PropGenesBelow=round(spkSlopeOut\$prop,2),
                       ALEStrata=bins,
                       SD=round(sv,2))
    colnames(tab1) <- c("Nominal Conc",
                        "Avg Expression",
                        "Prop of Genes Below",
                        "ALE Strata",
                        "Std Dev")
    
    # Write Table 1
    write.csv(tab1, "nominal_to_ale_mapping.csv", row.names=FALSE)
    
    # 7. Assess accuracy, precision, signal-to-noise ratio (SNR), and probability of being at the top (POT)
    AccuracySlope <- round(spkSlopeOut\$slopes[-1], digits=2)
    AccuracySD <- round(spkAccSD(object, spkSlopeOut), digits=2)
    pot <- spkPot(object, spkSlopeOut, AccuracySlope, AccuracySD, 
                  precisionQuantile=.995)
    PrecisionSD <- round(sbox\$madFC[1:3], digits=2)
    PrecisionQuantile <- round(pot\$quantiles, digits=2)
    SNR <- round(AccuracySlope/PrecisionSD, digits=2)
    POT <- round(pot\$POTs, digits=2)
    tab2 <- data.frame(AccuracySlope=AccuracySlope,
                       AccuracySD=AccuracySD,
                       PrecisionSD=PrecisionSD,
                       PrecisionQuantile=PrecisionQuantile,
                       SNR=SNR,
                       POT=POT)
    
    # Write Table 2
    write.csv(tab2, "assessment_results.csv", row.names=TRUE)
    
    # 8. Quantify design imbalance and probe/array effects using spkBal and spkAnova
    bals <- round(spkBal(object))
    anv <- round(spkAnova(object), digits=2)
    tab3 <- t(c(anv,bals))
    tab3_df <- as.data.frame(tab3)
    
    # Write Table 3
    write.csv(tab3_df, "anova_and_imbalance_results.csv", row.names=FALSE)
    
    # Save intermediate R objects for downstream analysis
    saveRDS(spkSlopeOut, "spkSlopeOut.rds")
    saveRDS(spkBoxOut, "spkBoxOut.rds")
    saveRDS(pot, "spkPotOut.rds")

    writeLines(c(
        '"BIOC_SPKTOOLS_SPIKE_IN_ANALYSIS":',
        paste0('    spkTools: ', as.character(packageVersion('spkTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spike_in_analysis.csv versions.yml
    """
}

workflow BIOC_SPKTOOLS_SPIKE_IN_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SpikeInExpressionSet.RData ] ]

    main:
    BIOC_SPKTOOLS_SPIKE_IN_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SPKTOOLS_SPIKE_IN_ANALYSIS.out.tables
    plots    = BIOC_SPKTOOLS_SPIKE_IN_ANALYSIS.out.plots
    objects  = BIOC_SPKTOOLS_SPIKE_IN_ANALYSIS.out.objects
    versions = BIOC_SPKTOOLS_SPIKE_IN_ANALYSIS.out.versions
}
