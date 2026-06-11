#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BindingSiteFinder — standard_binding_site_definition
// Define precise, reproducible RBP binding sites from iCLIP crosslink sites and coverage bigwig files, and annotate them with gene and transcript region features.
// Input: PureCLIP_crosslink_sites_examples.bed, plus.bw, minus.bw, gencode_v37_annotation.gff3
// Container: quay.io/biocontainers/bioconductor-bindingsitefinder:2.8.0--r45hdfd78af_0
// R packages: GenomicFeatures, BindingSiteFinder, ComplexHeatmap, dplyr, forcats, GenomicAlignments, GenomicRanges, rtracklayer, txdbmaker
// Bioconductor: 3.20 | R: 4.4
// Requires: BindingSiteFinder, GenomicFeatures, GenomicRanges, S4Vectors, rtracklayer, txdbmaker
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import crosslink sites as a GRanges object
//  * 2. [Input & Preparation] Create a metadata table pointing to strand-specific bigwig files
//  * 3. [Input & Preparation] Construct a BSFDataSet using BSFDataSetFromBigWig
//  * 4. [Input & Preparation] Build gene and transcript region annotation objects (GRanges and GRangesList)
//  * 5. [Core Analysis] Run the main wrapper BSFind to estimate width, filter, merge, check reproducibility, and annotate
//  * 6. [Visualization & Output] Export results to BED or Excel

nextflow.enable.dsl = 2

