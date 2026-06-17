#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ribodipa — ribodipa_exon_level_pipeline
// Perform differential pattern analysis using annotated exons as the bins for statistical testing.
// Input: bam_path[1:4], bam_path[5]
// Container: quay.io/biocontainers/bioconductor-ribodipa:1.18.0--r45ha27e39d_0
// R packages: RiboDiPA
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RIBODIPA_RIBODIPA_EXON_LEVEL_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ribodipa:1.18.0--r45ha27e39d_0"

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
    .bm_deps <- c("RiboDiPA")
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
    library(RiboDiPA)
    
    # --- Locate input files in the working directory ---
    # Expecting 4 BAM files and 1 GTF file
    bam_files <- list.files(pattern = "\\\\.bam\$", full.names = TRUE)
    gtf_files <- list.files(pattern = "\\\\.gtf\$", full.names = TRUE)
    
    if (length(bam_files) < 4) {
      stop("Error: At least 4 BAM files (.bam) are required in the working directory.")
    }
    if (length(gtf_files) < 1) {
      stop("Error: At least 1 GTF file (.gtf) is required in the working directory.")
    }
    
    # Construct the bam_path vector as specified: 
    # bam_path[1:4] are BAM files, bam_path[5] is the GTF file
    bam_path <- c(bam_files[1:4], gtf_files[1])
    
    # --- Define the experimental design (classlabel) ---
    # We assign the first two BAMs to treatment (2) and the next two to control (1)
    bam_names <- gsub("\\\\.bam\$", "", basename(bam_path[1:4]))
    classlabel <- data.frame(
      condition = c("treatment", "treatment", "control", "control"),
      comparison = c(2, 2, 1, 1)
    )
    rownames(classlabel) <- bam_names
    
    # --- Map RPFs to P-sites and generate total transcript ---
    message("Mapping P-sites...")
    data.psite <- psiteMapping(bam_file_list = bam_path[1:4], 
        gtf_file = bam_path[5], psite.mapping = "auto", cores = 2)
    
    # --- Perform exon-level binning and differential pattern ---
    message("Performing exon-level differential pattern testing...")
    result.exon <- diffPatternTestExon(psitemap = data.psite,
        classlabel = classlabel, method = c('gtxr', 'qvalue'))
    
    # --- Save results to output files ---
    message("Saving results...")
    saveRDS(result.exon, "ribodipa_exon_results.rds")
    
    if (!is.null(result.exon\$gene)) {
      write.csv(result.exon\$gene, "ribodipa_exon_gene_results.csv", row.names = TRUE)
    }
    
    if (!is.null(result.exon\$bin)) {
      if (is.data.frame(result.exon\$bin)) {
        write.csv(result.exon\$bin, "ribodipa_exon_bin_results.csv", row.names = TRUE)
      } else {
        saveRDS(result.exon\$bin, "ribodipa_exon_bin_results.rds")
      }
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_RIBODIPA_RIBODIPA_EXON_LEVEL_PIPELINE":',
        paste0('        ribodipa: ', as.character(packageVersion("ribodipa")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ribodipa_exon_level_pipeline.csv versions.yml
    """
}

workflow BIOC_RIBODIPA_RIBODIPA_EXON_LEVEL_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bam_path[1:4], bam_path[5] ] ]

    main:
    BIOC_RIBODIPA_RIBODIPA_EXON_LEVEL_PIPELINE(ch_input)

    emit:
    tables   = BIOC_RIBODIPA_RIBODIPA_EXON_LEVEL_PIPELINE.out.tables
    plots    = BIOC_RIBODIPA_RIBODIPA_EXON_LEVEL_PIPELINE.out.plots
    objects  = BIOC_RIBODIPA_RIBODIPA_EXON_LEVEL_PIPELINE.out.objects
    versions = BIOC_RIBODIPA_RIBODIPA_EXON_LEVEL_PIPELINE.out.versions
}
