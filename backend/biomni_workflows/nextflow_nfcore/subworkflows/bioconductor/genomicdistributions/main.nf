#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: genomicdistributions — genomic_range_characterization
// Characterize and visualize basic properties of genomic ranges including chromosome distribution, distance to TSS/features, genomic partitions, neighbor distance
// Input: vistaEnhancers.bed.gz, setB_100.bed.gz
// Container: quay.io/biocontainers/bioconductor-genomicdistributions:1.18.0--r45hdfd78af_0
// R packages: GenomicRanges, GenomicDistributions, ggplot2, rtracklayer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_GENOMICDISTRIBUTIONS_GENOMIC_RANGE_CHARACTERIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-genomicdistributions:1.18.0--r45hdfd78af_0"

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
    .bm_deps <- c("GenomicRanges", "GenomicDistributions", "ggplot2", "rtracklayer")
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
    library("GenomicDistributions")
    library("rtracklayer")
    library("GenomicRanges")
    library("ggplot2")
    
    # --- Load query genomic ranges using rtracklayer::import ---
    queryFile = "vistaEnhancers.bed.gz"
    query = rtracklayer::import(queryFile)
    
    # --- Calculate and plot chromosome distribution using ---
    x = calcChromBinsRef(query, "hg19")
    write.csv(as.data.frame(x), "chrom_bins_single.csv", row.names=FALSE)
    p1 = plotChromBins(x)
    ggsave("chrom_bins_single.pdf", plot=p1, width=8, height=6)
    
    query2 = GenomicRanges::shift(query, 1e6)
    queryList = GRangesList(vistaEnhancers=query, shifted=query2)
    x2 = calcChromBinsRef(queryList, "hg19")
    write.csv(as.data.frame(x2), "chrom_bins_multi.csv", row.names=FALSE)
    p2 = plotChromBins(x2)
    ggsave("chrom_bins_multi.pdf", plot=p2, width=8, height=6)
    
    # --- Calculate and plot distance to TSS or custom features ---
    TSSdist = calcFeatureDistRefTSS(query, "hg19")
    write.csv(as.data.frame(TSSdist), "tss_dist_single.csv", row.names=FALSE)
    p3 = plotFeatureDist(TSSdist, featureName="TSS")
    ggsave("tss_dist_single.pdf", plot=p3, width=8, height=6)
    
    TSSdist2 = calcFeatureDistRefTSS(queryList, "hg19")
    write.csv(as.data.frame(TSSdist2), "tss_dist_multi.csv", row.names=FALSE)
    p4 = plotFeatureDist(TSSdist2, featureName="TSS")
    ggsave("tss_dist_multi.pdf", plot=p4, width=8, height=6)
    
    p5 = plotFeatureDist(TSSdist2, featureName="TSS", tile=TRUE, labelOrder = "center")
    ggsave("tss_dist_multi_tiled.pdf", plot=p5, width=8, height=6)
    
    featureExample = GenomicRanges::shift(query, round(rnorm(length(query), 0, 1000)))
    fdd = calcFeatureDist(query, featureExample)
    write.csv(as.data.frame(fdd), "feature_dist_example.csv", row.names=FALSE)
    p6 = plotFeatureDist(fdd)
    ggsave("feature_dist_example.pdf", plot=p6, width=8, height=6)
    
    # --- Calculate and plot genomic partition distributions ---
    gp = calcPartitionsRef(query, "hg19")
    write.csv(as.data.frame(gp), "partitions_single.csv", row.names=FALSE)
    p7 = plotPartitions(gp)
    ggsave("partitions_single.pdf", plot=p7, width=8, height=6)
    
    gp2 = calcPartitionsRef(queryList, "hg19")
    write.csv(as.data.frame(gp2), "partitions_multi.csv", row.names=FALSE)
    p8 = plotPartitions(gp2)
    ggsave("partitions_multi.pdf", plot=p8, width=8, height=6)
    
    p9 = plotPartitions(gp2, numbers=TRUE)
    ggsave("partitions_multi_numbers.pdf", plot=p9, width=8, height=6)
    
    gp3 = calcPartitionsRef(queryList, "hg19", bpProportion=TRUE)
    write.csv(as.data.frame(gp3), "partitions_multi_bp.csv", row.names=FALSE)
    p10 = plotPartitions(gp3)
    ggsave("partitions_multi_bp.pdf", plot=p10, width=8, height=6)
    
    ep = calcExpectedPartitionsRef(query, "hg19")
    write.csv(as.data.frame(ep), "expected_partitions_single.csv", row.names=FALSE)
    p11 = plotExpectedPartitions(ep)
    ggsave("expected_partitions_single.pdf", plot=p11, width=8, height=6)
    
    ep2 = calcExpectedPartitionsRef(queryList, "hg19")
    write.csv(as.data.frame(ep2), "expected_partitions_multi.csv", row.names=FALSE)
    p12 = plotExpectedPartitions(ep2)
    ggsave("expected_partitions_multi.pdf", plot=p12, width=8, height=6)
    
    p13 = plotExpectedPartitions(ep2, pval=TRUE)
    ggsave("expected_partitions_multi_pval.pdf", plot=p13, width=8, height=6)
    
    ep3 = calcExpectedPartitionsRef(queryList, "hg19", bpProportion=TRUE)
    write.csv(as.data.frame(ep3), "expected_partitions_multi_bp.csv", row.names=FALSE)
    p14 = plotExpectedPartitions(ep3)
    ggsave("expected_partitions_multi_bp.pdf", plot=p14, width=8, height=6)
    
    cp = calcCumulativePartitionsRef(query, "hg19")
    write.csv(as.data.frame(cp), "cumulative_partitions_single.csv", row.names=FALSE)
    p15 = plotCumulativePartitions(cp)
    ggsave("cumulative_partitions_single.pdf", plot=p15, width=8, height=6)
    
    cp2 = calcCumulativePartitionsRef(queryList, "hg19")
    write.csv(as.data.frame(cp2), "cumulative_partitions_multi.csv", row.names=FALSE)
    p16 = plotCumulativePartitions(cp2)
    ggsave("cumulative_partitions_multi.pdf", plot=p16, width=8, height=6)
    
    # --- Calculate and plot neighboring region distances ---
    nd = calcNeighborDist(query)
    write.csv(as.data.frame(nd), "neighbor_dist_single.csv", row.names=FALSE)
    p17 = plotNeighborDist(nd)
    ggsave("neighbor_dist_single.pdf", plot=p17, width=8, height=6)
    
    s = "setB_100.bed.gz"
    setB = rtracklayer::import(s)
    queryList2 = GRangesList(vistaEnhancers=query, setB=setB)
    dist2 = calcNeighborDist(queryList2)
    write.csv(as.data.frame(dist2), "neighbor_dist_multi.csv", row.names=FALSE)
    p18 = plotNeighborDist(dist2)
    ggsave("neighbor_dist_multi.pdf", plot=p18, width=8, height=6)
    
    # --- Calculate and plot GC content and dinucleotide ---
    tryCatch({
      gc1 = calcGCContentRef(query, "hg19")
      write.csv(as.data.frame(gc1), "gc_content_single.csv", row.names=FALSE)
      p19 = plotGCContent(gc1)
      ggsave("gc_content_single.pdf", plot=p19, width=8, height=6)
      
      gc2 = calcGCContentRef(queryList, "hg19")
      write.csv(as.data.frame(gc2), "gc_content_multi.csv", row.names=FALSE)
      p20 = plotGCContent(gc2)
      ggsave("gc_content_multi.pdf", plot=p20, width=8, height=6)
    }, error = function(e) {
      message("GC Content calculation skipped or failed (requires BSgenome.Hsapiens.UCSC.hg19): ", e\$message)
    })
    
    tryCatch({
      df1 = calcDinuclFreqRef(query, "hg19")
      write.csv(as.data.frame(df1), "dinucl_freq_single.csv", row.names=FALSE)
      p21 = plotDinuclFreq(df1)
      ggsave("dinucl_freq_single.pdf", plot=p21, width=8, height=6)
      
      df2 = calcDinuclFreqRef(queryList, "hg19")
      write.csv(as.data.frame(df2), "dinucl_freq_multi.csv", row.names=FALSE)
      p22 = plotDinuclFreq(df2)
      ggsave("dinucl_freq_multi.pdf", plot=p22, width=8, height=6)
      
      df3 = calcDinuclFreqRef(queryList, "hg19", rawCounts=TRUE)
      write.csv(as.data.frame(df3), "dinucl_freq_multi_raw.csv", row.names=FALSE)
      p23 = plotDinuclFreq(df3)
      ggsave("dinucl_freq_multi_raw.pdf", plot=p23, width=8, height=6)
    }, error = function(e) {
      message("Dinucleotide frequency calculation skipped or failed (requires BSgenome.Hsapiens.UCSC.hg19): ", e\$message)
    })
    
    # --- Calculate and plot width distributions ---
    qt1 = calcWidth(query)
    write.csv(as.data.frame(qt1), "width_single.csv", row.names=FALSE)
    p24 = plotQTHist(qt1)
    ggsave("width_single.pdf", plot=p24, width=8, height=6)
    
    qt2 = calcWidth(queryList)
    write.csv(as.data.frame(qt2), "width_multi.csv", row.names=FALSE)
    p25 = plotQTHist(qt2)
    ggsave("width_multi.pdf", plot=p25, width=8, height=6)
    
    p26 = plotQTHist(qt1, bins=7, EndBarColor = 'black', MiddleBarColor='darkblue')
    ggsave("width_single_custom.pdf", plot=p26, width=8, height=6)

    writeLines(c(
        '"BIOC_GENOMICDISTRIBUTIONS_GENOMIC_RANGE_CHARACTERIZATION":',
        paste0('        genomicdistributions: ', as.character(packageVersion("genomicdistributions")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomic_range_characterization.csv versions.yml
    """
}

workflow BIOC_GENOMICDISTRIBUTIONS_GENOMIC_RANGE_CHARACTERIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ vistaEnhancers.bed.gz, setB_100.bed.gz ] ]

    main:
    BIOC_GENOMICDISTRIBUTIONS_GENOMIC_RANGE_CHARACTERIZATION(ch_input)

    emit:
    tables   = BIOC_GENOMICDISTRIBUTIONS_GENOMIC_RANGE_CHARACTERIZATION.out.tables
    plots    = BIOC_GENOMICDISTRIBUTIONS_GENOMIC_RANGE_CHARACTERIZATION.out.plots
    objects  = BIOC_GENOMICDISTRIBUTIONS_GENOMIC_RANGE_CHARACTERIZATION.out.objects
    versions = BIOC_GENOMICDISTRIBUTIONS_GENOMIC_RANGE_CHARACTERIZATION.out.versions
}
