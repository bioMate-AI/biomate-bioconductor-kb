#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: QDNAseq — generate_custom_bin_annotations
// Generate custom bin annotations for a reference genome, including GC content, mappability, blacklisted regions, and residuals.
// Input: BSgenome.Hsapiens.UCSC.hg19, /path/to/wgEncodeCrgMapabilityAlign50mer.bigWig, /path/to/bigWigAverageOverBed, /path/to/wgEncodeDacMapabilityConsensusExcludable.bed, /path/to/control-set/bam/files
// Container: quay.io/biocontainers/bioconductor-qdnaseq:1.46.0--r45hdfd78af_0
// R packages: BSgenome.Hsapiens.UCSC.hg19, Biobase, QDNAseq, digest
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg19, Biobase, QDNAseq, digest
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create bins from reference genome
//  * 2. [Core Analysis] Calculate mappability
//  * 3. [Core Analysis] Calculate blacklist overlap
//  * 4. [Core Analysis] Calculate residuals from control dataset
//  * 5. [Input & Preparation] Define default bins to use and convert to AnnotatedDataFrame

nextflow.enable.dsl = 2

process BIOC_QDNASEQ_GENERATE_CUSTOM_BIN_ANNOTATIONS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
        library(QDNAseq)
        library(Biobase)
        library(BSgenome.Hsapiens.UCSC.hg19)
        library(digest)
        
        # Define input file paths (assumed to be in the working directory or specified paths)
        bigWigFile <- "wgEncodeCrgMapabilityAlign50mer.bigWig"
        bigWigAverageOverBed <- "./bigWigAverageOverBed"
        blacklistBed <- "wgEncodeDacMapabilityConsensusExcludable.bed"
        controlBamPath <- "control-set/bam/files"
        
        # Check for required input files and directories to ensure robust execution
        required_files <- c(bigWigFile, bigWigAverageOverBed, blacklistBed)
        missing_files <- required_files[!file.exists(required_files)]
        if (length(missing_files) > 0) {
          stop(paste("Missing required input files:", paste(missing_files, collapse=", "), 
                     "\nPlease ensure these files are in the working directory before running."))
        }
        if (!dir.exists(controlBamPath)) {
          stop(paste("Control BAM directory not found:", controlBamPath, 
                     "\nPlease create this directory and populate it with control BAM files."))
        }
        
        # Ensure the UCSC utility binary is executable
        Sys.chmod(bigWigAverageOverBed, mode = "0755")
        
        # 1. Create bins from the reference genome
        binSize <- 15
        bins <- createBins(bsgenome=BSgenome.Hsapiens.UCSC.hg19, binSize=binSize)
        
        # 2. Calculate mappability
        bins\$mappability <- calculateMappability(bins,
          bigWigFile=bigWigFile,
          bigWigAverageOverBed=bigWigAverageOverBed)
        
        # 3. Calculate blacklist overlap
        bins\$blacklist <- calculateBlacklist(bins,
          bedFiles=c(blacklistBed))
        
        # 4. Calculate residuals from control dataset
        ctrl <- binReadCounts(bins, path=controlBamPath)
        ctrl <- applyFilters(ctrl, residual=FALSE, blacklist=FALSE,
          mappability=FALSE, bases=FALSE)
        bins\$residual <- iterateResiduals(ctrl)
        
        # 5. Define default bins to use and convert to AnnotatedDataFrame
        bins\$use <- bins\$chromosome %in% as.character(1:22) & bins\$bases > 0
        
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
        
        # Add metadata attributes
        attr(bins, "QDNAseq") <- list(
          author="Ilari Scheinin",
          date=Sys.time(),
          organism="Hsapiens",
          build="hg19",
          version=packageVersion("QDNAseq"),
          md5=digest::digest(bins@data),
          sessionInfo=sessionInfo())
        
        # Save the generated custom bin annotations to disk
        saveRDS(bins, "custom_bin_annotations.rds")
        write.table(pData(bins), "custom_bin_annotations.tsv", sep="\t", quote=FALSE, row.names=TRUE)
        
        message("Custom bin annotations successfully generated and saved to 'custom_bin_annotations.rds' and 'custom_bin_annotations.tsv'.")

    writeLines(c(
        '"BIOC_QDNASEQ_GENERATE_CUSTOM_BIN_ANNOTATIONS":',
        paste0('    QDNAseq: ', as.character(packageVersion('QDNAseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_generate_custom_bin_annotations.csv versions.yml
    """
}

workflow BIOC_QDNASEQ_GENERATE_CUSTOM_BIN_ANNOTATIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ BSgenome.Hsapiens.UCSC.hg19, /path/to/wgEncodeCrgMapabilityAlign50mer.bigWig, /path/to/bigWigAverageOverBed, /path/to/wgEncodeDacMapabilityConsensusExcludable.bed, /path/to/control-set/bam/files ] ]

    main:
    BIOC_QDNASEQ_GENERATE_CUSTOM_BIN_ANNOTATIONS(ch_input)

    emit:
    tables   = BIOC_QDNASEQ_GENERATE_CUSTOM_BIN_ANNOTATIONS.out.tables
    plots    = BIOC_QDNASEQ_GENERATE_CUSTOM_BIN_ANNOTATIONS.out.plots
    objects  = BIOC_QDNASEQ_GENERATE_CUSTOM_BIN_ANNOTATIONS.out.objects
    versions = BIOC_QDNASEQ_GENERATE_CUSTOM_BIN_ANNOTATIONS.out.versions
}
