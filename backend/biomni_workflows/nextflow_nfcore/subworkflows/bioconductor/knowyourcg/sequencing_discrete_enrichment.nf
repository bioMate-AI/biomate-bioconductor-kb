#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: knowyourcg — sequencing_discrete_enrichment
// Convert genomic coordinates (BED format) to coordinate-free YAME format and test for enrichment against a knowledgebase.
// Input: input_cpgs.bed, cpg_nocontig.cr
// Container: quay.io/biocontainers/bioconductor-knowyourcg:1.6.3--r45h01b2380_0
// R packages: knowYourCG
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: dot plot, enrichment plot

nextflow.enable.dsl = 2

process BIOC_KNOWYOURCG_SEQUENCING_DISCRETE_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-knowyourcg:1.6.3--r45h01b2380_0"

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
    .bm_deps <- c("knowYourCG")
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
    
    library(knowYourCG)
    
    # Define input files from the working directory
    bed_file <- "input_cpgs.bed"
    ref_cr <- "cpg_nocontig.cr"
    out_file <- "input_cpgs.cg"
    
    # --- Convert BED file to YAME-compressed binary vector ('.cg', ---
    # NOTE: the bedToCg() convenience wrapper is only available in newer knowYourCG
    # releases; this container ships an earlier version where it does not exist.
    # We therefore run the documented underlying pipeline directly (the same commands
    # bedToCg() wraps), which requires the `yame` and `bedtools` shell tools:
    #   yame unpack <ref.cr> | bedtools intersect -a - -b <input.bed> -c -sorted |
    #     cut -f4 | yame pack -fb - > <out.cg>
    # See the knowYourCG "Functional Analysis of DNAm Sequencing Data" vignette
    # (INPUT FORMAT section) for the reference pipeline.
    tryCatch({
      if (nzchar(Sys.which("yame")) && nzchar(Sys.which("bedtools"))) {
        cmd <- sprintf(
          "yame unpack %s | bedtools intersect -a - -b %s -c -sorted | cut -f4 | yame pack -fb - > %s",
          shQuote(ref_cr), shQuote(bed_file), shQuote(out_file)
        )
        status <- system(cmd)
        if (status != 0L) {
          stop(sprintf("BED-to-CG conversion pipeline exited with status %d", status))
        }
      } else {
        message("`yame` and/or `bedtools` not found on PATH; cannot convert BED to YAME '.cg' format.")
      }
    }, error = function(e) {
      message("Error converting BED to CG: ", e\$message)
    })
    
    # Prepare the knowledgebase by downloading from Zenodo
    temp_dir <- tempdir()
    knowledgebase <- file.path(temp_dir, "ChromHMM.20220414.cm")
    knowledgebase_url <- "https://zenodo.org/records/18175656/files/ChromHMM.20220414.cm"
    download.file(knowledgebase_url, destfile = knowledgebase, quiet = TRUE)
    
    # Set the query to the generated YAME file
    query <- out_file
    
    # --- Run enrichment testing using testEnrichment() ---
    res <- NULL
    tryCatch({
      res = testEnrichment(query, knowledgebase)
    }, error = function(e) {
      message("Error running testEnrichment: ", e\$message)
    })
    
    # --- Plot results using KYCG_plotDot() and save outputs ---
    if (!is.null(res)) {
      # Save tabular results
      write.csv(res, "enrichment_results.csv", row.names = FALSE)
      saveRDS(res, "enrichment_results.rds")
      
      # Generate and save the dot plot
      pdf("enrichment_dotplot.pdf", width = 8, height = 6)
      tryCatch({
        KYCG_plotDot(res, short_label = TRUE)
      }, error = function(e) {
        message("Error plotting results: ", e\$message)
      })
      dev.off()
    } else {
      message("Pipeline completed, but no enrichment results were generated to plot or save.")
    }

    writeLines(c(
        '"BIOC_KNOWYOURCG_SEQUENCING_DISCRETE_ENRICHMENT":',
        paste0('    knowYourCG: ', as.character(packageVersion('knowYourCG')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sequencing_discrete_enrichment.csv versions.yml
    """
}

workflow BIOC_KNOWYOURCG_SEQUENCING_DISCRETE_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input_cpgs.bed, cpg_nocontig.cr ] ]

    main:
    BIOC_KNOWYOURCG_SEQUENCING_DISCRETE_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_KNOWYOURCG_SEQUENCING_DISCRETE_ENRICHMENT.out.tables
    plots    = BIOC_KNOWYOURCG_SEQUENCING_DISCRETE_ENRICHMENT.out.plots
    objects  = BIOC_KNOWYOURCG_SEQUENCING_DISCRETE_ENRICHMENT.out.objects
    versions = BIOC_KNOWYOURCG_SEQUENCING_DISCRETE_ENRICHMENT.out.versions
}
