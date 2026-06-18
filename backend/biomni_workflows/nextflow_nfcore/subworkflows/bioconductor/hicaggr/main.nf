#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HicAggR — aggregation_peak_analysis
// Integrate 1D genomic features with 3D HiC data to perform Aggregation Peak Analysis (APA), quantify interaction signals, and visualize differential interaction 
// Input: HicOutput.pth, McoolOutput.pth, Beaf32_Peaks.gnr, TSS_Peaks.gnr, TADs_Domains.gnr
// Container: quay.io/biocontainers/bioconductor-hicaggr:1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, HicAggR, InteractionSet, rtracklayer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import HiC data for both conditions using ImportHiC
//  * 2. [Core Analysis] Perform matrix balancing using BalanceHiC
//  * 3. [Core Analysis] Apply observed/expected distance normalization using OverExpectedHiC
//  * 4. [Core Analysis] Index genomic features under TAD constraints using IndexFeatures
//  * 5. [Core Analysis] Pair anchors and baits within constraints using SearchPairs
//  * 6. [Core Analysis] Extract interaction submatrices using ExtractSubmatrix
//  * 7. [Core Analysis] Filter submatrices based on metadata targets using FilterInteractions
//  * 8. [Core Analysis] Correct matrix orientation using OrientateMatrix
//  * 9. [Input & Preparation] Prepare and transform matrix lists using PrepareMtxList
//  * 10. [Core Analysis] Quantify interaction signals using GetQuantif
//  * 11. [Core Analysis] Perform single or differential aggregation using Aggregation
//  * 12. [Visualization & Output] Plot APA heatmaps using ggAPA

nextflow.enable.dsl = 2

