#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: icetea — bam_entry_tss_analysis
// Perform TSS detection and analysis starting directly from pre-aligned and de-duplicated BAM files.
// Input: sample1.bam, sample2.bam
// Container: quay.io/biocontainers/bioconductor-icetea:1.28.0--r45hdfd78af_0
// R packages: icetea
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ICETEA_BAM_ENTRY_TSS_ANALYSIS {
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
    .bm_deps <- c("icetea")
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
    
    # Load required library
    library(icetea)
    
    # Verify input files exist in the working directory
    input_files <- c("sample1.bam", "sample2.bam")
    for (f in input_files) {
      if (!file.exists(f)) {
        stop(paste("Required input file missing from working directory:", f))
      }
    }
    
    # Define sample names corresponding to the input BAM files
    fnames <- c("sample1", "sample2")
    
    # Create CapSet object directly from pre-filtered BAM files
    cs2 <- newCapSet(expMethod = 'MAPCap',
                     filtered_file = input_files,
                     sampleNames = fnames)
    
    # Create output directory for TSS calling
    dir.create("tssCalling", showWarnings = FALSE, recursive = TRUE)
    
    # Detect TSSs using detectTSS
    # Note: groups is adjusted to c("wt", "mut") to match the 2 input samples
    cs2 <- detectTSS(cs2, groups = c("wt", "mut"),
                     outfile_prefix = "tssCalling/testTSS", restrictChr = "X", ncores = 1)
    
    # Export TSSs to BED format
    exportTSS(cs2, merged = TRUE, outfile_prefix = "tssCalling/testTSS")
    
    # Save the final CapSet object and sample info as meaningful outputs
    saveRDS(cs2, file = "tssCalling/capset_tss_analysis.rds")
    write.csv(sampleInfo(cs2), file = "tssCalling/sample_info.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_ICETEA_BAM_ENTRY_TSS_ANALYSIS":',
        paste0('        icetea: ', as.character(packageVersion("icetea")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bam_entry_tss_analysis.csv versions.yml
    """
}

workflow BIOC_ICETEA_BAM_ENTRY_TSS_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample1.bam, sample2.bam ] ]

    main:
    BIOC_ICETEA_BAM_ENTRY_TSS_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ICETEA_BAM_ENTRY_TSS_ANALYSIS.out.tables
    plots    = BIOC_ICETEA_BAM_ENTRY_TSS_ANALYSIS.out.plots
    objects  = BIOC_ICETEA_BAM_ENTRY_TSS_ANALYSIS.out.objects
    versions = BIOC_ICETEA_BAM_ENTRY_TSS_ANALYSIS.out.versions
}
