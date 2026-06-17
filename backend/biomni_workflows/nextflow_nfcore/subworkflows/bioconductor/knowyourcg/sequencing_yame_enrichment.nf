#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: knowYourCG — sequencing_yame_enrichment
// Test enrichment of sequencing-based CpG sets formatted as YAME binary vectors.
// Input: input_cpgs.bed, cpg_nocontig.cr
// Container: quay.io/biocontainers/bioconductor-knowyourcg:1.6.3--r45h01b2380_0
// R packages: knowYourCG
// Bioconductor: 3.20 | R: 4.4
// Requires: knowYourCG
// Visualizations: dot plot, enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert BED files to YAME .cg format
//  * 2. [Core Analysis] Run enrichment testing using YAME-compressed files
//  * 3. [Visualization & Output] Plot results

nextflow.enable.dsl = 2

process BIOC_KNOWYOURCG_SEQUENCING_YAME_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    
    # Define input files from working directory
    bed_file <- "input_cpgs.bed"
    ref_cr <- "cpg_nocontig.cr"
    out_file <- "input_cpgs.cg"
    
    # 1. Convert BED files to YAME .cg format
    bedToCg(bed_file, ref_cr, out_file)
    
    # Set up knowledgebase
    temp_dir <- tempdir()
    knowledgebase <- file.path(temp_dir, "ChromHMM.20220414.cm")
    knowledgebase_url <- "https://zenodo.org/records/18175656/files/ChromHMM.20220414.cm"
    download.file(knowledgebase_url, destfile = knowledgebase)
    
    # Use the converted .cg file as the query instead of the downloaded demo query
    query <- out_file
    
    # 2. Run enrichment testing using YAME-compressed files
    res = testEnrichment(query, knowledgebase)
    
    # Save meaningful results
    write.csv(res, "enrichment_results.csv", row.names = FALSE)
    saveRDS(res, "enrichment_results.rds")
    
    # 3. Plot results
    pdf("enrichment_dotplot.pdf", width = 10, height = 8)
    print(KYCG_plotDot(res, short_label = TRUE))
    dev.off()

    writeLines(c(
        '"BIOC_KNOWYOURCG_SEQUENCING_YAME_ENRICHMENT":',
        paste0('    knowYourCG: ', as.character(packageVersion('knowYourCG')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sequencing_yame_enrichment.csv versions.yml
    """
}

workflow BIOC_KNOWYOURCG_SEQUENCING_YAME_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input_cpgs.bed, cpg_nocontig.cr ] ]

    main:
    BIOC_KNOWYOURCG_SEQUENCING_YAME_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_KNOWYOURCG_SEQUENCING_YAME_ENRICHMENT.out.tables
    plots    = BIOC_KNOWYOURCG_SEQUENCING_YAME_ENRICHMENT.out.plots
    objects  = BIOC_KNOWYOURCG_SEQUENCING_YAME_ENRICHMENT.out.objects
    versions = BIOC_KNOWYOURCG_SEQUENCING_YAME_ENRICHMENT.out.versions
}
