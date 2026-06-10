#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: xcms — lc_ms_feature_compounding
// Group LC-MS features presumably representing signal from the same originating compound (compounding) based on retention time, abundance correlation, and EIC sim
// Input: xmse
// Container: quay.io/biocontainers/bioconductor-xcms:4.8.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_XCMS_LC_MS_FEATURE_COMPOUNDING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-xcms:4.8.0--r45ha27e39d_0"

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
    .bm_deps <- c("MSnbase", "MsFeatures", "faahKO", "pheatmap", "xcms")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(MSnbase)
    library(xcms)
    library(faahKO)
    library(MsFeatures)
    library(pheatmap)
    
    # 1. Load preprocessed data
    # The pipeline expects a preprocessed XcmsExperiment or XCMSnExp object named 'xmse' in the working directory.
    if (!file.exists("xmse")) {
      stop("Input file 'xmse' not found in the working directory.")
    }
    
    xmse <- readRDS("xmse")
    
    # 2. Group features by similar retention time
    xmse <- groupFeatures(xmse, SimilarRtimeParam(20))
    
    # 3. Refine feature groups by abundance correlation across samples
    xmse <- groupFeatures(xmse, AbundanceSimilarityParam(threshold = 0.7, transform = log2), filled = TRUE)
    
    # 4. Refine feature groups by EIC similarity
    # This step requires access to the original raw MS files. We wrap it in a tryCatch
    # to ensure the pipeline remains robust if raw files are missing or paths have changed.
    tryCatch({
      xmse <- groupFeatures(xmse, EicSimilarityParam(threshold = 0.7, n = 2))
    }, error = function(e) {
      warning("EIC similarity grouping skipped or failed: ", e\$message)
    })
    
    # 5. Access feature groups
    fgrps <- featureGroups(xmse)
    
    # Save the compounded XcmsExperiment/XCMSnExp object
    saveRDS(xmse, "xmse_compounded.rds")
    
    # Export feature definitions with their assigned feature groups to a CSV file
    fd <- featureDefinitions(xmse)
    if (!is.null(fd)) {
      fd\$feature_group <- fgrps
      write.csv(as.data.frame(fd), "feature_groups.csv", row.names = TRUE)
    }
    
    # Generate a summary plot of the feature groups
    pdf("feature_compounding_summary.pdf", width = 7, height = 5)
    if (!all(is.na(fgrps))) {
      tbl <- table(fgrps)
      barplot(sort(tbl, decreasing = TRUE)[1:min(20, length(tbl))],
              las = 2, 
              main = "Top 20 Feature Groups by Size",
              ylab = "Number of Features",
              col = "steelblue")
    } else {
      plot.new()
      text(0.5, 0.5, "No feature groups detected or all are NA", cex = 1.2)
    }
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_XCMS_LC_MS_FEATURE_COMPOUNDING":
        xcms: \$(Rscript -e 'cat(as.character(packageVersion("xcms")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lc_ms_feature_compounding.csv versions.yml
    """
}

workflow BIOC_XCMS_LC_MS_FEATURE_COMPOUNDING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ xmse ] ]

    main:
    BIOC_XCMS_LC_MS_FEATURE_COMPOUNDING(ch_input)

    emit:
    tables   = BIOC_XCMS_LC_MS_FEATURE_COMPOUNDING.out.tables
    plots    = BIOC_XCMS_LC_MS_FEATURE_COMPOUNDING.out.plots
    objects  = BIOC_XCMS_LC_MS_FEATURE_COMPOUNDING.out.objects
    versions = BIOC_XCMS_LC_MS_FEATURE_COMPOUNDING.out.versions
}
