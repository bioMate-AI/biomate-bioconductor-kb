#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeneStructureTools — whippet_analysis
// Import, filter, and analyze Whippet alternative splicing events, generate in silico alternative isoforms, and annotate/compare their open reading frames (ORFs).
// Input: whippet_file_directory, example_gtf.gtf, BSgenome.Mmusculus.UCSC.mm10
// Container: quay.io/biocontainers/bioconductor-genestructuretools:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Mmusculus.UCSC.mm10, GeneStructureTools, GenomicRanges, Gviz, rtracklayer, stringr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read Whippet dataset using readWhippetDataSet
//  * 2. [Input & Preparation] Import GTF and prepare exon/transcript annotations
//  * 3. [Core Analysis] Filter Whippet events using filterWhippetEvents
//  * 4. [Visualization & Output] Summarize transcript changes using whippetTranscriptChangeSummary
//  * 5. [Core Analysis] Model specific splicing events (e.g., Exon Skipping with findExonContainingTranscripts and skipExonInTranscript, or Intron Retenti
//  * 6. [Core Analysis] Annotate ORFs using getOrfs and upstream ORFs using getUOrfs
//  * 7. [Core Analysis] Compare ORFs between isoforms using orfDiff
//  * 8. [Visualization & Output] Annotate gene models for visualization using annotateGeneModel

nextflow.enable.dsl = 2

