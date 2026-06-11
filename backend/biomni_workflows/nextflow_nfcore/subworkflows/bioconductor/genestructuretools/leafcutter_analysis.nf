#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeneStructureTools — leafcutter_analysis
// Import Leafcutter intron results, summarize transcript changes, and generate alternative isoforms based on intron usage clusters.
// Input: per_intron_results.tab, example_gtf.gtf, BSgenome.Mmusculus.UCSC.mm10
// Container: quay.io/biocontainers/bioconductor-genestructuretools:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Mmusculus.UCSC.mm10, GeneStructureTools, GenomicRanges, rtracklayer
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import GTF and extract exons
//  * 2. [Input & Preparation] Read Leafcutter intron results
//  * 3. [Visualization & Output] Summarize transcript changes using leafcutterTranscriptChangeSummary
//  * 4. [Core Analysis] Select a cluster and generate alternative isoforms using alternativeIntronUsage

nextflow.enable.dsl = 2

process BIOC_GENESTRUCTURETOOLS_LEAFCUTTER_ANALYSIS {
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
    .bm_deps <- c("GeneStructureTools", "GenomicRanges", "rtracklayer", "BSgenome.Mmusculus.UCSC.mm10")
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
    library(GenomicRanges)
    library(rtracklayer)
    library(BSgenome.Mmusculus.UCSC.mm10)
    
    # 1. Import GTF and extract exons
    # The pipeline reads "example_gtf.gtf" directly from the working directory
    gtf <- rtracklayer::import("example_gtf.gtf")
    exons <- gtf[gtf\$type=="exon"]
    
    # Specify the BSGenome annotation
    g <- BSgenome.Mmusculus.UCSC.mm10::BSgenome.Mmusculus.UCSC.mm10
    
    # 2. Read Leafcutter intron results
    # The pipeline reads "per_intron_results.tab" directly from the working directory
    intron_results <- read.delim("per_intron_results.tab", stringsAsFactors = FALSE)
    
    # 3. Summarize transcript changes using leafcutterTranscriptChangeSummary
    leafcutter_summary <- leafcutterTranscriptChangeSummary(intron_results, 
                                                            exons = exons,
                                                            BSgenome = g,
                                                            NMD = FALSE,
                                                            showProgressBar = FALSE)
    
    # Save the summary results
    write.csv(leafcutter_summary, "leafcutter_transcript_change_summary.csv", row.names = FALSE)
    
    # 4. Select a cluster and generate alternative isoforms using alternativeIntronUsage
    # We attempt to select the documented cluster "chr16:clu_1396".
    # For robustness, if that specific cluster is not present in the user's input,
    # we fall back to the first available cluster.
    target_cluster <- "chr16:clu_1396"
    if (!(target_cluster %in% leafcutter_summary\$cluster) && nrow(leafcutter_summary) > 0) {
      target_cluster <- leafcutter_summary\$cluster[1]
    }
    
    cluster <- leafcutter_summary[leafcutter_summary\$cluster==target_cluster,]
    
    # Generate alternative isoforms
    altIsoforms1396 <- alternativeIntronUsage(cluster, exons)
    
    # Filter for downregulated and upregulated isoforms
    altIsoforms1396_dnreg <- altIsoforms1396[grep("dnre", 
                                                altIsoforms1396\$transcript_id)]
    altIsoforms1396_upreg <- altIsoforms1396[grep("upre", 
                                                altIsoforms1396\$transcript_id)]
    
    # Save the generated alternative isoforms
    saveRDS(altIsoforms1396, "altIsoforms_all.rds")
    saveRDS(altIsoforms1396_dnreg, "altIsoforms_dnreg.rds")
    saveRDS(altIsoforms1396_upreg, "altIsoforms_upreg.rds")
    
    # Export alternative isoforms as GTF for downstream visualization or analysis
    tryCatch({
      rtracklayer::export(altIsoforms1396, "altIsoforms_all.gtf")
      rtracklayer::export(altIsoforms1396_dnreg, "altIsoforms_dnreg.gtf")
      rtracklayer::export(altIsoforms1396_upreg, "altIsoforms_upreg.gtf")
    }, error = function(e) {
      warning("Could not export GRanges to GTF format: ", e\$message)
    })
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_GENESTRUCTURETOOLS_LEAFCUTTER_ANALYSIS":',
        paste0('    GeneStructureTools: ', as.character(packageVersion('GeneStructureTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_leafcutter_analysis.csv versions.yml
    """
}

workflow BIOC_GENESTRUCTURETOOLS_LEAFCUTTER_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ per_intron_results.tab, example_gtf.gtf, BSgenome.Mmusculus.UCSC.mm10 ] ]

    main:
    BIOC_GENESTRUCTURETOOLS_LEAFCUTTER_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GENESTRUCTURETOOLS_LEAFCUTTER_ANALYSIS.out.tables
    plots    = BIOC_GENESTRUCTURETOOLS_LEAFCUTTER_ANALYSIS.out.plots
    objects  = BIOC_GENESTRUCTURETOOLS_LEAFCUTTER_ANALYSIS.out.objects
    versions = BIOC_GENESTRUCTURETOOLS_LEAFCUTTER_ANALYSIS.out.versions
}
