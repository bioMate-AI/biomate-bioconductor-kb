#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: QuasR — bis_seq_analysis
// Align bisulfite-converted reads and quantify DNA methylation levels at CpG sites.
// Input: samples_bis_single.txt, hg19sub.fa
// Container: quay.io/biocontainers/bioconductor-quasr:1.50.0--r45ha27e39d_0
// R packages: Biostrings, GenomicRanges, QuasR
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, GenomicRanges, QuasR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Align bisulfite reads using qAlign with bisulfite="dir"
//  * 2. [Core Analysis] Quantify CpG methylation using qMeth
//  * 3. [Core Analysis] Calculate methylation percentage
//  * 4. [Core Analysis] Quantify methylation in specific query regions

nextflow.enable.dsl = 2

process BIOC_QUASR_BIS_SEQ_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("Biostrings", "GenomicRanges", "QuasR")
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
    library(QuasR)
    library(Biostrings)
    library(GenomicRanges)
    
    # Define input files from the working directory
    sampleFile <- "samples_bis_single.txt"
    genomeFile <- "hg19sub.fa"
    
    # 1. Align bisulfite reads using qAlign with bisulfite="dir"
    proj4 <- qAlign(sampleFile, genomeFile, bisulfite = "dir")
    proj4
    
    # 2. Quantify CpG methylation using qMeth
    meth <- qMeth(proj4, mode = "CpGcomb", collapseBySample = TRUE)
    meth
    saveRDS(meth, "meth_CpGcomb.rds")
    
    # 3. Calculate methylation percentage
    chrs <- readDNAStringSet(genomeFile)
    sum(vcountPattern("CG", chrs))
    
    length(qMeth(proj4))
    length(qMeth(proj4, keepZero = FALSE))
    
    percMeth <- mcols(meth)[, 2] * 100 / mcols(meth)[, 1]
    summary(percMeth)
    
    # Save methylation percentage to a CSV file
    write.csv(data.frame(percMeth = percMeth), "percMeth.csv", row.names = FALSE)
    
    # 4. Quantify methylation in specific query regions
    # Query 1: Specific GRanges region
    meth_q1 <- qMeth(proj4, query = GRanges("chr1", IRanges(start = 31633, width = 2)),
                     collapseBySample = TRUE)
    meth_q1
    saveRDS(meth_q1, "meth_query_specific.rds")
    
    # Query 2: promRegSel
    # Define promRegSel using coordinates compatible with hg19sub to make the call runnable
    promRegSel <- GRanges(
      seqnames = c("chr1", "chr1"),
      ranges = IRanges(start = c(31000, 32000), end = c(31500, 32500)),
      strand = c("+", "-")
    )
    names(promRegSel) <- c("region_1", "region_2")
    
    meth_q2 <- qMeth(proj4, query = promRegSel, collapseByQueryRegion = TRUE,
                     collapseBySample = TRUE)
    meth_q2
    saveRDS(meth_q2, "meth_query_promRegSel.rds")

    writeLines(c(
        '"BIOC_QUASR_BIS_SEQ_ANALYSIS":',
        paste0('    QuasR: ', as.character(packageVersion('QuasR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bis_seq_analysis.csv versions.yml
    """
}

workflow BIOC_QUASR_BIS_SEQ_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ samples_bis_single.txt, hg19sub.fa ] ]

    main:
    BIOC_QUASR_BIS_SEQ_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_QUASR_BIS_SEQ_ANALYSIS.out.tables
    plots    = BIOC_QUASR_BIS_SEQ_ANALYSIS.out.plots
    objects  = BIOC_QUASR_BIS_SEQ_ANALYSIS.out.objects
    versions = BIOC_QUASR_BIS_SEQ_ANALYSIS.out.versions
}
