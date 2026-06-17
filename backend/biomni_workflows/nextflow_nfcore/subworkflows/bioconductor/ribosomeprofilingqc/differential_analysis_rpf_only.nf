#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ribosomeprofilingqc — differential_analysis_rpf_only
// Count RPF reads and perform differential expression or alternative splicing analysis using RPF data alone.
// Input: RPFs, gtf
// Container: quay.io/biocontainers/bioconductor-ribosomeprofilingqc:1.22.0--r45hdfd78af_0
// R packages: Rsamtools, edgeR, ribosomeProfilingQC, txdbmaker
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RIBOSOMEPROFILINGQC_DIFFERENTIAL_ANALYSIS_RPF_ONLY {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ribosomeprofilingqc:1.22.0--r45hdfd78af_0"

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
    .bm_deps <- c("Rsamtools", "edgeR", "ribosomeProfilingQC", "txdbmaker")
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
    library(ribosomeProfilingQC)
    library(txdbmaker)
    library(edgeR)
    library(Rsamtools)
    
    # ==========================================
    # 1. USER INPUT & ENVIRONMENT SETUP
    # ==========================================
    
    # Locate BAM files in the working directory
    user_bams <- list.files(pattern = "\\\\.bam\$", full.names = TRUE)
    if (length(user_bams) < 4) {
      stop("This workflow requires at least 4 BAM files (2 for KD, 2 for WT) in the working directory.")
    }
    
    # Locate GTF file in the working directory
    gtf_files <- list.files(pattern = "\\\\.gtf(\\\\.gz)?\$", full.names = TRUE)
    if (length(gtf_files) == 0) {
      stop("No GTF file found in the working directory.")
    }
    gtf <- gtf_files[1]
    
    # Create TxDb object from GTF
    txdb <- makeTxDbFromGFF(gtf)
    
    # To faithfully reproduce the vignette's grepl and group structure,
    # we copy/symlink the user's BAM files to the expected names.
    expected_names <- c("RPF.KD1.1.bam", "RPF.KD1.2.bam", "RPF.WT.1.bam", "RPF.WT.2.bam")
    RPFs <- c()
    
    for (i in 1:4) {
      dest <- expected_names[i]
      if (file.exists(dest)) {
        file.remove(dest)
      }
      file.copy(user_bams[i], dest)
      
      # Handle BAM index files
      user_bai <- paste0(user_bams[i], ".bai")
      dest_bai <- paste0(dest, ".bai")
      if (file.exists(dest_bai)) {
        file.remove(dest_bai)
      }
      if (file.exists(user_bai)) {
        file.copy(user_bai, dest_bai)
      } else {
        # Generate index if missing
        indexBam(dest)
      }
      RPFs <- c(RPFs, dest)
    }
    
    # Define groups and sample names matching the vignette
    gp <- c("KD", "KD", "CTL", "CTL")
    group1 <- c("RPF.KD1.1", "RPF.KD1.2")
    group2 <- c("RPF.WT.1", "RPF.WT.2")
    
    # ==========================================
    # 2. EXECUTING THE WORKFLOW
    # ==========================================
    
    # --- Count RPF reads ---
    cnts <- countReads(RPFs, gtf=gtf, level="gene", bestpsite=13, readsLen=c(28,29))
    
    # Save raw counts
    write.csv(cnts\$RPFs, "rpf_counts.csv", row.names = TRUE)
    
    # --- Differential expression analysis using edgeR ---
    y <- DGEList(counts = cnts\$RPFs, group = gp)
    y <- calcNormFactors(y)
    design <- model.matrix(~0+gp)
    colnames(design) <- sub("gp", "", colnames(design))
    y <- estimateDisp(y, design)
    
    # Quasi-likelihood F-tests
    fit <- glmQLFit(y, design)
    qlf <- glmQLFTest(fit)
    qlf_tags <- topTags(qlf, n=3)
    write.csv(as.data.frame(topTags(qlf, n=nrow(qlf))), "edgeR_qlf_results.csv")
    
    # Likelihood ratio tests
    fit <- glmFit(y, design)
    lrt <- glmLRT(fit)
    lrt_tags <- topTags(lrt, n=3)
    write.csv(as.data.frame(topTags(lrt, n=nrow(lrt))), "edgeR_lrt_results.csv")
    
    # --- Calculate coverage depth ---
    coverage <- coverageDepth(RPFs[grepl("KD1|WT", RPFs)], gtf=txdb, level="gene", region="feature with extension")
    
    # --- Alternative splicing/translation events detection and ---
    se <- spliceEvent(coverage, group1, group2)
    write.csv(as.data.frame(se), "splice_events.csv", row.names = FALSE)
    
    # Plot the first detected splice event if available
    if (nrow(se) > 0 && !is.na(se\$feature[1])) {
      pdf("splice_event_plot.pdf", width = 8, height = 6)
      plotSpliceEvent(se, se\$feature[1], coverage, group1, group2)
      dev.off()
    } else {
      message("No alternative splicing events detected to plot.")
    }
    
    # Clean up temporary copied BAM files and indices
    file.remove(expected_names)
    file.remove(paste0(expected_names, ".bai"))

    writeLines(c(
        '"BIOC_RIBOSOMEPROFILINGQC_DIFFERENTIAL_ANALYSIS_RPF_ONLY":',
        paste0('        ribosomeprofilingqc: ', as.character(packageVersion("ribosomeprofilingqc")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_analysis_rpf_only.csv versions.yml
    """
}

workflow BIOC_RIBOSOMEPROFILINGQC_DIFFERENTIAL_ANALYSIS_RPF_ONLY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ RPFs, gtf ] ]

    main:
    BIOC_RIBOSOMEPROFILINGQC_DIFFERENTIAL_ANALYSIS_RPF_ONLY(ch_input)

    emit:
    tables   = BIOC_RIBOSOMEPROFILINGQC_DIFFERENTIAL_ANALYSIS_RPF_ONLY.out.tables
    plots    = BIOC_RIBOSOMEPROFILINGQC_DIFFERENTIAL_ANALYSIS_RPF_ONLY.out.plots
    objects  = BIOC_RIBOSOMEPROFILINGQC_DIFFERENTIAL_ANALYSIS_RPF_ONLY.out.objects
    versions = BIOC_RIBOSOMEPROFILINGQC_DIFFERENTIAL_ANALYSIS_RPF_ONLY.out.versions
}
