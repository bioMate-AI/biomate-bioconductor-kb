#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: teqc — automated_html_reports
// Generate automated single-sample and multi-sample HTML quality control reports.
// Input: ExampleSet_Targets.bed, ExampleSet_Reads.bed
// Container: quay.io/biocontainers/bioconductor-teqc:4.32.0--r45hdfd78af_0
// R packages: TEQC
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TEQC_AUTOMATED_HTML_REPORTS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-teqc:4.32.0--r45hdfd78af_0"

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
    .bm_deps <- c("TEQC")
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
    
    # --- Load the TEQC library ---
    library(TEQC)
    
    # --- Define paths to target and read files (expected in the ---
    readsfile <- "ExampleSet_Reads.bed"
    targetsfile <- "ExampleSet_Targets.bed"
    
    # Verify input files exist
    if (!file.exists(readsfile)) {
      stop(paste("Error: Input reads file not found:", readsfile))
    }
    if (!file.exists(targetsfile)) {
      stop(paste("Error: Input targets file not found:", targetsfile))
    }
    
    # Save intermediate objects to disk as named output files
    reads_obj <- get.reads(readsfile, skip = 0, idcol = 4)
    targets_obj <- get.targets(targetsfile, skip = 0)
    
    saveRDS(reads_obj, "reads.rds")
    saveRDS(targets_obj, "targets.rds")
    write.csv(as.data.frame(targets_obj), "targets_summary.csv", row.names = FALSE)
    
    # --- Run TEQCreport to generate a single-sample HTML report ---
    TEQCreport(
      sampleName = "Test Sample",
      targetsName = "Human Exome",
      referenceName = "Human Genome",
      destDir = "report",
      reads = get.reads(readsfile, skip = 0, idcol = 4),
      targets = get.targets(targetsfile, skip = 0),
      genome = "hg19"
    )
    
    # Duplicate the report directory to simulate a second sample for multiTEQCreport
    if (dir.exists("report")) {
      dir.create("report2", showWarnings = FALSE)
      file.copy(from = list.files("report", full.names = TRUE), to = "report2", recursive = TRUE)
    } else {
      stop("Error: 'report' directory was not created by TEQCreport.")
    }
    
    # --- Run multiTEQCreport to combine multiple single-sample ---
    multiTEQCreport(
      singleReportDirs = c("report", "report2"),
      samplenames = c("Sample A", "Sample B"),
      projectName = "Test Project",
      targetsName = "Human Exome",
      referenceName = "Human Genome",
      destDir = "multiTEQCreport"
    )

    writeLines(c(
        '"BIOC_TEQC_AUTOMATED_HTML_REPORTS":',
        paste0('        teqc: ', as.character(packageVersion("teqc")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_automated_html_reports.csv versions.yml
    """
}

workflow BIOC_TEQC_AUTOMATED_HTML_REPORTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ExampleSet_Targets.bed, ExampleSet_Reads.bed ] ]

    main:
    BIOC_TEQC_AUTOMATED_HTML_REPORTS(ch_input)

    emit:
    tables   = BIOC_TEQC_AUTOMATED_HTML_REPORTS.out.tables
    plots    = BIOC_TEQC_AUTOMATED_HTML_REPORTS.out.plots
    objects  = BIOC_TEQC_AUTOMATED_HTML_REPORTS.out.objects
    versions = BIOC_TEQC_AUTOMATED_HTML_REPORTS.out.versions
}
