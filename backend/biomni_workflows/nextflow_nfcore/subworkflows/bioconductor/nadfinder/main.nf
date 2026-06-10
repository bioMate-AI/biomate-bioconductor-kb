#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: nadfinder — single_pair_nad_seq
// Identify nucleolar-associated domains (NADs) from a single pair of nucleolus-associated DNA and genomic DNA sequencing samples.
// Input: nucleolus.bam, genomic.bam
// Container: quay.io/biocontainers/bioconductor-nadfinder:1.34.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NADFINDER_SINGLE_PAIR_NAD_SEQ {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-nadfinder:1.34.0--r45hdfd78af_0"

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
    .bm_deps <- c("BSgenome.Mmusculus.UCSC.mm10", "GenomicAlignments", "Rsamtools", "nadfinder", "rtracklayer", "summarizedexperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(NADfinder)
    library(SummarizedExperiment)
    library(BSgenome.Mmusculus.UCSC.mm10)
    library(GenomicAlignments)
    library(Rsamtools)
    
    # Define input files in the working directory
    nucleolus_bam <- "nucleolus.bam"
    genomic_bam <- "genomic.bam"
    
    # Ensure BAM files are indexed
    for (bf in c(nucleolus_bam, genomic_bam)) {
      if (!file.exists(paste0(bf, ".bai"))) {
        message("Indexing ", bf, "...")
        indexBam(bf)
      }
    }
    
    # Set parameters
    path <- "."
    bamFiles <- c(nucleolus_bam, genomic_bam)
    ws <- 50000
    step <- 5000
    backgroundPercentage <- 0.25
    
    # 1. Calculate read coverage in sliding windows using tileCount
    se <- tileCount(reads=file.path(path, bamFiles), 
                    genome=Mmusculus, 
                    windowSize=ws, 
                    step=step, 
                    mode = IntersectionNotStrict, 
                    dataOverSamples = FALSE)
    
    # 2. Compute log2 ratios of nucleolus vs genomic DNA using log2se
    # Dynamically retrieve column names to avoid path mismatch issues
    nucleolus_col <- colnames(se)[1]
    genomic_col <- colnames(se)[2]
    
    dat <- log2se(se, 
                  nucleolusCols = nucleolus_col, 
                  genomeCols = genomic_col, 
                  transformation = "log2CPMRatio")
    
    # 3. Smooth ratios per chromosome using smoothRatiosByChromosome
    # Ensure we only use chromosomes present in the dataset
    target_chrs <- intersect(c("chr18", "chr19"), seqlevels(se))
    if (length(target_chrs) == 0) {
      target_chrs <- seqlevels(se)[1]
    }
    
    datList <- smoothRatiosByChromosome(dat, chr = target_chrs, N = 100)
    
    # 4. Assess quality using cumulativePercentage
    pdf("cumulative_percentage.pdf")
    cumulativePercentage(datList[[target_chrs[1]]])
    dev.off()
    
    # 5. Call and trim peaks using trimPeaks
    peaks <- lapply(datList, 
                    trimPeaks, 
                    backgroundPercentage=backgroundPercentage, 
                    cutoffAdjPvalue=0.05, 
                    countFilter=1000)
    
    # 6. Export peaks to CSV format
    peaks.gr <- unlist(GRangesList(peaks))
    write.csv(as.data.frame(unname(peaks.gr)), "peaklist.csv", row.names=FALSE)
    
    # Save RDS of the smoothed ratios for downstream analysis
    saveRDS(datList, "smoothed_ratios.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_NADFINDER_SINGLE_PAIR_NAD_SEQ":
        nadfinder: \$(Rscript -e 'cat(as.character(packageVersion("nadfinder")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_pair_nad_seq.csv versions.yml
    """
}

workflow BIOC_NADFINDER_SINGLE_PAIR_NAD_SEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ nucleolus.bam, genomic.bam ] ]

    main:
    BIOC_NADFINDER_SINGLE_PAIR_NAD_SEQ(ch_input)

    emit:
    tables   = BIOC_NADFINDER_SINGLE_PAIR_NAD_SEQ.out.tables
    plots    = BIOC_NADFINDER_SINGLE_PAIR_NAD_SEQ.out.plots
    objects  = BIOC_NADFINDER_SINGLE_PAIR_NAD_SEQ.out.objects
    versions = BIOC_NADFINDER_SINGLE_PAIR_NAD_SEQ.out.versions
}