process BIOC_BINDINGSITEFINDER_STANDARD_BINDING_SITE_DEFINITION {
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
    .bm_deps <- c("GenomicFeatures", "BindingSiteFinder", "ComplexHeatmap", "dplyr", "forcats", "GenomicAlignments", "GenomicRanges", "rtracklayer", "txdbmaker")
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
        library(BindingSiteFinder)
        library(rtracklayer)
        library(txdbmaker)
        library(GenomicRanges)
        library(GenomicFeatures)
        
        # 1. Import crosslink sites as a GRanges object
        csFile <- "./PureCLIP_crosslink_sites_examples.bed"
        cs <- rtracklayer::import(con = csFile, format = "BED", extraCols = c("additionalScores" = "character"))
        cs\$additionalScores <- NULL
        
        # 2. Create a metadata table pointing to strand-specific bigwig files
        clipFilesP <- list.files(".", pattern = "plus.bw\$", full.names = TRUE)
        clipFilesM <- list.files(".", pattern = "minus.bw\$", full.names = TRUE)
        
        # Sort to ensure matching replicates
        clipFilesP <- sort(clipFilesP)
        clipFilesM <- sort(clipFilesM)
        
        n_reps <- length(clipFilesP)
        if (n_reps == 0) {
          stop("No bigwig files found matching 'plus.bw\$' in the working directory.")
        }
        
        meta <- data.frame(
          id = seq_len(n_reps),
          condition = factor(rep("WT", n_reps)), 
          clPlus = clipFilesP, 
          clMinus = clipFilesM
        )
        
        # 3. Construct a BSFDataSet using BSFDataSetFromBigWig
        bds <- BSFDataSetFromBigWig(ranges = cs, meta = meta, silent = TRUE)
        
        # 4. Build gene and transcript region annotation objects (GRanges and GRangesList)
        annoFile <- "./gencode_v37_annotation.gff3"
        annoDb <- txdbmaker::makeTxDbFromGFF(file = annoFile, format = "gff3")
        annoInfo <- rtracklayer::import(annoFile, format = "gff3")
        
        # Get genes as GRanges
        gns <- genes(annoDb)
        idx <- match(gns\$gene_id, annoInfo\$gene_id)
        meta_genes <- cbind(S4Vectors::elementMetadata(gns), S4Vectors::elementMetadata(annoInfo)[idx, ])
        meta_genes <- meta_genes[, !duplicated(colnames(meta_genes))]
        S4Vectors::elementMetadata(gns) <- meta_genes
        
        # Get transcript regions
        cdseq <- cds(annoDb)
        intrns <- unlist(intronsByTranscript(annoDb))
        utrs3 <- unlist(threeUTRsByTranscript(annoDb))
        utrs5 <- unlist(fiveUTRsByTranscript(annoDb))
        regions <- GRangesList(CDS = cdseq, Intron = intrns, UTR3 = utrs3, UTR5 = utrs5)
        
        # Determine chromosome for estimation (default to chr22, fallback to first available if chr22 is absent)
        target_chrom <- "chr22"
        if (!(target_chrom %in% seqlevels(cs))) {
          target_chrom <- as.character(seqnames(cs)[1])
        }
        
        # 5. Run the main wrapper BSFind to estimate width, filter, merge, check reproducibility, and annotate
        bdsOut <- BSFind(object = bds, anno.genes = gns, anno.transcriptRegionList = regions,
                        est.subsetChromosome = target_chrom, veryQuiet = TRUE, est.maxBsWidth = 29)
        
        # 6. Export results to BED or Excel/CSV
        getRanges(bdsOut)
        exportToBED(bdsOut, con = "./myResults.bed")
        
        # Export target genes (try xlsx first, fallback to csv if needed)
        tryCatch({
          exportTargetGenes(bdsOut, format = "xlsx", split = "transcriptRegion")
        }, error = function(e) {
          exportTargetGenes(bdsOut, format = "csv", split = "transcriptRegion")
        })
        
        # Save the final BSFDataSet object
        saveRDS(bdsOut, file = "./bdsOut.rds")
        
        # Generate and save diagnostic plots
        pdf("./diagnostic_plots.pdf", width = 8, height = 6)
        try(pureClipGlobalFilterPlot(bdsOut), silent = TRUE)
        try(estimateBsWidthPlot(bdsOut), silent = TRUE)
        try(duplicatedSitesPlot(bdsOut), silent = TRUE)
        try(mergeCrosslinkDiagnosticsPlot(bdsOut), silent = TRUE)
        try(makeBsSummaryPlot(bdsOut), silent = TRUE)
        try(reproducibilityFilterPlot(bdsOut), silent = TRUE)
        try(reproducibilitySamplesPlot(bdsOut), silent = TRUE)
        try(reproducibilityScatterPlot(bdsOut), silent = TRUE)
        try(geneOverlapsPlot(bdsOut), silent = TRUE)
        try(targetGeneSpectrumPlot(bdsOut), silent = TRUE)
        try(transcriptRegionOverlapsPlot(bdsOut), silent = TRUE)
        try(transcriptRegionSpectrumPlot(bdsOut), silent = TRUE)
        dev.off()

    writeLines(c(
        '"BIOC_BINDINGSITEFINDER_STANDARD_BINDING_SITE_DEFINITION":',
        paste0('    BindingSiteFinder: ', as.character(packageVersion('BindingSiteFinder')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_binding_site_definition.csv versions.yml
    """
}

workflow BIOC_BINDINGSITEFINDER_STANDARD_BINDING_SITE_DEFINITION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ PureCLIP_crosslink_sites_examples.bed, plus.bw, minus.bw, gencode_v37_annotation.gff3 ] ]

    main:
    BIOC_BINDINGSITEFINDER_STANDARD_BINDING_SITE_DEFINITION(ch_input)

    emit:
    tables   = BIOC_BINDINGSITEFINDER_STANDARD_BINDING_SITE_DEFINITION.out.tables
    plots    = BIOC_BINDINGSITEFINDER_STANDARD_BINDING_SITE_DEFINITION.out.plots
    objects  = BIOC_BINDINGSITEFINDER_STANDARD_BINDING_SITE_DEFINITION.out.objects
    versions = BIOC_BINDINGSITEFINDER_STANDARD_BINDING_SITE_DEFINITION.out.versions
}
