#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: xcms — compounding_feature_grouping
// Group LC-MS features representing different ions/adducts/isotopes of the same originating compound.
// Input: xmse.rds
// Container: quay.io/biocontainers/bioconductor-xcms:4.8.0--r45ha27e39d_0
// R packages: MSnbase, MsFeatures, faahKO, xcms
// Bioconductor: 3.20 | R: 4.4
// Requires: MSnbase, MsFeatures, faahKO, xcms
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Group features by similar retention time using groupFeatures with SimilarRtimeParam
//  * 2. [Core Analysis] Refine groups by abundance correlation using groupFeatures with AbundanceSimilarityParam
//  * 3. [Core Analysis] Refine groups by EIC similarity using groupFeatures with EicSimilarityParam

nextflow.enable.dsl = 2

process BIOC_XCMS_COMPOUNDING_FEATURE_GROUPING {
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
    .bm_deps <- c("MSnbase", "MsFeatures", "faahKO", "xcms")
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
    library(MSnbase)
    library(xcms)
    library(faahKO)
    library(MsFeatures)
    
    # Read the preprocessed XcmsExperiment object from the working directory
    xmse <- readRDS("xmse.rds")
    
    # Stage 1: Group features by similar retention time
    xmse <- groupFeatures(xmse, SimilarRtimeParam(20))
    
    # Stage 2: Refine groups by abundance correlation
    xmse <- groupFeatures(xmse, AbundanceSimilarityParam(threshold = 0.7, transform = log2), filled = TRUE)
    
    # Stage 3: Refine groups by EIC similarity
    xmse <- groupFeatures(xmse, EicSimilarityParam(threshold = 0.7, n = 2))
    
    # Save the final grouped XcmsExperiment object
    saveRDS(xmse, "xmse_grouped.rds")
    
    # Extract and save feature groups mapping
    fg <- featureGroups(xmse)
    fg_df <- data.frame(
      feature_id = names(fg),
      feature_group = fg,
      stringsAsFactors = FALSE
    )
    write.csv(fg_df, "feature_groups.csv", row.names = FALSE)
    
    # Generate a PDF plot showing the distribution of feature group sizes
    pdf("feature_groups_distribution.pdf")
    if (!all(is.na(fg))) {
      group_sizes <- table(fg)
      barplot(
        table(group_sizes),
        main = "Distribution of Feature Group Sizes",
        xlab = "Number of Features in Group",
        ylab = "Number of Groups",
        col = "skyblue"
      )
    } else {
      plot.new()
      text(0.5, 0.5, "No feature groups detected or all are NA", cex = 1.2)
    }
    dev.off()

    writeLines(c(
        '"BIOC_XCMS_COMPOUNDING_FEATURE_GROUPING":',
        paste0('    xcms: ', as.character(packageVersion('xcms')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_compounding_feature_grouping.csv versions.yml
    """
}

workflow BIOC_XCMS_COMPOUNDING_FEATURE_GROUPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ xmse.rds ] ]

    main:
    BIOC_XCMS_COMPOUNDING_FEATURE_GROUPING(ch_input)

    emit:
    tables   = BIOC_XCMS_COMPOUNDING_FEATURE_GROUPING.out.tables
    plots    = BIOC_XCMS_COMPOUNDING_FEATURE_GROUPING.out.plots
    objects  = BIOC_XCMS_COMPOUNDING_FEATURE_GROUPING.out.objects
    versions = BIOC_XCMS_COMPOUNDING_FEATURE_GROUPING.out.versions
}