process BIOC_HICAGGR_AGGREGATION_PEAK_ANALYSIS {
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
    .bm_deps <- c("HicAggR", "GenomicRanges", "InteractionSet", "rtracklayer")
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
            library(HicAggR)
            library(GenomicRanges)
            library(InteractionSet)
            library(rtracklayer)
            
            # Define paths to user input files in the working directory
            HicOutput.pth <- "HicOutput.pth"
            McoolOutput.pth <- "McoolOutput.pth"
            
            # Read GRanges objects from the working directory
            Beaf32_Peaks.gnr <- import("Beaf32_Peaks.gnr", format = "bed")
            TSS_Peaks.gnr <- import("TSS_Peaks.gnr", format = "bed")
            TADs_Domains.gnr <- import("TADs_Domains.gnr", format = "bed")
            
            # 1. Import HiC data for both conditions
            seq_names <- as.character(unique(seqnames(TADs_Domains.gnr)))
            chrom_grid <- expand.grid(chrom_1 = seq_names, chrom_2 = seq_names, stringsAsFactors = FALSE)
            chrom_grid <- chrom_grid[chrom_grid\$chrom_1 <= chrom_grid\$chrom_2, ]
            
            HiC_Ctrl.cmx_lst <- ImportHiC(
                    file    = HicOutput.pth,
                    hicResolution     = 5000,
                    chrom_1 = chrom_grid\$chrom_1,
                    chrom_2 = chrom_grid\$chrom_2
            )
            
            HiC_HS.cmx_lst <- ImportHiC(
                    file    = McoolOutput.pth,
                    hicResolution     = 5000,
                    chrom_1 = chrom_grid\$chrom_1,
                    chrom_2 = chrom_grid\$chrom_2
            )
            
            # Define genomic information dynamically from HiC attributes
            chromSizes_attr <- attributes(HiC_Ctrl.cmx_lst)\$chromSize
            chromSizes <- data.frame(
                seqnames   = chromSizes_attr\$name, 
                seqlengths = chromSizes_attr\$length
            )
            binSize <- 5000
            
            # 2. Perform matrix balancing
            HiC_Ctrl.cmx_lst <- BalanceHiC(HiC_Ctrl.cmx_lst)
            HiC_HS.cmx_lst <- BalanceHiC(HiC_HS.cmx_lst)
            
            # 3. Apply observed/expected distance normalization
            HiC_Ctrl.cmx_lst <- OverExpectedHiC(HiC_Ctrl.cmx_lst)
            HiC_HS.cmx_lst <- OverExpectedHiC(HiC_HS.cmx_lst)
            
            # 4. Index genomic features under TAD constraints
            anchors_Index.gnr <- IndexFeatures(
                gRangeList        = list(Beaf=Beaf32_Peaks.gnr), 
                genomicConstraint        = TADs_Domains.gnr,
                chromSizes         = chromSizes,
                binSize           = binSize,
                metadataColName = "score",
                method            = "max"
            )
            
            baits_Index.gnr <- IndexFeatures(
                gRangeList        = list(Tss=TSS_Peaks.gnr),
                genomicConstraint        = TADs_Domains.gnr,
                chromSizes         = chromSizes,
                binSize           = binSize,
                metadataColName = "score",
                method            = "max"
            )
            
            # Filter indexed features to remove overlaps
            non_Overlaps.ndx <- match(baits_Index.gnr\$bin, 
                anchors_Index.gnr\$bin, nomatch=0L)==0L
            baits_Index.gnr <- baits_Index.gnr[non_Overlaps.ndx,]
            
            # 5. Pair anchors and baits within constraints
            interactions.gni <- SearchPairs(
                    indexAnchor = anchors_Index.gnr,
                    indexBait   = baits_Index.gnr
            )
            
            # 6. Extract interaction submatrices (Control)
            interactions_RFmatrix_ctrl.lst  <- ExtractSubmatrix(
                genomicFeature         = interactions.gni,
                hicLst        = HiC_Ctrl.cmx_lst,
                hicResolution            = NULL,
                referencePoint = "rf",
                matriceDim     = 101
            )
            
            # 7. Filter submatrices based on metadata targets
            interactions_attr <- attributes(interactions_RFmatrix_ctrl.lst)\$interactions
            n_int <- length(interactions_attr)
            
            if (n_int > 0) {
                valid_idx <- 1:min(2, n_int)
                exclude_idx <- min(3, n_int)
                
                targets <- list(
                    anchor.Beaf.name = unlist(interactions_attr\$anchor.Beaf.name[valid_idx]),
                    bait.Tss.name    = unlist(interactions_attr\$bait.Tss.name[valid_idx]),
                    name             = interactions_attr\$name[exclude_idx],
                    distance         = function(columnElement){
                        return(columnElement %in% interactions_attr\$distance[valid_idx])
                    }
                )
            } else {
                targets <- list(
                    anchor.Beaf.name = character(0),
                    bait.Tss.name    = character(0),
                    name             = character(0),
                    distance         = function(columnElement) FALSE
                )
            }
            
            selectionFun = function(){
                Reduce(intersect, list(anchor.Beaf.name, bait.Tss.name ,distance) ) |>
                setdiff(name)
            }
            
            filtred_interactions_RFmatrix_ctrl.lst <- FilterInteractions(
                matrices  = interactions_RFmatrix_ctrl.lst,
                targets    = targets,
                selectionFun = selectionFun
            )
            
            # Filter first 100 targets safely
            n_subset <- min(100, length(interactions_RFmatrix_ctrl.lst))
            if (n_subset > 0) {
                first100_targets = list(
                    submatrix.name = names(interactions_RFmatrix_ctrl.lst)[1:n_subset]
                )
            } else {
                first100_targets = list(submatrix.name = character(0))
            }
            
            first100_interactions_RFmatrix_ctrl.lst <- FilterInteractions(
                matrices  = interactions_RFmatrix_ctrl.lst,
                targets    = first100_targets,
                selectionFun = NULL
            )
            
            # 8. Correct matrix orientation
            oriented_first100_interactions_RFmatrix_ctrl.lst <- 
                OrientateMatrix(first100_interactions_RFmatrix_ctrl.lst)
            
            # 9. Prepare and transform matrix lists
            oriented_quantiled_first100_interactions_RFmatrix_ctrl.lst <- 
                PrepareMtxList(
                    first100_interactions_RFmatrix_ctrl.lst,
                    transFun = 'quantile',
                    orientate = TRUE
                )
            
            oriented_first100_interactions_RFmatrix_ctrl.lst <- 
                PrepareMtxList(
                    first100_interactions_RFmatrix_ctrl.lst,
                    orientate = TRUE
                )
            
            # 10. Quantify interaction signals
            center.num <- GetQuantif(
                matrices  = oriented_first100_interactions_RFmatrix_ctrl.lst,
                areaFun      = "center",
                operationFun = "mean"
            )
            
            # 11. Perform single aggregation
            oriented_first100_interactions_RFmatrix_ctrl.lst = 
                PrepareMtxList(
                    oriented_first100_interactions_RFmatrix_ctrl.lst,
                    rm0 = FALSE
                )
            
            agg_sum.mtx <- Aggregation(
                matrices = oriented_first100_interactions_RFmatrix_ctrl.lst, 
                aggFun      = "sum"
            )
            
            # Extract submatrices for Heat Shock condition
            interactions_RFmatrix.lst  <- ExtractSubmatrix(
                genomicFeature         = interactions.gni,
                hicLst        = HiC_HS.cmx_lst,
                referencePoint = "rf",
                matriceDim     = 101
            )
            
            first100_interactions_RFmatrix.lst <- FilterInteractions(
                matrices  = interactions_RFmatrix.lst,
                targets    = first100_targets,
                selectionFun = NULL
            )
            
            oriented_first100_interactions_RFmatrix.lst <- 
                OrientateMatrix(first100_interactions_RFmatrix.lst)
            
            # Prepare matrix lists for differential aggregation
            oriented_first100_interactions_RFmatrix_ctrl.lst = 
                PrepareMtxList(first100_interactions_RFmatrix_ctrl.lst,
                    minDist   = NULL,
                    maxDist   = NULL,
                    rm0       = FALSE,
                    orientate = TRUE
            )
            
            oriented_first100_interactions_RFmatrix.lst = 
                PrepareMtxList(first100_interactions_RFmatrix.lst,
                    minDist   = NULL,
                    maxDist   = NULL,
                    rm0       = FALSE,
                    orientate = TRUE
            )
            
            # Perform differential aggregation
            diffAggreg.mtx <- Aggregation(
                ctrlMatrices    = oriented_first100_interactions_RFmatrix_ctrl.lst,
                matrices        = oriented_first100_interactions_RFmatrix.lst,
                aggFun             = "mean",
                diffFun            = "substraction",
                scaleCorrection = TRUE,
                correctionArea  =  list(
                    i = c(1:30),
                    j = c(72:101)
                ),
                statCompare = TRUE
            )
            
            # 12. Plot APA heatmaps and save to PDF
            pdf("APA_differential_plot.pdf", width = 7, height = 6)
            p <- ggAPA(
                    aggregatedMtx   = diffAggreg.mtx,
                    title = "APA"
            )
            print(p)
            dev.off()
            
            # Save meaningful results to files
            saveRDS(filtred_interactions_RFmatrix_ctrl.lst, "filtred_interactions_RFmatrix_ctrl.rds")
            saveRDS(center.num, "center_quantification.rds")
            saveRDS(agg_sum.mtx, "agg_sum_matrix.rds")
            saveRDS(diffAggreg.mtx, "diff_aggreg_matrix.rds")
            
            write.csv(as.data.frame(center.num), "center_quantification.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_HICAGGR_AGGREGATION_PEAK_ANALYSIS":',
        paste0('    HicAggR: ', as.character(packageVersion('HicAggR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_aggregation_peak_analysis.csv versions.yml
    """
}

workflow BIOC_HICAGGR_AGGREGATION_PEAK_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ HicOutput.pth, McoolOutput.pth, Beaf32_Peaks.gnr, TSS_Peaks.gnr, TADs_Domains.gnr ] ]

    main:
    BIOC_HICAGGR_AGGREGATION_PEAK_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_HICAGGR_AGGREGATION_PEAK_ANALYSIS.out.tables
    plots    = BIOC_HICAGGR_AGGREGATION_PEAK_ANALYSIS.out.plots
    objects  = BIOC_HICAGGR_AGGREGATION_PEAK_ANALYSIS.out.objects
    versions = BIOC_HICAGGR_AGGREGATION_PEAK_ANALYSIS.out.versions
}
