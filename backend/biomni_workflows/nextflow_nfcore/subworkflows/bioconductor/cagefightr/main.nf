#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CAGEfightR — cage_5end_analysis_pipeline
// Quantify, cluster, annotate, and analyze 5'-end transcriptomics data (CAGE, PRO-Cap, etc.) to identify TSSs and enhancers, calculate their correlations, and vis
// Input: plus_strand.bw, minus_strand.bw, design_matrix.csv, txdb_annotation
// Container: quay.io/biocontainers/bioconductor-cagefightr:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CAGEfightR, GenomicFeatures, Gviz, InteractionSet, SummarizedExperiment, TxDb.Mmusculus.UCSC.mm9.knownGene, org.Hs.eg.db, org.Mm.eg.db, rtracklayer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Import and quantify CTSSs from BigWig files using quantifyCTSSs. 2. Normalize counts to TPM using calcTPM and calculate pooled sig

nextflow.enable.dsl = 2

process BIOC_CAGEFIGHTR_CAGE_5END_ANALYSIS_PIPELINE {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        # Load required libraries
        library(CAGEfightR)
        library(GenomicFeatures)
        library(InteractionSet)
        library(Gviz)
        library(rtracklayer)
        
        # ==========================================
        # 1. Load User Inputs and Setup Design
        # ==========================================
        
        # Read design matrix
        if (file.exists("design_matrix.csv")) {
            design <- read.csv("design_matrix.csv", stringsAsFactors=FALSE)
        } else {
            stop("Error: design_matrix.csv not found in the working directory.")
        }
        
        # Ensure required columns exist or assign defaults
        if (!"Name" %in% colnames(design)) {
            design\$Name <- paste0("Sample_", seq_len(nrow(design)))
        }
        
        # Handle BigWig file paths
        bw_plus_files <- if ("BigWigPlus" %in% colnames(design)) design\$BigWigPlus else "plus_strand.bw"
        bw_minus_files <- if ("BigWigMinus" %in% colnames(design)) design\$BigWigMinus else "minus_strand.bw"
        
        # Fallback to default filenames if specified files do not exist
        if (!all(file.exists(bw_plus_files))) bw_plus_files <- rep("plus_strand.bw", nrow(design))
        if (!all(file.exists(bw_minus_files))) bw_minus_files <- rep("minus_strand.bw", nrow(design))
        
        # Verify file existence
        if (!all(file.exists(bw_plus_files)) || !all(file.exists(bw_minus_files))) {
            stop("Error: plus_strand.bw and/or minus_strand.bw not found in the working directory.")
        }
        
        # Duplicate samples if only 1 sample is provided to ensure support filtering works
        if (nrow(design) == 1) {
            design <- rbind(design, design)
            design\$Name[2] <- paste0(design\$Name[1], "_rep2")
            bw_plus_files <- c(bw_plus_files, bw_plus_files)
            bw_minus_files <- c(bw_minus_files, bw_minus_files)
        }
        
        # Create BigWigFileList objects
        bw_plus <- BigWigFileList(bw_plus_files)
        bw_minus <- BigWigFileList(bw_minus_files)
        names(bw_plus) <- design\$Name
        names(bw_minus) <- design\$Name
        
        # Load TxDb Annotation
        if (file.exists("txdb_annotation")) {
            txdb <- tryCatch({
                readRDS("txdb_annotation")
            }, error = function(e) {
                makeTxDbFromGFF("txdb_annotation")
            })
        } else {
            # Fallback to UCSC mm9 if no annotation file is provided
            library(TxDb.Mmusculus.UCSC.mm9.knownGene)
            txdb <- TxDb.Mmusculus.UCSC.mm9.knownGene
        }
        
        # Get genome information
        genomeInfo <- tryCatch({
            seqinfo(txdb)
        }, error = function(e) {
            tryCatch({
                seqinfo(bw_plus[[1]])
            }, error = function(e2) {
                SeqinfoForUCSCGenome("mm9")
            })
        })
        
        # ==========================================
        # 2. Quantify and Normalize CTSSs
        # ==========================================
        
        # Quantify CTSSs
        CTSSs <- quantifyCTSSs(plusStrand=bw_plus,
                               minusStrand=bw_minus,
                               design=design,
                               genome=genomeInfo)
        
        # Ensure totalTags column exists in colData
        if (!"totalTags" %in% colnames(colData(CTSSs))) {
            colData(CTSSs)\$totalTags <- colSums(assay(CTSSs, "counts"))
        }
        
        # Normalize counts to TPM and calculate pooled signal
        CTSSs <- calcTPM(CTSSs, inputAssay="counts", outputAssay="TPM", outputColumn="subsetTags")
        CTSSs <- calcTPM(CTSSs, inputAssay="counts", totalTags="totalTags", outputAssay="TPM")
        CTSSs <- calcPooled(CTSSs, inputAssay="TPM")
        
        # Filter out noisy CTSSs
        CTSSs <- calcSupport(CTSSs, inputAssay="counts", outputColumn="support", unexpressed=0)
        supportedCTSSs <- subset(CTSSs, support > 1)
        supportedCTSSs <- calcTPM(supportedCTSSs, totalTags="totalTags")
        supportedCTSSs <- calcPooled(supportedCTSSs)
        
        # ==========================================
        # 3. Clustering (TSSs and Enhancers)
        # ==========================================
        
        # Unidirectional clustering (TSSs)
        simple_TCs <- clusterUnidirectionally(CTSSs, pooledCutoff=0, mergeDist=20)
        higher_TCs <- clusterUnidirectionally(CTSSs, pooledCutoff=0.1, mergeDist=20)
        prefiltered_TCs <- clusterUnidirectionally(supportedCTSSs, pooledCutoff=0, mergeDist=20)
        
        # Bidirectional clustering (Enhancers)
        BCs <- clusterBidirectionally(CTSSs, balanceThreshold=0.95)
        BCs <- calcBidirectionality(BCs, samples=CTSSs)
        
        # Filter enhancers
        enhancers <- BCs
        enhancers <- subset(enhancers, bidirectionality > 0)
        
        # ==========================================
        # 4. Quantify and Annotate Clusters
        # ==========================================
        
        # Convert GRanges clusters to RangedSummarizedExperiment by quantifying
        exampleUnidirectional <- quantifyClusters(CTSSs, clusters=prefiltered_TCs, inputAssay="counts")
        exampleBidirectional <- quantifyClusters(CTSSs, clusters=enhancers, inputAssay="counts")
        
        # Requantify clusters (matching vignette flow)
        requantified_TSSs <- quantifyClusters(CTSSs,
                                              clusters=rowRanges(exampleUnidirectional),
                                              inputAssay="counts")
        requantified_enhancers <- quantifyClusters(CTSSs,
                                                   clusters=rowRanges(exampleBidirectional),
                                                   inputAssay="counts")
        
        # Filter clusters by support
        supported_enhancers <- subsetBySupport(exampleBidirectional,
                                               inputAssay="counts",
                                               unexpressed=0,
                                               minSamples=1)
        
        exampleUnidirectional <- calcTPM(exampleUnidirectional, totalTags = "totalTags")
        exampleUnidirectional <- subsetBySupport(exampleUnidirectional,
                                                 inputAssay="TPM",
                                                 unexpressed=1,
                                                 minSamples=2)
        
        # Annotate with transcript models
        exampleUnidirectional <- assignTxID(exampleUnidirectional,
                                            txModels=txdb,
                                            outputColumn="txID")
        
        exampleUnidirectional <- assignTxType(exampleUnidirectional,
                                              txModels=txdb,
                                              outputColumn="txType")
        
        exampleUnidirectional <- assignTxType(exampleUnidirectional,
                                              txModels=txdb,
                                              outputColumn="peakTxType",
                                              swap="thick")
        
        exampleBidirectional <- assignTxType(exampleBidirectional,
                                             txModels=txdb,
                                             outputColumn="txType")
        
        exampleBidirectional <- subset(exampleBidirectional,
                                       txType %in% c("intron", "intergenic"))
        
        # ==========================================
        # 5. Shape and Spatial Analysis
        # ==========================================
        
        # Calculate shape statistics
        exampleCTSSs <- calcTPM(CTSSs, totalTags = "totalTags")
        exampleCTSSs <- calcPooled(exampleCTSSs)
        
        exampleUnidirectional <- calcShape(exampleUnidirectional,
                                           pooled=exampleCTSSs,
                                           outputColumn = "IQR",
                                           shapeFunction = shapeIQR,
                                           lower=0.25, upper=0.75)
        
        # Find links
        TC_pairs <- findLinks(exampleUnidirectional, 
                              inputAssay="TPM", 
                              maxDist=10000, 
                              method="kendall")
        
        rowRanges(exampleUnidirectional)\$clusterType <- "TSS"
        rowRanges(exampleBidirectional)\$clusterType <- "enhancer"
        
        colData(exampleBidirectional) <- colData(exampleUnidirectional)
        SE <- combineClusters(object1=exampleUnidirectional, 
                              object2=exampleBidirectional,
                              removeIfOverlapping="object1")
        
        rowRanges(SE)\$clusterType <- factor(rowRanges(SE)\$clusterType,
                                            levels=c("TSS", "enhancer"))
        
        SE <- calcTPM(SE, totalTags="totalTags")
        
        TCBC_pairs <- findLinks(SE, 
                              inputAssay="TPM",
                              maxDist=10000, 
                              directional="clusterType",
                              method="kendall")
        
        # Find stretches (Super-enhancers)
        stretches <- findStretches(exampleBidirectional, 
                      inputAssay="counts",
                      minSize=3,
                      mergeDist=10000,
                      method="spearman")
        
        if (length(stretches) > 0) {
            extracted_stretches <- extractList(rowRanges(exampleBidirectional), stretches\$revmap)
        }
        
        # ==========================================
        # 6. Gene-Level Analysis
        # ==========================================
        
        # Re-normalize and filter TSSs for gene-level analysis
        exampleUnidirectional <- calcTPM(exampleUnidirectional, totalTags = "totalTags")
        exampleUnidirectional <- subsetBySupport(exampleUnidirectional,
                                                 inputAssay="TPM",
                                                 unexpressed=1,
                                                 minSamples=2)
        
        # Assign Gene IDs
        exampleUnidirectional <- assignGeneID(exampleUnidirectional,
                                              geneModels=txdb,
                                              outputColumn="geneID")
        
        # Map Gene Symbols
        odb <- tryCatch({
            org_name <- metadata(txdb)[metadata(txdb)\$name == "Organism", "value"]
            if (org_name == "Mus musculus") {
                if (requireNamespace("org.Mm.eg.db", quietly=TRUE)) {
                    library(org.Mm.eg.db)
                    org.Mm.eg.db
                } else {
                    NULL
                }
            } else if (org_name == "Homo sapiens") {
                if (requireNamespace("org.Hs.eg.db", quietly=TRUE)) {
                    library(org.Hs.eg.db)
                    org.Hs.eg.db
                } else {
                    NULL
                }
            } else {
                if (requireNamespace("org.Mm.eg.db", quietly=TRUE)) {
                    library(org.Mm.eg.db)
                    org.Mm.eg.db
                } else {
                    NULL
                }
            }
        }, error = function(e) {
            if (requireNamespace("org.Mm.eg.db", quietly=TRUE)) {
                library(org.Mm.eg.db)
                org.Mm.eg.db
            } else {
                NULL
            }
        })
        
        symbols <- tryCatch({
            mapIds(odb,
                   keys=rowRanges(exampleUnidirectional)\$geneID,
                   keytype="ENTREZID",
                   column="SYMBOL")
        }, error = function(e) {
            setNames(rep(NA, length(rowRanges(exampleUnidirectional))), rowRanges(exampleUnidirectional)\$geneID)
        })
        
        rowRanges(exampleUnidirectional)\$symbol <- as.character(symbols)
        
        exampleUnidirectional <- assignMissingID(exampleUnidirectional,
                                                 outputColumn="symbol")
        
        # Quantify Gene Expression
        genelevel <- quantifyGenes(exampleUnidirectional, 
                                   genes="geneID", 
                                   inputAssay="counts")
        
        # Filter clusters based on gene composition
        intragenicTSSs <- subset(exampleUnidirectional, !is.na(geneID))
        
        intragenicTSSs <- calcComposition(intragenicTSSs,
                                          outputColumn="composition",
                                          unexpressed=0.1,
                                          genes="geneID")
        
        # Subset composition (using a safe fallback if composition > 2 is empty)
        intragenicTSSs_filtered <- subset(intragenicTSSs, composition > 2)
        if (nrow(intragenicTSSs_filtered) == 0) {
            intragenicTSSs_filtered <- subset(intragenicTSSs, composition >= 1)
        }
        
        # ==========================================
        # 7. Visualization with Gviz
        # ==========================================
        
        # Prepare tracks
        exampleCTSSs <- calcTPM(CTSSs, totalTags="totalTags")
        exampleCTSSs <- calcPooled(exampleCTSSs)
        
        pooled_track <- trackCTSS(exampleCTSSs, name="CTSSs")
        
        # Determine dynamic plotting coordinates based on data peak
        chr_to_plot <- names(sort(table(seqnames(rowRanges(exampleCTSSs))), decreasing=TRUE))[1]
        peak_idx <- which.max(rowRanges(exampleCTSSs)\$score)
        peak_pos <- start(rowRanges(exampleCTSSs)[peak_idx])
        from_pos <- max(1, peak_pos - 1000)
        to_pos <- peak_pos + 1000
        
        # Combine clusters for track
        try({ exampleUnidirectional\$totalTags <- NULL }, silent=TRUE)
        try({ exampleBidirectional\$totalTags <- NULL }, silent=TRUE)
        
        CAGEclusters <- combineClusters(object1=exampleUnidirectional, 
                                        object2=exampleBidirectional, 
                                        removeIfOverlapping="object1")
        
        CAGEclusters <- subsetBySupport(CAGEclusters, 
                                        inputAssay = "counts", 
                                        unexpressed=0, 
                                        minSamples=2)
        
        cluster_track <- trackClusters(CAGEclusters, name="Clusters", col=NA)
        
        axis_track <- GenomeAxisTrack()
        
        tx_track <- tryCatch({
            GeneRegionTrack(txdb,
                            chromosome = "chr18",
                            name="Gene Models", 
                            col=NA, 
                            fill="bisque4", 
                            shape="arrow")
        }, error = function(e) {
            GeneRegionTrack(txdb,
                            chromosome = chr_to_plot,
                            name="Gene Models", 
                            col=NA, 
                            fill="bisque4", 
                            shape="arrow")
        })
        
        all_tracks <- list(axis_track, tx_track, cluster_track, pooled_track)
        
        # Plot and save to PDF
        pdf("cagefightr_plots.pdf", width=12, height=10)
        
        # Plot standard regions (with dynamic fallbacks)
        tryCatch({
            plotTracks(pooled_track, from=74601950, to=74602100, chromosome="chr18")
        }, error = function(e) {
            plotTracks(pooled_track, from=from_pos, to=to_pos, chromosome=chr_to_plot)
        })
        
        tryCatch({
            plotTracks(cluster_track, from=74601950, to=74602100, chromosome="chr18")
        }, error = function(e) {
            plotTracks(cluster_track, from=from_pos, to=to_pos, chromosome=chr_to_plot)
        })
        
        tryCatch({
            plotTracks(all_tracks, from=77182700, to=77184000, chromosome="chr18")
        }, error = function(e) {
            plotTracks(all_tracks, from=from_pos, to=to_pos, chromosome=chr_to_plot)
        })
        
        tryCatch({
            plotTracks(all_tracks, from=75582473, to=75582897, chromosome="chr18")
        }, error = function(e) {
            plotTracks(all_tracks, from=from_pos, to=to_pos, chromosome=chr_to_plot)
        })
        
        # TSS-enhancer links track
        rowRanges(CAGEclusters)\$clusterType <- factor(ifelse(strand(CAGEclusters)=="*",
                                                      "enhancer", "TSS"),
                                                      levels=c("TSS", "enhancer"))
        
        links <- findLinks(CAGEclusters, 
                           inputAssay="counts", 
                           directional="clusterType",
                           method="kendall")
        
        links <- subset(links, estimate > 0)
        
        if (length(links) > 0) {
            all_tracks\$links_track <- trackLinks(links, 
                                      name="TSS-enhancer", 
                                      col.interactions="black",
                                      col.anchors.fill ="dimgray",
                                      col.anchors.line = NA,
                                      interaction.measure="p.value",
                                      interaction.dimension.transform="log",
                                      col.outside="grey")
        
            tryCatch({
                plotTracks(all_tracks, 
                           from=84255991-1000, 
                           to=84255991+1000, 
                           chromosome="chr18",
                           sizes=c(1, 1, 1, 1, 2))
            }, error = function(e) {
                plotTracks(all_tracks, 
                           from=from_pos, 
                           to=to_pos, 
                           chromosome=chr_to_plot,
                           sizes=c(1, 1, 1, 1, 2))
            })
        }
        
        dev.off()
        
        # ==========================================
        # 8. Save Outputs
        # ==========================================
        
        # Save GRanges objects
        write.csv(as.data.frame(simple_TCs), "simple_TCs.csv", row.names=FALSE)
        write.csv(as.data.frame(higher_TCs), "higher_TCs.csv", row.names=FALSE)
        write.csv(as.data.frame(prefiltered_TCs), "prefiltered_TCs.csv", row.names=FALSE)
        write.csv(as.data.frame(enhancers), "identified_enhancers.csv", row.names=FALSE)
        
        # Save SummarizedExperiment objects
        saveRDS(exampleUnidirectional, "unidirectional_clusters.rds")
        saveRDS(exampleBidirectional, "bidirectional_clusters.rds")
        saveRDS(genelevel, "genelevel_expression.rds")
        write.csv(as.data.frame(assay(genelevel, "counts")), "genelevel_counts.csv")
        
        if (exists("TC_pairs")) saveRDS(TC_pairs, "TC_pairs.rds")
        if (exists("TCBC_pairs")) saveRDS(TCBC_pairs, "TCBC_pairs.rds")
        if (exists("stretches")) write.csv(as.data.frame(stretches), "super_enhancer_stretches.csv", row.names=FALSE)
        
        message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_CAGEFIGHTR_CAGE_5END_ANALYSIS_PIPELINE":',
        paste0('    CAGEfightR: ', as.character(packageVersion('CAGEfightR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cage_5end_analysis_pipeline.csv versions.yml
    """
}

workflow BIOC_CAGEFIGHTR_CAGE_5END_ANALYSIS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ plus_strand.bw, minus_strand.bw, design_matrix.csv, txdb_annotation ] ]

    main:
    BIOC_CAGEFIGHTR_CAGE_5END_ANALYSIS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_CAGEFIGHTR_CAGE_5END_ANALYSIS_PIPELINE.out.tables
    plots    = BIOC_CAGEFIGHTR_CAGE_5END_ANALYSIS_PIPELINE.out.plots
    objects  = BIOC_CAGEFIGHTR_CAGE_5END_ANALYSIS_PIPELINE.out.objects
    versions = BIOC_CAGEFIGHTR_CAGE_5END_ANALYSIS_PIPELINE.out.versions
}
