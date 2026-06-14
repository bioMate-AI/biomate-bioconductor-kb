#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scmeth — step_by_step_qc_analysis
// Perform individual quality control checks and generate diagnostic metrics for methylation data.
// Input: directory, methylationBiasFile
// Container: quay.io/biocontainers/bioconductor-scmeth:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.NCBI.GRCh38, BSgenome.Mmusculus.UCSC.mm10, HDF5Array, ggplot2, scmeth
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the bsseq object
//  * 2. [Core Analysis] Calculate basic CpG coverage per sample
//  * 3. [Visualization & Output] Visualize read mapping metrics
//  * 4. [Core Analysis] Assess CpG coverage in non-repeat regions
//  * 5. [Core Analysis] Calculate CpG coverage by chromosome
//  * 6. [Core Analysis] Classify CpG coverage by genomic features
//  * 7. [Core Analysis] Calculate CpG density across genomic windows
//  * 8. [Core Analysis] Perform downsampling analysis to assess sequencing saturation
//  * 9. [Visualization & Output] Generate and plot methylation bias along reads
//  * 10. [Core Analysis] Calculate methylation distribution across cells
//  * 11. [Visualization & Output] Calculate and plot bisulfite conversion rates

nextflow.enable.dsl = 2

process BIOC_SCMETH_STEP_BY_STEP_QC_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("scmeth", "HDF5Array", "BSgenome.Mmusculus.UCSC.mm10", "BSgenome.Hsapiens.NCBI.GRCh38", "ggplot2")
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
    library(scmeth)
    library(HDF5Array)
    library(BSgenome.Mmusculus.UCSC.mm10)
    library(BSgenome.Hsapiens.NCBI.GRCh38)
    library(ggplot2)
    
    # Define user inputs (must exist in the working directory)
    directory <- "bismark_data"
    methylationBiasFile <- "2017-04-21_HG23KBCXY_2_AGGCAGAA_TATCTC_pe.M-bias.txt"
    
    # 1. Load the bsseq object
    bsObject <- HDF5Array::loadHDF5SummarizedExperiment(directory)
    
    # 2. Calculate basic CpG coverage per sample
    cov_res <- scmeth::coverage(bsObject)
    write.csv(as.data.frame(cov_res), "coverage_metrics.csv", row.names = TRUE)
    
    # 3. Visualize read mapping metrics
    read_met <- readmetrics(bsObject)
    write.csv(as.data.frame(read_met), "read_metrics.csv", row.names = FALSE)
    
    # 4. Assess CpG coverage in non-repeat regions
    bs <- bsObject
    rep_res <- repMask(bs, Hsapiens, "hg38")
    write.csv(as.data.frame(rep_res), "repmask_metrics.csv", row.names = TRUE)
    
    # 5. Calculate CpG coverage by chromosome
    chrom_cov <- chromosomeCoverage(bsObject)
    write.csv(as.data.frame(chrom_cov), "chromosome_coverage.csv", row.names = TRUE)
    
    # 6. Classify CpG coverage by genomic features
    featureList <- c('cpg_islands', 'cpg_shores', 'cpg_shelves')
    feat_cov <- featureCoverage(bsObject, features=featureList, "hg38")
    write.csv(as.data.frame(feat_cov), "feature_coverage.csv", row.names = TRUE)
    
    # 7. Calculate CpG density across genomic windows
    cpg_dens <- cpgDensity(bsObject, Hsapiens, windowLength=1000, small=TRUE)
    write.csv(as.data.frame(cpg_dens), "cpg_density.csv", row.names = TRUE)
    
    # 8. Perform downsampling analysis to assess sequencing saturation
    down_res <- scmeth::downsample(bsObject)
    write.csv(as.data.frame(down_res), "downsample_metrics.csv", row.names = TRUE)
    
    # 9. Generate and plot methylation bias along reads
    mbiasList <- mbiasplot(mbiasFiles=methylationBiasFile)
    mbiasDf <- do.call(rbind.data.frame, mbiasList)
    meanTable <- stats::aggregate(methylation ~ position + read, data=mbiasDf, FUN=mean)
    sdTable <- stats::aggregate(methylation ~ position + read, data=mbiasDf, FUN=sd)
    seTable <- stats::aggregate(methylation ~ position + read, data=mbiasDf, FUN=function(x){sd(x)/sqrt(length(x))})
    sum_mt<-data.frame('position'=meanTable\$position,'read'=meanTable\$read,
                           'meth'=meanTable\$methylation, 'sdMeth'=sdTable\$methylation,
                           'seMeth'=seTable\$methylation)
    sum_mt\$upperCI <- sum_mt\$meth + (1.96*sum_mt\$seMeth)
    sum_mt\$lowerCI <- sum_mt\$meth - (1.96*sum_mt\$seMeth)
    sum_mt\$read_rep <- paste(sum_mt\$read, sum_mt\$position, sep="_")
    
    g <- ggplot2::ggplot(sum_mt)
    g <- g + ggplot2::geom_line(ggplot2::aes_string(x='position', y='meth',
                                                    colour='read'))
    g <- g + ggplot2::geom_ribbon(ggplot2::aes_string(ymin = 'lowerCI',
                            ymax = 'upperCI', x='position', fill = 'read'),
                            alpha=0.4)
    g <- g + ggplot2::ylim(0,100) + ggplot2::ggtitle('Mbias Plot')
    g <- g + ggplot2::ylab('methylation')
    
    pdf("mbias_plot.pdf")
    print(g)
    dev.off()
    
    # 10. Calculate methylation distribution across cells
    meth_dist <- methylationDist(bsObject)
    write.csv(as.data.frame(meth_dist), "methylation_dist.csv", row.names = TRUE)
    
    # 11. Calculate and plot bisulfite conversion rates
    bs_conv <- bsConversionPlot(bsObject)
    write.csv(as.data.frame(bs_conv), "bs_conversion.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_SCMETH_STEP_BY_STEP_QC_ANALYSIS":',
        paste0('    scmeth: ', as.character(packageVersion('scmeth')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_qc_analysis.csv versions.yml
    """
}

workflow BIOC_SCMETH_STEP_BY_STEP_QC_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ directory, methylationBiasFile ] ]

    main:
    BIOC_SCMETH_STEP_BY_STEP_QC_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCMETH_STEP_BY_STEP_QC_ANALYSIS.out.tables
    plots    = BIOC_SCMETH_STEP_BY_STEP_QC_ANALYSIS.out.plots
    objects  = BIOC_SCMETH_STEP_BY_STEP_QC_ANALYSIS.out.objects
    versions = BIOC_SCMETH_STEP_BY_STEP_QC_ANALYSIS.out.versions
}
