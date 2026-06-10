#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: qdnaseq — generate_bin_annotations
// Generate custom bin annotations for a reference genome, including GC content, mappability, blacklist overlap, and residuals.
// Input: BSgenome.Hsapiens.UCSC.hg19, wgEncodeCrgMapabilityAlign50mer.bigWig, bigWigAverageOverBed, wgEncodeDacMapabilityConsensusExcludable.bed, /path/to/control-set/bam/files
// Container: quay.io/biocontainers/bioconductor-qdnaseq:1.46.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QDNASEQ_GENERATE_BIN_ANNOTATIONS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-qdnaseq:1.46.0--r45hdfd78af_0"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg19", "Biobase", "QDNAseq", "digest")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(QDNAseq)
    library(Biobase)
    library(BSgenome.Hsapiens.UCSC.hg19)
    library(digest)
    
    # Define input file paths in the working directory
    bigWigFile <- "wgEncodeCrgMapabilityAlign50mer.bigWig"
    bigWigAverageOverBed <- "./bigWigAverageOverBed"
    blacklistBed <- "wgEncodeDacMapabilityConsensusExcludable.bed"
    controlBamPath <- "control-set-bams"
    
    # Ensure the UCSC utility binary is executable
    if (file.exists(bigWigAverageOverBed)) {
      Sys.chmod(bigWigAverageOverBed, mode = "0755")
    }
    
    # 1. Create bins from the reference genome
    binSize <- 15
    bins <- createBins(bsgenome=BSgenome.Hsapiens.UCSC.hg19, binSize=binSize)
    
    # 2. Calculate mappability
    bins\$mappability <- calculateMappability(bins,
      bigWigFile=bigWigFile,
      bigWigAverageOverBed=bigWigAverageOverBed)
    
    # 3. Calculate blacklist overlap
    bins\$blacklist <- calculateBlacklist(bins,
      bedFiles=blacklistBed)
    
    # Read the blacklist BED file to perform the generic region overlap calculation
    bed_data <- read.table(blacklistBed, header=FALSE, sep="\t", stringsAsFactors=FALSE)
    chromosome <- as.character(bed_data[[1]])
    bpStart <- as.integer(bed_data[[2]])
    bpEnd <- as.integer(bed_data[[3]])
    
    bins\$blacklist <- calculateBlacklistByRegions(bins, 
      cbind(chromosome, bpStart, bpEnd))
    
    # 4. Calculate residuals from control dataset
    ctrl <- binReadCounts(bins, path=controlBamPath)
    ctrl <- applyFilters(ctrl, residual=FALSE, blacklist=FALSE,
      mappability=FALSE, bases=FALSE)
    bins\$residual <- iterateResiduals(ctrl)
    
    # 5. Define default bins to use
    bins\$use <- bins\$chromosome %in% as.character(1:22) & bins\$bases > 0
    
    # 6. Convert to AnnotatedDataFrame and add metadata
    bins <- AnnotatedDataFrame(bins,
      varMetadata=data.frame(labelDescription=c(
      "Chromosome name",
      "Base pair start position",
      "Base pair end position",
      "Percentage of non-N nucleotides (of full bin size)",
      "Percentage of C and G nucleotides (of non-N nucleotides)",
      "Average mappability of 50mers with a maximum of 2 mismatches",
      "Percent overlap with ENCODE blacklisted regions",
      "Median loess residual from 1000 Genomes (50mers)",
      "Whether the bin should be used in subsequent analysis steps"),
      row.names=colnames(bins)))
    
    attr(bins, "QDNAseq") <- list(
      author="Ilari Scheinin",
      date=Sys.time(),
      organism="Hsapiens",
      build="hg19",
      version=packageVersion("QDNAseq"),
      md5=digest::digest(bins@data),
      sessionInfo=sessionInfo())
    
    # Save the generated bin annotations
    saveRDS(bins, file="bin_annotations_hg19_15kbp.rds")
    write.table(pData(bins), file="bin_annotations_hg19_15kbp.tsv", sep="\t", quote=FALSE, row.names=TRUE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_QDNASEQ_GENERATE_BIN_ANNOTATIONS":
        qdnaseq: \$(Rscript -e 'cat(as.character(packageVersion("qdnaseq")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_generate_bin_annotations.csv versions.yml
    """
}

workflow BIOC_QDNASEQ_GENERATE_BIN_ANNOTATIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ BSgenome.Hsapiens.UCSC.hg19, wgEncodeCrgMapabilityAlign50mer.bigWig, bigWigAverageOverBed, wgEncodeDacMapabilityConsensusExcludable.bed, /path/to/control-set/bam/files ] ]

    main:
    BIOC_QDNASEQ_GENERATE_BIN_ANNOTATIONS(ch_input)

    emit:
    tables   = BIOC_QDNASEQ_GENERATE_BIN_ANNOTATIONS.out.tables
    plots    = BIOC_QDNASEQ_GENERATE_BIN_ANNOTATIONS.out.plots
    objects  = BIOC_QDNASEQ_GENERATE_BIN_ANNOTATIONS.out.objects
    versions = BIOC_QDNASEQ_GENERATE_BIN_ANNOTATIONS.out.versions
}
