#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rbec — syncom_community_profiling
// Estimate SynCom community profiles and correct sequencing errors using reference sequences.
// Input: test_raw_merged_reads.fastq.gz, test_ref.fasta
// Container: quay.io/biocontainers/bioconductor-rbec:1.18.0--r45ha27e39d_0
// R packages: Rbec
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RBEC_SYNCOM_COMMUNITY_PROFILING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rbec:1.18.0--r45ha27e39d_0"

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
    .bm_deps <- c("Rbec")
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
    library(Rbec)
    
    # Define input file paths (must read EXACTLY these files from the working directory)
    fq <- "test_raw_merged_reads.fastq.gz"
    ref <- "test_ref.fasta"
    
    # Verify that the input files exist
    if (!file.exists(fq)) {
      stop(paste("Required input file missing:", fq))
    }
    if (!file.exists(ref)) {
      stop(paste("Required input file missing:", ref))
    }
    
    # Define and create the output directory for Rbec results
    outdir <- "rbec_output"
    if (!dir.exists(outdir)) {
      dir.create(outdir, recursive = TRUE)
    }
    
    # Run Rbec to perform error correction and profile estimation
    # Using the exact positional arguments from the documented code,
    # replacing the volatile tempdir() with our dedicated output directory.
    message("Running Rbec error correction and community profiling...")
    Rbec(fq, ref, outdir, 1, 500, 33)
    
    # List and verify the generated output files
    output_files <- list.files(outdir, full.names = TRUE)
    message("Rbec execution completed successfully. Generated outputs:")
    print(output_files)

    writeLines(c(
        '"BIOC_RBEC_SYNCOM_COMMUNITY_PROFILING":',
        paste0('        rbec: ', as.character(packageVersion("rbec")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_syncom_community_profiling.csv versions.yml
    """
}

workflow BIOC_RBEC_SYNCOM_COMMUNITY_PROFILING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ test_raw_merged_reads.fastq.gz, test_ref.fasta ] ]

    main:
    BIOC_RBEC_SYNCOM_COMMUNITY_PROFILING(ch_input)

    emit:
    tables   = BIOC_RBEC_SYNCOM_COMMUNITY_PROFILING.out.tables
    plots    = BIOC_RBEC_SYNCOM_COMMUNITY_PROFILING.out.plots
    objects  = BIOC_RBEC_SYNCOM_COMMUNITY_PROFILING.out.objects
    versions = BIOC_RBEC_SYNCOM_COMMUNITY_PROFILING.out.versions
}
