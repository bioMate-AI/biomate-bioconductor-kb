#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DiscoRhythm — step_by_step_rhythm_analysis
// Perform a complete step-by-step rhythmicity analysis including data import, outlier removal, replicate merging, period profiling, and feature-wise oscillation d
// Input: temporal_data.csv
// Container: quay.io/biocontainers/bioconductor-discorhythm:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DiscoRhythm, SummarizedExperiment
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Import tabular data and convert to SummarizedExperiment using discoDFtoSE
//  * 2. [Core Analysis] Clean data and check for missing/constant values using discoCheckInput
//  * 3. [Core Analysis] Detect outliers using inter-sample correlation (discoInterCorOutliers) and PCA (discoPCAoutliers)
//  * 4. [Visualization & Output] Filter outliers from the SummarizedExperiment
//  * 5. [Core Analysis] Analyze and combine technical replicates using discoRepAnalysis
//  * 6. [Core Analysis] Detect dominant dataset-wide periodicities using discoPeriodDetection
//  * 7. [Core Analysis] Perform feature-wise oscillation detection using discoODAs

nextflow.enable.dsl = 2

process BIOC_DISCORHYTHM_STEP_BY_STEP_RHYTHM_ANALYSIS {
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
    .bm_deps <- c("DiscoRhythm")
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
    library(DiscoRhythm)
    
    # 1. Import tabular data and convert to SummarizedExperiment
    # Expects "temporal_data.csv" in the working directory with unique feature IDs in the first column
    # and sample data in subsequent columns (column names: Prefix_Time_UniqueID_ReplicateID)
    indata <- read.csv("temporal_data.csv", check.names = FALSE)
    
    se <- discoDFtoSE(indata)
    
    # 2. Clean data and check for missing/constant values
    selectDataSE <- discoCheckInput(se)
    
    # 3. Detect outliers using inter-sample correlation and PCA
    CorRes <- discoInterCorOutliers(selectDataSE,
                                    cor_method="pearson",
                                    threshold=3,
                                    thresh_type="sd")
    
    PCAres <- discoPCAoutliers(selectDataSE,
                               threshold=3,
                               scale=TRUE,
                               pcToCut = c("PC1","PC2","PC3","PC4"))
    
    # 4. Filter outliers from the SummarizedExperiment
    FilteredSE <- selectDataSE[,!PCAres\$outliers & !CorRes\$outliers]
    
    # 5. Analyze and combine technical replicates
    ANOVAres <- discoRepAnalysis(FilteredSE,
                                 aov_method="Equal Variance",
                                 aov_pcut=0.05,
                                 aov_Fcut=1,
                                 avg_method="Median")
    FinalSE <- ANOVAres\$se
    
    # 6. Detect dominant dataset-wide periodicities
    PeriodRes <- discoPeriodDetection(FinalSE,
                                      timeType="linear",
                                      main_per=24)
    
    # 7. Perform feature-wise oscillation detection
    discoODAres <- discoODAs(FinalSE,
                             period=24,
                             method="CS",
                             ncores=1,
                             circular_t=FALSE)
    
    # Write meaningful output files
    # Save outlier detection summary
    outliers_summary <- data.frame(
      SampleID = colnames(selectDataSE),
      Correlation_Outlier = CorRes\$outliers,
      PCA_Outlier = PCAres\$outliers,
      Excluded = (CorRes\$outliers | PCAres\$outliers)
    )
    write.csv(outliers_summary, "outliers_summary.csv", row.names = FALSE)
    
    # Save ANOVA and replicate filtering results
    if (!is.null(ANOVAres\$anova)) {
      write.csv(as.data.frame(ANOVAres\$anova), "replicate_anova_results.csv", row.names = TRUE)
    }
    
    # Save final cleaned SummarizedExperiment object
    saveRDS(FinalSE, "final_summarized_experiment.rds")
    
    # Save dataset-wide period profiling results
    write.csv(as.data.frame(PeriodRes), "period_detection_results.csv", row.names = TRUE)
    
    # Save feature-wise oscillation detection results
    saveRDS(discoODAres, "oscillation_detection_results.rds")
    if (!is.null(discoODAres\$CS)) {
      write.csv(as.data.frame(discoODAres\$CS), "oscillation_detection_cosinor.csv", row.names = TRUE)
    }

    writeLines(c(
        '"BIOC_DISCORHYTHM_STEP_BY_STEP_RHYTHM_ANALYSIS":',
        paste0('    DiscoRhythm: ', as.character(packageVersion('DiscoRhythm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_rhythm_analysis.csv versions.yml
    """
}

workflow BIOC_DISCORHYTHM_STEP_BY_STEP_RHYTHM_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ temporal_data.csv ] ]

    main:
    BIOC_DISCORHYTHM_STEP_BY_STEP_RHYTHM_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DISCORHYTHM_STEP_BY_STEP_RHYTHM_ANALYSIS.out.tables
    plots    = BIOC_DISCORHYTHM_STEP_BY_STEP_RHYTHM_ANALYSIS.out.plots
    objects  = BIOC_DISCORHYTHM_STEP_BY_STEP_RHYTHM_ANALYSIS.out.objects
    versions = BIOC_DISCORHYTHM_STEP_BY_STEP_RHYTHM_ANALYSIS.out.versions
}
