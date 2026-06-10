#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RSVSim — sv_detection_comparison
// Compare simulated SVs (ground truth) with query SVs detected by an external algorithm to evaluate detection performance.
// Input: query_svs.bed, simulated_svs.csv
// Container: quay.io/biocontainers/bioconductor-rsvsim:1.50.0--r45hdfd78af_0
// Requires: RSVSim
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Extract simulated SVs from the simulation metadata. 2. Load or define the query SVs detected by the external algorithm. 3. Compare

nextflow.enable.dsl = 2

process BIOC_RSVSIM_SV_DETECTION_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("RSVSim")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required library
    library(RSVSim)
    
    # Verify that the required user input files exist
    if (!file.exists("query_svs.bed")) {
      stop("Error: query_svs.bed not found in the working directory.")
    }
    if (!file.exists("simulated_svs.csv")) {
      stop("Error: simulated_svs.csv not found in the working directory.")
    }
    
    # Load query SVs (detected SVs in BED or BEDPE format)
    querySVs <- read.table("query_svs.bed", header=FALSE, sep="\t", stringsAsFactors=FALSE)
    
    # Format querySVs columns to match the expected structure for BED or BEDPE
    if (ncol(querySVs) >= 6) {
      colnames(querySVs)[1:6] <- c("chr", "start1", "end1", "chr2", "start2", "end2")
      if (ncol(querySVs) >= 7) {
        colnames(querySVs)[7] <- "bpSeq"
      }
    } else {
      colnames(querySVs)[1:3] <- c("chr", "start", "end")
      if (ncol(querySVs) >= 4) {
        colnames(querySVs)[4] <- "bpSeq"
      }
    }
    
    # Load simulated SVs (ground truth metadata table)
    simSVs <- read.csv("simulated_svs.csv", stringsAsFactors=FALSE)
    
    # Compare the two sets using compareSV with a specified breakpoint tolerance of 3bp
    comparison_results <- compareSV(querySVs, simSVs, tol=3)
    
    # Write the meaningful results to output files
    write.csv(comparison_results, "sv_comparison_results.csv", row.names=FALSE)
    saveRDS(comparison_results, "sv_comparison_results.rds")

    writeLines(c(
        '"BIOC_RSVSIM_SV_DETECTION_COMPARISON":',
        paste0('    RSVSim: ', as.character(packageVersion('RSVSim')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sv_detection_comparison.csv versions.yml
    """
}

workflow BIOC_RSVSIM_SV_DETECTION_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ query_svs.bed, simulated_svs.csv ] ]

    main:
    BIOC_RSVSIM_SV_DETECTION_COMPARISON(ch_input)

    emit:
    tables   = BIOC_RSVSIM_SV_DETECTION_COMPARISON.out.tables
    plots    = BIOC_RSVSIM_SV_DETECTION_COMPARISON.out.plots
    objects  = BIOC_RSVSIM_SV_DETECTION_COMPARISON.out.objects
    versions = BIOC_RSVSIM_SV_DETECTION_COMPARISON.out.versions
}
