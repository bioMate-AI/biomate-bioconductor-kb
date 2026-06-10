#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: icetea — tss_analysis_from_bams
// Perform TSS detection and differential expression analysis starting directly from pre-aligned and pre-filtered BAM files.
// Input: embryo1.bam, embryo2.bam, embryo3.bam, embryo4.bam
// Container: quay.io/biocontainers/bioconductor-icetea:1.28.0--r45hdfd78af_0
// R packages: icetea, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: icetea, rtracklayer
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize CapSet object from BAM files
//  * 2. [Visualization & Output] Detect TSSs and export BED files
//  * 3. [Core Analysis] Perform differential TSS expression analysis

nextflow.enable.dsl = 2

process BIOC_ICETEA_TSS_ANALYSIS_FROM_BAMS {
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
    .bm_deps <- c("icetea", "rtracklayer")
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
        library(icetea)
        
        # Define sample names and input BAM files from the working directory
        fnames <- c("embryo1", "embryo2", "embryo3", "embryo4")
        bam_files <- c("embryo1.bam", "embryo2.bam", "embryo3.bam", "embryo4.bam")
        
        # Verify that the input files exist before proceeding
        for (bf in bam_files) {
          if (!file.exists(bf)) {
            stop(paste("Required input file missing in working directory:", bf))
          }
        }
        
        # 1. Initialize CapSet object from BAM files
        cs2 <- newCapSet(expMethod = 'MAPCap',
                         filtered_file = bam_files,
                         sampleNames = fnames)
        
        # 2. Detect TSSs and export BED files
        if (!dir.exists("tssCalling")) {
          dir.create("tssCalling")
        }
        
        cs2 <- detectTSS(cs2, groups = c("wt", "wt", "mut", "mut"),
                         outfile_prefix = "tssCalling/testTSS", ncores = 1)
        
        exportTSS(cs2, merged = TRUE, outfile_prefix = "tssCalling/testTSS")
        
        # 3. Perform differential TSS expression analysis
        csfit <- fitDiffTSS(cs2, groups = rep(c("wt","mut"), each = 2), normalization = "windowTMM",
                             outplots = NULL, plotref = "embryo1")
        
        de_tss <- detectDiffTSS(csfit, testGroup = "mut", contGroup = "wt",
                       TSSfile = "tssCalling/testTSS_merged.bed", MAplot_fdr = 0.05)
        
        # Save meaningful results to output files
        saveRDS(cs2, file = "capset_tss_detected.rds")
        saveRDS(csfit, file = "diffTSS_fit.rds")
        saveRDS(de_tss, file = "de_tss_results.rds")
        
        # Export the differential TSS results as a CSV table
        write.csv(as.data.frame(de_tss), file = "de_tss_results.csv", row.names = FALSE)
        
        # Export significant differential TSSs to a BED file if rtracklayer is available
        if (requireNamespace("rtracklayer", quietly = TRUE)) {
          library(rtracklayer)
          sig_de_tss <- de_tss[de_tss\$score < 0.05]
          export.bed(sig_de_tss, con = "diffTSS_output.bed")
        }

    writeLines(c(
        '"BIOC_ICETEA_TSS_ANALYSIS_FROM_BAMS":',
        paste0('    icetea: ', as.character(packageVersion('icetea')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tss_analysis_from_bams.csv versions.yml
    """
}

workflow BIOC_ICETEA_TSS_ANALYSIS_FROM_BAMS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ embryo1.bam, embryo2.bam, embryo3.bam, embryo4.bam ] ]

    main:
    BIOC_ICETEA_TSS_ANALYSIS_FROM_BAMS(ch_input)

    emit:
    tables   = BIOC_ICETEA_TSS_ANALYSIS_FROM_BAMS.out.tables
    plots    = BIOC_ICETEA_TSS_ANALYSIS_FROM_BAMS.out.plots
    objects  = BIOC_ICETEA_TSS_ANALYSIS_FROM_BAMS.out.objects
    versions = BIOC_ICETEA_TSS_ANALYSIS_FROM_BAMS.out.versions
}
