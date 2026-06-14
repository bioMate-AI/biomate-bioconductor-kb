#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeneStructureTools — dexseq_and_gtf_reannotation
// Reannotate GTF features (UTRs and broad biotypes) and overlap DEXSeq results to identify the exonic part types affected by differential usage.
// Input: example_gtf.gtf, dexseq_results_significant.txt, gencode.vM14.dexseq.gtf
// Container: quay.io/biocontainers/bioconductor-genestructuretools:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GeneStructureTools, rtracklayer
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import GTF and reannotate UTRs to 5' and 3' UTRs using UTR2UTR53
//  * 2. [Core Analysis] Reannotate transcript biotypes into broader categories using addBroadTypes
//  * 3. [Input & Preparation] Import DEXSeq results and exonic parts ranges
//  * 4. [Core Analysis] Find the exon type of significant DEXSeq events using findDEXexonType
//  * 5. [Visualization & Output] Summarize exon types into broader definitions using summariseExonTypes

nextflow.enable.dsl = 2

process BIOC_GENESTRUCTURETOOLS_DEXSEQ_AND_GTF_REANNOTATION {
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
    .bm_deps <- c("GeneStructureTools", "rtracklayer")
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
    library(GeneStructureTools)
    library(rtracklayer)
    
    # 1. Import GTF and reannotate UTRs to 5' and 3' UTRs using UTR2UTR53
    gtf <- rtracklayer::import("example_gtf.gtf")
    gtf_UTRannotated <- UTR2UTR53(gtf)
    
    # 2. Reannotate transcript biotypes into broader categories using addBroadTypes
    gtf_broad <- addBroadTypes(gtf)
    
    # Re-import and reannotate UTRs for the DEXSeq overlap step (matching documented workflow)
    gtf <- rtracklayer::import("example_gtf.gtf")
    gtf <- UTR2UTR53(gtf)
    
    # 3. Import DEXSeq results and exonic parts ranges
    dexseq_ranges <- rtracklayer::import("gencode.vM14.dexseq.gtf")
    dexseq_results.significant <- read.delim("dexseq_results_significant.txt")
    
    # 4. Find the exon type of significant DEXSeq events using findDEXexonType
    dexseq_results.significant\$overlap_types <- findDEXexonType(
      rownames(dexseq_results.significant), 
      dexseq_ranges, 
      gtf = gtf
    )
    
    # 5. Summarize exon types into broader definitions using summariseExonTypes
    dexseq_results.significant\$overlap_types_broad <- summariseExonTypes(
      dexseq_results.significant\$overlap_types
    )
    
    # Write meaningful output files
    rtracklayer::export(gtf_UTRannotated, "example_gtf_UTRannotated.gtf")
    rtracklayer::export(gtf_broad, "example_gtf_broad.gtf")
    write.table(
      dexseq_results.significant, 
      file = "dexseq_results_annotated.txt", 
      sep = "\t", 
      quote = FALSE, 
      row.names = TRUE
    )

    writeLines(c(
        '"BIOC_GENESTRUCTURETOOLS_DEXSEQ_AND_GTF_REANNOTATION":',
        paste0('    GeneStructureTools: ', as.character(packageVersion('GeneStructureTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dexseq_and_gtf_reannotation.csv versions.yml
    """
}

workflow BIOC_GENESTRUCTURETOOLS_DEXSEQ_AND_GTF_REANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example_gtf.gtf, dexseq_results_significant.txt, gencode.vM14.dexseq.gtf ] ]

    main:
    BIOC_GENESTRUCTURETOOLS_DEXSEQ_AND_GTF_REANNOTATION(ch_input)

    emit:
    tables   = BIOC_GENESTRUCTURETOOLS_DEXSEQ_AND_GTF_REANNOTATION.out.tables
    plots    = BIOC_GENESTRUCTURETOOLS_DEXSEQ_AND_GTF_REANNOTATION.out.plots
    objects  = BIOC_GENESTRUCTURETOOLS_DEXSEQ_AND_GTF_REANNOTATION.out.objects
    versions = BIOC_GENESTRUCTURETOOLS_DEXSEQ_AND_GTF_REANNOTATION.out.versions
}
