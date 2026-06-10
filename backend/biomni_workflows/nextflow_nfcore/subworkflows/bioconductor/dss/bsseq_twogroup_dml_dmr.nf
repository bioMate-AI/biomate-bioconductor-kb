#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DSS — bsseq_twogroup_dml_dmr
// Detect differentially methylated loci (DML) and differentially methylated regions (DMR) from BS-seq data in a two-group comparison.
// Input: sample_files.txt
// Container: quay.io/biocontainers/bioconductor-dss:2.58.0--r45h01b2380_0
// R packages: DSS, bsseq
// Bioconductor: 3.20 | R: 4.4
// Requires: DSS, bsseq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load text files and create a BSseq object using makeBSseqData
//  * 2. [Core Analysis] Perform statistical test for DML using DMLtest (with optional smoothing)
//  * 3. [Core Analysis] Call DMLs using callDML (with optional delta threshold)
//  * 4. [Core Analysis] Call DMRs using callDMR (with optional delta threshold)
//  * 5. [Visualization & Output] Visualize a selected DMR using showOneDMR

nextflow.enable.dsl = 2

process BIOC_DSS_BSSEQ_TWOGROUP_DML_DMR {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("DSS", "bsseq")
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
        library(DSS)
        require(bsseq)
        
        # 1. Load text files and create a BSseq object using makeBSseqData
        # Read the sample files manifest
        sample_info <- read.table("sample_files.txt", header=TRUE, stringsAsFactors=FALSE)
        
        if (ncol(sample_info) == 1) {
          files <- sample_info[[1]]
        } else {
          if ("filePath" %in% colnames(sample_info)) {
            files <- sample_info\$filePath
          } else if ("file" %in% colnames(sample_info)) {
            files <- sample_info\$file
          } else {
            files <- sample_info[[2]]
          }
        }
        
        # Dynamically determine sample names
        if ("sample" %in% colnames(sample_info)) {
          sample_names <- as.character(sample_info\$sample)
        } else if ("sampleName" %in% colnames(sample_info)) {
          sample_names <- as.character(sample_info\$sampleName)
        } else {
          sample_names <- paste0("Sample", seq_along(files))
        }
        
        # Dynamically determine groups
        if ("group" %in% colnames(sample_info)) {
          groups <- as.character(sample_info\$group)
        } else if ("condition" %in% colnames(sample_info)) {
          groups <- as.character(sample_info\$condition)
        } else {
          half <- floor(length(files) / 2)
          groups <- c(rep("Group1", half), rep("Group2", length(files) - half))
        }
        
        # Read the individual sample data files
        dat_list <- lapply(files, function(f) read.table(f, header=TRUE, stringsAsFactors=FALSE))
        
        # Construct the BSseq object
        BSobj = makeBSseqData(dat_list, sample_names)
        
        # 2. Perform statistical test for DML using DMLtest (with and without smoothing)
        unique_groups <- unique(groups)
        if (length(unique_groups) < 2) {
          stop("At least two groups are required for DMLtest.")
        }
        group1_samples <- sample_names[groups == unique_groups[1]]
        group2_samples <- sample_names[groups == unique_groups[2]]
        
        dmlTest = DMLtest(BSobj, group1=group1_samples, group2=group2_samples)
        
        dmlTest.sm = DMLtest(BSobj, group1=group1_samples, group2=group2_samples,
                             smoothing=TRUE)
        
        # 3. Call DMLs using callDML (with and without delta threshold)
        dmls = callDML(dmlTest, p.threshold=0.001)
        
        dmls2 = callDML(dmlTest, delta=0.1, p.threshold=0.001)
        
        # 4. Call DMRs using callDMR (with and without delta threshold)
        dmrs = callDMR(dmlTest, p.threshold=0.01)
        
        dmrs2 = callDMR(dmlTest, delta=0.1, p.threshold=0.05)
        
        # 5. Visualize a selected DMR using showOneDMR and save to PDF
        pdf("dmr_visualization.pdf", width=10, height=8)
        if (!is.null(dmrs) && nrow(dmrs) > 0) {
          tryCatch({
            showOneDMR(dmrs[1,], BSobj)
          }, error = function(e) {
            warning("Could not plot the first DMR: ", e\$message)
          })
        } else {
          plot.new()
          text(0.5, 0.5, "No DMRs detected to plot.")
        }
        dev.off()
        
        # Save meaningful results to output files
        write.csv(dmls, "dmls_results.csv", row.names=FALSE)
        write.csv(dmls2, "dmls_delta0.1_results.csv", row.names=FALSE)
        write.csv(dmrs, "dmrs_results.csv", row.names=FALSE)
        write.csv(dmrs2, "dmrs_delta0.1_results.csv", row.names=FALSE)
        
        saveRDS(dmlTest, "dmlTest_results.rds")
        saveRDS(dmlTest.sm, "dmlTest_smoothed_results.rds")
        saveRDS(BSobj, "BSobj_data.rds")

    writeLines(c(
        '"BIOC_DSS_BSSEQ_TWOGROUP_DML_DMR":',
        paste0('    DSS: ', as.character(packageVersion('DSS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bsseq_twogroup_dml_dmr.csv versions.yml
    """
}

workflow BIOC_DSS_BSSEQ_TWOGROUP_DML_DMR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample_files.txt ] ]

    main:
    BIOC_DSS_BSSEQ_TWOGROUP_DML_DMR(ch_input)

    emit:
    tables   = BIOC_DSS_BSSEQ_TWOGROUP_DML_DMR.out.tables
    plots    = BIOC_DSS_BSSEQ_TWOGROUP_DML_DMR.out.plots
    objects  = BIOC_DSS_BSSEQ_TWOGROUP_DML_DMR.out.objects
    versions = BIOC_DSS_BSSEQ_TWOGROUP_DML_DMR.out.versions
}