process BIOC_GENESTRUCTURETOOLS_WHIPPET_ANALYSIS {
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
    .bm_deps <- c("GeneStructureTools", "GenomicRanges", "stringr", "BSgenome.Mmusculus.UCSC.mm10", "Gviz", "rtracklayer")
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
        library(stringr)
        library(BSgenome.Mmusculus.UCSC.mm10)
        library(Gviz)
        library(rtracklayer)
        
        # 1. Read Whippet dataset
        whippet_file_directory <- "whippet_file_directory"
        wds <- readWhippetDataSet(whippet_file_directory)
        
        # 2. Import GTF and prepare exon/transcript annotations
        gtf <- rtracklayer::import("example_gtf.gtf")
        exons <- gtf[gtf\$type == "exon"]
        transcripts <- gtf[gtf\$type == "transcript"]
        
        if (!("first_last" %in% colnames(mcols(exons)))) {
          t <- as.data.frame(table(exons\$transcript_id))
          exons\$first_last <- NA
          exons\$first_last[exons\$exon_number == 1] <- "first"
          exons\$first_last[exons\$exon_number == t\$Freq[match(exons\$transcript_id, t\$Var1)]] <- "last"
        }
        
        g <- BSgenome.Mmusculus.UCSC.mm10::BSgenome.Mmusculus.UCSC.mm10
        
        # 3. Filter Whippet events
        wds <- filterWhippetEvents(
          whippetDataSet = wds,
          probability = 0.95, # min probability
          psiDelta = 0.1, # min change in PSI
          eventTypes = "all" # all event types
        )
        
        # 4. Summarize transcript changes
        whippet_summary <- whippetTranscriptChangeSummary(
          wds,
          exons = exons,
          transcripts = transcripts,
          BSgenome = g,
          NMD = FALSE # ignore nonsense mediated decay
        )
        
        write.csv(as.data.frame(whippet_summary), "whippet_transcript_change_summary.csv", row.names = FALSE)
        
        # 5. Model specific splicing events
        
        # 5.1 Exon Skipping (CE)
        ce_id <- whippet_summary\$gene[whippet_summary\$type == "CE"][1]
        wds.ce <- filterWhippetEvents(wds, psiDelta = 0, probability = 0, 
                                      event = "CE", idList = ce_id)
        diffSplicingResults(wds.ce)
        coordinates(wds.ce)
        
        exons.ce <- findExonContainingTranscripts(wds.ce, 
                                                  exons = exons,
                                                  transcripts = transcripts)
        skippedExonTranscripts <- skipExonInTranscript(skippedExons = exons.ce,
                                                       exons = exons, 
                                                       match = "skip",
                                                       whippetDataSet = wds.ce)
        
        # 5.2 Intron Retention (RI)
        ri_id <- whippet_summary\$gene[whippet_summary\$type == "RI"][1]
        wds.ri <- filterWhippetEvents(wds, psiDelta = 0, probability = 0, 
                                      event = "RI", idList = ri_id)
        exons.ri <- findIntronContainingTranscripts(wds.ri, exons)
        retainedIntronTranscripts <- addIntronInTranscript(exons.ri, 
                                                           exons = exons, 
                                                           whippetDataSet = wds.ri,
                                                           glueExons = TRUE)
        
        # 5.3 Alternative Acceptor (AA)
        aa_id <- whippet_summary\$gene[whippet_summary\$type == "AA"][1]
        wds.aa <- filterWhippetEvents(wds, psiDelta = 0, probability = 0, 
                                      event = "AA", idList = aa_id)
        junctionPairs.aa <- findJunctionPairs(wds.aa, type = "AA")
        altTranscripts <- replaceJunction(wds.aa, 
                                          junctionPairs.aa, 
                                          exons, 
                                          type = "AA")
        xTranscripts <- altTranscripts[altTranscripts\$set == "AA_X"]
        yTranscripts <- altTranscripts[altTranscripts\$set == "AA_Y"]
        
        # 6. Annotate ORFs
        normalTranscripts <- exons[exons\$transcript_id %in% exons.ce\$transcript_id]
        
        orfs_normal <- getOrfs(normalTranscripts, BSgenome = g, 
                               returnLongestOnly = FALSE, allFrames = TRUE)
        orfs_skipped <- getOrfs(skippedExonTranscripts[skippedExonTranscripts\$set == "skipped_exon"],
                                BSgenome = g,
                                returnLongestOnly = FALSE, allFrames = TRUE)
        orfs_included <- getOrfs(skippedExonTranscripts[skippedExonTranscripts\$set == "included_exon"],
                                 BSgenome = g,
                                 returnLongestOnly = FALSE, allFrames = TRUE)
        
        upstreamORFs <- getUOrfs(normalTranscripts, BSgenome = g, orfs = orfs_normal, findExonB = TRUE)
        
        orfs_normal <- getOrfs(normalTranscripts, BSgenome = g, 
                               returnLongestOnly = FALSE, allFrames = TRUE,
                               uORFs = TRUE)
        
        # 7. Compare ORFs
        orfChange <- orfDiff(orfsX = orfs_included, 
                             orfsY = orfs_skipped, 
                             filterNMD = FALSE,
                             compareBy = "gene",
                             geneSimilarity = TRUE,
                             compareUTR = TRUE,
                             allORFs = orfs_normal)
        
        write.csv(as.data.frame(orfChange), "orf_change_diff.csv", row.names = FALSE)
        
        # 8. Annotate gene models
        geneModel.skipped <- annotateGeneModel(skippedExonTranscripts[skippedExonTranscripts\$set == "skipped_exon"], orfs_skipped)
        geneModel.included <- annotateGeneModel(skippedExonTranscripts[skippedExonTranscripts\$set == "included_exon"], orfs_included)
        
        saveRDS(geneModel.skipped, "geneModel_skipped.rds")
        saveRDS(geneModel.included, "geneModel_included.rds")
        
        # 9. Visualization of Splicing Events
        pdf("splicing_events_visualization.pdf", width = 10, height = 8)
        tryCatch({
          gtr <- GenomeAxisTrack()
          
          # CE visualization
          geneModel.all.ce <- GeneRegionTrack(makeGeneModel(exons[exons\$gene_id == skippedExonTranscripts\$gene_id[1]]), 
                                              name = "Reference Gene", showId = TRUE, transcriptAnnotation = "transcript")
          geneModelNormal.ce <- GeneRegionTrack(makeGeneModel(skippedExonTranscripts[skippedExonTranscripts\$set == "included_exon"]), 
                                                name = "Reference Isoform", showId = TRUE, fill = "#4D7ABE", transcriptAnnotation = "transcript")
          geneModelSkipped.ce <- GeneRegionTrack(makeGeneModel(skippedExonTranscripts[skippedExonTranscripts\$set == "skipped_exon"]), 
                                                 name = "Alternative Isoform", showId = TRUE, fill = "#94AFD8", transcriptAnnotation = "transcript")
          plotTracks(list(gtr, geneModel.all.ce, geneModelNormal.ce, geneModelSkipped.ce), extend.left = 1000, extend.right = 1000)
          
          # RI visualization
          geneModel.all.ri <- GeneRegionTrack(makeGeneModel(exons[exons\$gene_id == retainedIntronTranscripts\$gene_id[1]]), 
                                              name = "Reference Gene", showId = TRUE, transcriptAnnotation = "transcript")
          geneModelNormal.ri <- GeneRegionTrack(makeGeneModel(retainedIntronTranscripts[retainedIntronTranscripts\$set == "spliced_intron"]), 
                                                name = "Reference Isoform", showId = TRUE, fill = "#4D7ABE", transcriptAnnotation = "transcript")
          geneModelRetained.ri <- GeneRegionTrack(makeGeneModel(retainedIntronTranscripts[retainedIntronTranscripts\$set == "retained_intron"]), 
                                                  name = "Alternative Isoform", showId = TRUE, fill = "#94AFD8", transcriptAnnotation = "transcript")
          plotTracks(list(gtr, geneModel.all.ri, geneModelNormal.ri, geneModelRetained.ri), extend.left = 1000, extend.right = 1000)
        }, error = function(e) {
          message("Gviz plotting failed: ", e\$message)
        })
        dev.off()
        
        message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_GENESTRUCTURETOOLS_WHIPPET_ANALYSIS":',
        paste0('    GeneStructureTools: ', as.character(packageVersion('GeneStructureTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_whippet_analysis.csv versions.yml
    """
}

workflow BIOC_GENESTRUCTURETOOLS_WHIPPET_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ whippet_file_directory, example_gtf.gtf, BSgenome.Mmusculus.UCSC.mm10 ] ]

    main:
    BIOC_GENESTRUCTURETOOLS_WHIPPET_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GENESTRUCTURETOOLS_WHIPPET_ANALYSIS.out.tables
    plots    = BIOC_GENESTRUCTURETOOLS_WHIPPET_ANALYSIS.out.plots
    objects  = BIOC_GENESTRUCTURETOOLS_WHIPPET_ANALYSIS.out.objects
    versions = BIOC_GENESTRUCTURETOOLS_WHIPPET_ANALYSIS.out.versions
}
