#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowFP — gating_quality_control
// Perform quality control on multi-tube or plate-based flow cytometry data to detect sample/tube inconsistencies and identify outlier bins.
// Input: fs1, fs2, plate
// Container: quay.io/biocontainers/bioconductor-flowfp:1.68.0--r45h01b2380_0
// R packages: flowCore, flowFP
// Bioconductor: 3.20 | R: 4.4
// Requires: flowCore, flowFP
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate fingerprints using flowFP with specific parameters
//  * 2. [Visualization & Output] Visualize fingerprint deviations across tubes or plate wells using plot with type="qc" or type="plate"
//  * 3. [Visualization & Output] Identify specific outlier bins by plotting fingerprints against raw data using plot with showbins and transformation='norm'

nextflow.enable.dsl = 2

process BIOC_FLOWFP_GATING_QUALITY_CONTROL {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20-deps"

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
    .bm_deps <- c("flowCore", "flowFP")
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
    library(flowCore)
    library(flowFP)
    
    # 1. Read the declared user input files from the working directory
    fs1 <- readRDS("fs1")
    fs2 <- readRDS("fs2")
    plate <- readRDS("plate")
    
    # 2. Generate fingerprints and perform Quality Control for fs1
    fp1 <- flowFP (fs1, name="self model: fs1", nRecursions=5)
    
    pdf("gate_qc_fs1.pdf", width=10, height=8)
    plot (fp1, type="qc", main="Gate QC for Sample fs1")
    dev.off()
    
    # 3. Generate fingerprints and perform Quality Control for fs2 (with potential outliers)
    fp2 <- flowFP (fs2, name="self model: fs2", nRecursions=5)
    
    pdf("gate_qc_fs2.pdf", width=10, height=8)
    plot (fp2, type="qc", main="Gate QC for Sample fs2")
    dev.off()
    
    # 4. Identify specific outlier bins by plotting fingerprints against raw data
    pdf("outlier_bins_fs2.pdf", width=10, height=8)
    c_log2norm <- counts(fp2, transformation="log2norm")
    outlier_hi <- as.integer(which.max(apply(c_log2norm, 1, sd, na.rm=TRUE)))
    outlier_bins <- as.integer(order(abs(c_log2norm[outlier_hi, ]), decreasing=TRUE, na.last=TRUE)[1:4])
    
    plot (fp2, fs2, hi=outlier_hi, showbins=outlier_bins, pch=20, cex=.3, transformation='norm')
    dev.off()
    
    # 5. Generate fingerprints and perform Quality Control for the 96-well plate
    fp <- flowFP (plate, nRecursions=5)
    
    pdf("plate_qc.pdf", width=12, height=10)
    plot (fp, type='plate')
    dev.off()
    
    # 6. Save meaningful results to disk
    saveRDS(fp1, "fp1.rds")
    saveRDS(fp2, "fp2.rds")
    saveRDS(fp, "fp_plate.rds")
    
    write.csv(counts(fp1, transformation="raw"), "counts_fp1_raw.csv", row.names=TRUE)
    write.csv(counts(fp2, transformation="raw"), "counts_fp2_raw.csv", row.names=TRUE)
    write.csv(counts(fp, transformation="raw"), "counts_plate_raw.csv", row.names=TRUE)

    writeLines(c(
        '"BIOC_FLOWFP_GATING_QUALITY_CONTROL":',
        paste0('    flowFP: ', as.character(packageVersion('flowFP')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gating_quality_control.csv versions.yml
    """
}

workflow BIOC_FLOWFP_GATING_QUALITY_CONTROL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fs1, fs2, plate ] ]

    main:
    BIOC_FLOWFP_GATING_QUALITY_CONTROL(ch_input)

    emit:
    tables   = BIOC_FLOWFP_GATING_QUALITY_CONTROL.out.tables
    plots    = BIOC_FLOWFP_GATING_QUALITY_CONTROL.out.plots
    objects  = BIOC_FLOWFP_GATING_QUALITY_CONTROL.out.objects
    versions = BIOC_FLOWFP_GATING_QUALITY_CONTROL.out.versions
}
