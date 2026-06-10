#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: xcms — alignment_to_external_reference
// Align an experimental dataset to an external reference dataset using landmark features.
// Input: ref.rds, tst.rds
// Container: quay.io/biocontainers/bioconductor-xcms:4.8.0--r45ha27e39d_0
// Requires: MsExperiment, MsFeatures, xcms
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract landmark features (lamas) from reference QC samples using filterFeatures with PercentMissingFilter
//  * 2. [Core Analysis] Align experimental dataset using adjustRtime with LamaParama
//  * 3. [Core Analysis] Apply adjusted retention times using applyAdjustedRtime

nextflow.enable.dsl = 2

process BIOC_XCMS_ALIGNMENT_TO_EXTERNAL_REFERENCE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("MsExperiment", "MsFeatures", "xcms")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
            
        # Load required libraries
        library(xcms)
        library(MsExperiment)
        library(MsFeatures)
        
        # 1. Load the experimental and reference datasets from the working directory
        if (!file.exists("ref.rds") || !file.exists("tst.rds")) {
          stop("Required input files 'ref.rds' and/or 'tst.rds' are missing from the working directory.")
        }
        
        ref <- readRDS("ref.rds")
        tst <- readRDS("tst.rds")
        
        # 2. Extract landmark features (lamas) from reference QC samples
        f <- sampleData(ref)\$sample_type
        f[f != "QC"] <- NA
        ref <- filterFeatures(ref, PercentMissingFilter(threshold = 0, f = f))
        ref_mz_rt <- featureDefinitions(ref)[, c("mzmed","rtmed")]
        colnames(ref_mz_rt) <- c("mz", "rt")
        
        # 3. Align experimental dataset using adjustRtime with LamaParama
        param <- LamaParama(
          lamas = ref_mz_rt, 
          method = "loess", 
          span = 0.5, 
          outlierTolerance = 3, 
          zeroWeight = 10, 
          ppm = 20, 
          tolerance = 0, 
          toleranceRt = 20, 
          bs = "tp"
        )
        
        tst_adjusted <- adjustRtime(tst, param = param)
        
        # 4. Export a CSV table of raw vs adjusted retention times
        rt_df <- data.frame(
          spectrum_id = seq_along(rtime(tst_adjusted)),
          raw_rt = rtime(tst_adjusted, adjusted = FALSE),
          adjusted_rt = rtime(tst_adjusted, adjusted = TRUE)
        )
        write.csv(rt_df, "adjusted_retention_times.csv", row.names = FALSE)
        
        # Generate a PDF plot of the adjusted retention times
        pdf("alignment_plot.pdf", width = 8, height = 6)
        tryCatch({
          plotAdjustedRtime(tst_adjusted)
        }, error = function(e) {
          warning("Could not plot adjusted retention times: ", e\$message)
        })
        dev.off()
        
        # 5. Apply adjusted retention times and save outputs
        tst_adjusted <- applyAdjustedRtime(tst_adjusted)
        
        # Save the final adjusted XcmsExperiment object
        saveRDS(tst_adjusted, "tst_adjusted.rds")

    writeLines(c(
        '"BIOC_XCMS_ALIGNMENT_TO_EXTERNAL_REFERENCE":',
        paste0('    xcms: ', as.character(packageVersion('xcms')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alignment_to_external_reference.csv versions.yml
    """
}

workflow BIOC_XCMS_ALIGNMENT_TO_EXTERNAL_REFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ref.rds, tst.rds ] ]

    main:
    BIOC_XCMS_ALIGNMENT_TO_EXTERNAL_REFERENCE(ch_input)

    emit:
    tables   = BIOC_XCMS_ALIGNMENT_TO_EXTERNAL_REFERENCE.out.tables
    plots    = BIOC_XCMS_ALIGNMENT_TO_EXTERNAL_REFERENCE.out.plots
    objects  = BIOC_XCMS_ALIGNMENT_TO_EXTERNAL_REFERENCE.out.objects
    versions = BIOC_XCMS_ALIGNMENT_TO_EXTERNAL_REFERENCE.out.versions
}
