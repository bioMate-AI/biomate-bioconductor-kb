#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: icetea — end_to_end_tss_analysis
// Perform end-to-end TSS detection and differential expression analysis starting from raw multiplexed paired-end FASTQ files.
// Input: mapcap_test_R1.fastq.gz, mapcap_test_R2.fastq.gz, reference_genome.fa
// Container: quay.io/biocontainers/bioconductor-icetea:1.28.0--r45hdfd78af_0
// R packages: icetea, Rsubread, rtracklayer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ICETEA_END_TO_END_TSS_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-icetea:1.28.0--r45hdfd78af_0"

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
    .bm_deps <- c("icetea", "Rsubread", "rtracklayer")
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
    library(icetea)
    library(Rsubread)
    library(rtracklayer)
    
    # --- Create a CapSet object with raw FASTQ files and sample ---
    idxlist <- c("CAAGTG", "TTAGCC", "GTGGAA", "TGTGAG")
    fnames <- c("embryo1", "embryo2", "embryo3", "embryo4")
    
    cs <- newCapSet(expMethod = 'MAPCap',
                    fastq_R1 = 'mapcap_test_R1.fastq.gz',
                    fastq_R2 = 'mapcap_test_R2.fastq.gz',
                    idxList = idxlist,
                    sampleNames = fnames)
    
    # --- De-multiplex the FASTQ files using demultiplexFASTQ ---
    dir.create("splitting", showWarnings = FALSE)
    cs <- demultiplexFASTQ(cs, max_mismatch = 1, outdir = "splitting", ncores = 10)
    
    # --- Build a subread index using Rsubread::buildindex ---
    dir.create("genome_index", showWarnings = FALSE)
    buildindex(basename = "genome_index/dm6", reference = "reference_genome.fa")
    subread_idx <- "genome_index/dm6"
    
    # --- Map the de-multiplexed FASTQ files using mapCaps ---
    dir.create("mapping", showWarnings = FALSE)
    cs <- mapCaps(cs, subread_idx, outdir = "mapping", ncores = 20, logfile = "mapping/subread_mapping.log")
    
    # --- Filter PCR duplicates using filterDuplicates ---
    dir.create("removedup", showWarnings = FALSE)
    cs <- filterDuplicates(cs, outdir = "removedup")
    
    # --- Detect TSSs using detectTSS and export them using ---
    dir.create("tssCalling", showWarnings = FALSE)
    cs <- detectTSS(cs, groups = c("wt", "wt", "mut", "mut"),
                     outfile_prefix = "tssCalling/testTSS", restrictChr = "X", ncores = 1)
    exportTSS(cs, merged = TRUE, outfile_prefix = "tssCalling/testTSS")
    
    # --- Perform differential TSS expression analysis using ---
    csfit <- fitDiffTSS(cs, groups = rep(c("wt","mut"), each = 2), normalization = "windowTMM",
                         outplots = NULL, plotref = "embryo1")
    
    # Save the fit object
    saveRDS(csfit, file = "diffTSS_fit.rds")
    
    # Detect differential TSS
    de_tss <- detectDiffTSS(csfit, testGroup = "mut", contGroup = "wt",
                   TSSfile = "tssCalling/testTSS_merged.bed", MAplot_fdr = 0.05)
    
    # Save the differential TSS GRanges object
    saveRDS(de_tss, file = "de_tss_results.rds")
    
    # Export the significant results to BED
    if (inherits(de_tss, "GRanges")) {
      sig_tss <- de_tss[de_tss\$score < 0.05]
      if (length(sig_tss) > 0) {
        export.bed(sig_tss, con = "diffTSS_output.bed")
      } else {
        # Fallback: export all if none are below the threshold
        export.bed(de_tss, con = "diffTSS_output_all.bed")
      }
    }

    writeLines(c(
        '"BIOC_ICETEA_END_TO_END_TSS_ANALYSIS":',
        paste0('        icetea: ', as.character(packageVersion("icetea")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_end_to_end_tss_analysis.csv versions.yml
    """
}

workflow BIOC_ICETEA_END_TO_END_TSS_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mapcap_test_R1.fastq.gz, mapcap_test_R2.fastq.gz, reference_genome.fa ] ]

    main:
    BIOC_ICETEA_END_TO_END_TSS_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ICETEA_END_TO_END_TSS_ANALYSIS.out.tables
    plots    = BIOC_ICETEA_END_TO_END_TSS_ANALYSIS.out.plots
    objects  = BIOC_ICETEA_END_TO_END_TSS_ANALYSIS.out.objects
    versions = BIOC_ICETEA_END_TO_END_TSS_ANALYSIS.out.versions
}
