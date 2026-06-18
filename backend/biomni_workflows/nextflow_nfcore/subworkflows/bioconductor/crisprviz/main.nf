#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: crisprViz — single_guideset_visualization_and_filtering
// Visualize, annotate, and filter a single GuideSet targeting a gene of interest to select optimal gRNAs.
// Input: GuideSet, GRangesList, BSgenome, GRanges
// Container: quay.io/biocontainers/bioconductor-crisprviz:1.12.0--r45hdfd78af_0
// R packages: BSgenome, GenomicRanges, crisprDesign, crisprViz
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome, GenomicRanges, crisprDesign, crisprViz
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Plot initial candidate gRNAs against the gene model to inspect isoform coverage
//  * 2. [Core Analysis] Adjust the genomic window to zoom in on specific exons or regions of interest
//  * 3. [Core Analysis] Add repeat and SNP annotation tracks to identify problematic guides
//  * 4. [Core Analysis] Filter out guides overlapping repeats or SNPs
//  * 5. [Core Analysis] Add functional annotations (CAGE, DNase) and filter guides overlapping active regions
//  * 6. [Visualization & Output] Visualize final selected guides with on-target scores or nucleotide-level resolution

nextflow.enable.dsl = 2

process BIOC_CRISPRVIZ_SINGLE_GUIDESET_VISUALIZATION_AND_FILTERING {
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
    .bm_deps <- c("BSgenome", "GenomicRanges", "crisprDesign", "crisprViz")
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
    library(BSgenome)
    library(crisprDesign)
    library(crisprViz)
    library(GenomicRanges)
    
    # ==========================================
    # 1. READ USER INPUT FILES FROM WORKING DIR
    # ==========================================
    # The pipeline reads exactly the required GuideSet, GRangesList, BSgenome, and GRanges files.
    guideSet  <- readRDS("guideSet.rds")
    geneModel <- readRDS("geneModel.rds")
    bsgenome  <- readRDS("bsgenome.rds")
    repeats   <- readRDS("repeats.rds")
    cage      <- readRDS("cage.rds")
    dnase     <- readRDS("dnase.rds")
    
    # Extract target gene name dynamically
    target_gene <- "TargetGene"
    if ("gene_name" %in% colnames(mcols(geneModel\$transcripts))) {
        target_gene <- geneModel\$transcripts\$gene_name[1]
    } else if ("gene_symbol" %in% colnames(mcols(geneModel\$transcripts))) {
        target_gene <- geneModel\$transcripts\$gene_symbol[1]
    } else if ("gene_id" %in% colnames(mcols(geneModel\$transcripts))) {
        target_gene <- geneModel\$transcripts\$gene_id[1]
    }
    
    # ==========================================
    # 2. PIPELINE EXECUTION & VISUALIZATION
    # ==========================================
    
    # --- Step 1: Plot initial candidate gRNAs against the gene model to inspect isoform coverage ---
    pdf("plot1_initial.pdf", width=8, height=6)
    plotGuideSet(guideSet[1:min(4, length(guideSet))],
                 geneModel=geneModel,
                 targetGene=target_gene)
    dev.off()
    
    from <- min(start(geneModel\$transcripts))
    to <- max(end(geneModel\$transcripts))
    
    pdf("plot2_full_gene.pdf", width=8, height=6)
    plotGuideSet(guideSet[1:min(4, length(guideSet))],
                 geneModel=geneModel,
                 targetGene=target_gene,
                 from=from,
                 to=to,
                 extend.left=1000,
                 extend.right=1000)
    dev.off()
    
    pdf("plot3_no_labels.pdf", width=8, height=10)
    plotGuideSet(guideSet,
                 geneModel=geneModel,
                 targetGene=target_gene,
                 showGuideLabels=FALSE,
                 from=from,
                 to=to,
                 extend.left=1000,
                 extend.right=1000)
    dev.off()
    
    
    # --- Step 2: Adjust the genomic window to zoom in on specific exons or regions of interest ---
    if (!is.null(geneModel\$cds) && length(geneModel\$cds) > 0) {
        targetExon <- geneModel\$cds[1]
    } else {
        targetExon <- geneModel\$exons[1]
    }
    from <- start(targetExon)
    to <- end(targetExon)
    
    pdf("plot4_target_exon.pdf", width=8, height=6)
    plotGuideSet(guideSet,
                 geneModel=geneModel,
                 targetGene=target_gene,
                 from=from,
                 to=to,
                 extend.left=20,
                 extend.right=20)
    dev.off()
    
    pdf("plot5_pam_only.pdf", width=8, height=6)
    plotGuideSet(guideSet,
                 geneModel=geneModel,
                 targetGene=target_gene,
                 from=from,
                 to=to,
                 extend.left=20,
                 extend.right=20,
                 pamSiteOnly=TRUE)
    dev.off()
    
    selectedGuides <- names(guideSet)[1:min(9, length(guideSet))]
    candidateGuides <- guideSet[selectedGuides]
    
    pdf("plot6_on_target.pdf", width=8, height=6)
    score_col <- "score_deephf"
    if (!score_col %in% colnames(mcols(candidateGuides))) {
        score_cols <- grep("score", colnames(mcols(candidateGuides)), value=TRUE, ignore.case=TRUE)
        if (length(score_cols) > 0) {
            score_col <- score_cols[1]
        } else {
            score_col <- NULL
        }
    }
    
    if (!is.null(score_col)) {
        plotGuideSet(candidateGuides,
                     geneModel=geneModel,
                     targetGene=target_gene,
                     onTargetScore=score_col)
    } else {
        plotGuideSet(candidateGuides,
                     geneModel=geneModel,
                     targetGene=target_gene)
    }
    dev.off()
    
    
    # --- Step 3: Add repeat and SNP annotation tracks to identify problematic guides ---
    pdf("plot7_sequence.pdf", width=10, height=4)
    plotGuideSet(guideSet,
                 geneModel=geneModel,
                 targetGene=target_gene,
                 bsgenome=bsgenome,
                 margin=0.3)
    dev.off()
    
    from <- min(start(guideSet))
    to <- max(end(guideSet))
    
    has_snp <- "hasSNP" %in% colnames(mcols(guideSet))
    
    pdf("plot8_repeats_snps.pdf", width=8, height=6)
    plotGuideSet(guideSet,
                 geneModel=geneModel,
                 targetGene=target_gene,
                 guideStacking="dense",
                 annotations=list(Repeats=repeats),
                 pamSiteOnly=TRUE,
                 from=from,
                 to=to,
                 extend.left=600,
                 extend.right=100,
                 includeSNPTrack=has_snp)
    dev.off()
    
    
    # --- Step 4: Filter out guides overlapping repeats or SNPs ---
    filteredGuideSet <- crisprDesign::removeRepeats(guideSet,
                                                    gr.repeats=repeats)
    if ("hasSNP" %in% colnames(mcols(filteredGuideSet))) {
        filteredGuideSet <- filteredGuideSet[!filteredGuideSet\$hasSNP]
    }
    
    pdf("plot9_filtered.pdf", width=8, height=6)
    plotGuideSet(filteredGuideSet,
                 geneModel=geneModel,
                 targetGene=target_gene,
                 guideStacking="dense",
                 annotations=list(Repeats=repeats),
                 pamSiteOnly=TRUE,
                 from=from,
                 to=to,
                 extend.left=600,
                 extend.right=100,
                 includeSNPTrack=has_snp)
    dev.off()
    
    
    # --- Step 5: Add functional annotations (CAGE, DNase) and filter guides overlapping active regions ---
    pdf("plot10_cage_dnase.pdf", width=8, height=6)
    plotGuideSet(filteredGuideSet,
                 geneModel=geneModel,
                 targetGene=target_gene,
                 guideStacking="dense",
                 annotations=list(CAGE=cage, DNase=dnase),
                 pamSiteOnly=TRUE,
                 from=from,
                 to=to,
                 extend.left=600,
                 extend.right=100)
    dev.off()
    
    overlaps <- findOverlaps(filteredGuideSet, dnase, ignore.strand=TRUE)
    finalGuideSet <- filteredGuideSet[queryHits(overlaps)]
    
    pdf("plot11_final.pdf", width=8, height=6)
    plotGuideSet(finalGuideSet,
                 geneModel=geneModel,
                 targetGene=target_gene,
                 guideStacking="dense",
                 annotations=list(CAGE=cage, DNase=dnase),
                 pamSiteOnly=TRUE,
                 margin=0.4)
    dev.off()
    
    
    # --- Step 6: Visualize final selected guides with on-target scores or nucleotide-level resolution ---
    pdf("plot12_multiple_guidesets.pdf", width=8, height=8)
    plotMultipleGuideSets(list(SelectedGuides=finalGuideSet),
                          geneModel=geneModel,
                          targetGene=target_gene,
                          bsgenome=bsgenome,
                          margin=0.2,
                          gcWindow=10)
    dev.off()
    
    
    # ==========================================
    # 3. WRITE OUTPUT FILES
    # ==========================================
    saveRDS(filteredGuideSet, "filteredGuideSet.rds")
    saveRDS(finalGuideSet, "finalGuideSet.rds")
    
    # Export final selected guides metadata to CSV
    final_df <- as.data.frame(finalGuideSet)
    write.csv(final_df, "finalGuideSet.csv", row.names=FALSE)
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_CRISPRVIZ_SINGLE_GUIDESET_VISUALIZATION_AND_FILTERING":',
        paste0('    crisprViz: ', as.character(packageVersion('crisprViz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_guideset_visualization_and_filtering.csv versions.yml
    """
}

workflow BIOC_CRISPRVIZ_SINGLE_GUIDESET_VISUALIZATION_AND_FILTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ GuideSet, GRangesList, BSgenome, GRanges ] ]

    main:
    BIOC_CRISPRVIZ_SINGLE_GUIDESET_VISUALIZATION_AND_FILTERING(ch_input)

    emit:
    tables   = BIOC_CRISPRVIZ_SINGLE_GUIDESET_VISUALIZATION_AND_FILTERING.out.tables
    plots    = BIOC_CRISPRVIZ_SINGLE_GUIDESET_VISUALIZATION_AND_FILTERING.out.plots
    objects  = BIOC_CRISPRVIZ_SINGLE_GUIDESET_VISUALIZATION_AND_FILTERING.out.objects
    versions = BIOC_CRISPRVIZ_SINGLE_GUIDESET_VISUALIZATION_AND_FILTERING.out.versions
}
