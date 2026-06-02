#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DMRcaller
// Uses Bisulfite sequencing data in two conditions and identifies differentially methylated regions be
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DMRcaller/inst/doc/DMRcaller.R
// Upstream  : betareg
// Downstream: none
//
// Install: BiocManager::install("DMRcaller")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DMRCALLER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dmrcaller"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dmrcaller:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dmrcaller:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dmrcaller_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dmrcaller_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dmrcaller_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(GRangesList)
    library(jsonlite)

    # --- save Bismark [] ---
    # Key functions: saveBismark, readBismark, GRangesList
    saveBismark(methylationDataList[["WT"]],
    saveBismark(methylationDataList[["met1-3"]],
    methylationDataWT <- readBismark("chr3test_a_thaliana_wt.CX_report")
    # --- pool Methylation Datasets [] ---
    # Key functions: poolMethylationDatasets, poolTwoMethylationDatasets
    methylationDataAll <- poolMethylationDatasets(methylationDataList)
    methylationDataAll <- poolTwoMethylationDatasets(methylationDataList[[1]],
    # --- read pool data [] ---
    # Key functions: readBismarkPool
    methylationDataAll <- readBismarkPool(c(file_wt, file_met13))
    # --- plot Methylation Profile From Data [] ---
    # Key functions: plotMethylationProfileFromData
    par(mar=c(4, 4, 3, 1)+0.1)
    plotMethylationProfileFromData(methylationDataList[["WT"]],
    conditionsNames = c("WT","met1-3"),
    # --- Create GenomicRanges object [] ---
    # Key functions: GRanges, computeMethylationProfile, GRangesList, plotMethylationProfile
    regions <- GRanges(seqnames = Rle("Chr3"), ranges = IRanges(1,1E6))
    profileCGWT <- computeMethylationProfile(methylationDataList[["WT"]],
    profileCGMet13 <- computeMethylationProfile(methylationDataList[["met1-3"]],
    # --- plot Methylation Data Coverage [] ---
    # Key functions: plotMethylationDataCoverage
    par(mar=c(4, 4, 3, 1)+0.1)
    plotMethylationDataCoverage(methylationDataList[["WT"]],
    breaks = c(1,5,10,15),
    # --- compute Methylation Data Coverage [] ---
    # Key functions: computeMethylationDataCoverage
    coverageCGWT <- computeMethylationDataCoverage(methylationDataList[["WT"]],
    breaks = c(1,5,10,15))
    # --- compute DMRs CG noise filter [] ---
    # Key functions: GRanges, computeDMRs
    chr_local <- GRanges(seqnames = Rle("Chr3"), ranges = IRanges(5E5,6E5))
    DMRsNoiseFilterCG <- computeDMRs(methylationDataList[["WT"]],
    print(DMRsNoiseFilterCG)
    # --- compute DMRs CG neighbourhood [] ---
    # Key functions: computeDMRs
    DMRsNeighbourhoodCG <- computeDMRs(methylationDataList[["WT"]],
    print(DMRsNeighbourhoodCG)
    # --- compute DMRs CG bins [] ---
    # Key functions: computeDMRs
    DMRsBinsCG <- computeDMRs(methylationDataList[["WT"]],
    print(DMRsBinsCG)
    # --- compute DMRs CG GE [] ---
    # Key functions: filterDMRs
    data(GEs)
    genes <- GEs[which(GEs$type == "gene")]
    DMRsGenesCG <- filterDMRs(methylationDataList[["WT"]],
    # --- merge DMRs CG noise filter [] ---
    # Key functions: mergeDMRsIteratively
    DMRsNoiseFilterCGMerged <- mergeDMRsIteratively(DMRsNoiseFilterCG,
    print(DMRsNoiseFilterCGMerged)
    # --- DMR distribution [] ---
    # Key functions: computeOverlapProfile, plotOverlapProfile
    hotspots <- computeOverlapProfile(DMRsNoiseFilterCGMerged, chr_local,
    plotOverlapProfile(GRangesList("Chr3"=hotspots))
    # --- Create GenomicRanges object [] ---
    # Key functions: GRanges, plotLocalMethylationProfile
    chr3Reg <- GRanges(seqnames = Rle("Chr3"), ranges = IRanges(510000,530000))
    DMRsCGList <- list("noise filter" = DMRsNoiseFilterCGMerged,
    par(cex=0.9)
    # --- computing biological replicates [] ---
    # Key functions: computeDMRsReplicates
    library(betareg)
    condition <- c("a", "a", "b", "b")
    DMRsReplicatesBins <- computeDMRsReplicates(methylationData = methylationData,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dmrcaller_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dmrcaller_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dmrcaller_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DMRCALLER:", paste0("    dmrcaller: ", packageVersion("DMRcaller"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dmrcaller_results.csv
    touch ${prefix}_dmrcaller_output.rds
    echo "BIOC_DMRCALLER:" > versions.yml
    echo "    dmrcaller: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DMRCALLER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DMRCALLER(ch_input)

    emit:
    results  = BIOC_DMRCALLER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DMRCALLER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DMRCALLER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DMRCALLER.out.versions  // channel: path(versions.yml)
}
