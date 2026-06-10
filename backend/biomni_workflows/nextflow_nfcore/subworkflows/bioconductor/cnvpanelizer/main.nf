#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cnvpanelizer — cnv_detection_from_bam_and_bed
// Perform gene-level CNV detection and reliability estimation from raw BAM files and an amplicon BED file using non-matched reference samples.
// Input: someFile.bed, sampleDirectory/*.bam, referenceDirectory/*.bam
// Container: quay.io/biocontainers/bioconductor-cnvpanelizer:1.42.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CNVPANELIZER_CNV_DETECTION_FROM_BAM_AND_BED {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-cnvpanelizer:1.42.0--r45hdfd78af_0"

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
    .bm_deps <- c("GenomicRanges", "cnvpanelizer")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(CNVPanelizer)
    library(GenomicRanges)
    
    # Define input paths as specified by user
    bedFilepath <- "someFile.bed"
    sampleDirectory <- "sampleDirectory"
    referenceDirectory <- "referenceDirectory"
    
    # Check if inputs exist
    if (!file.exists(bedFilepath)) {
      stop(paste("Error: BED file not found at", bedFilepath))
    }
    if (!dir.exists(sampleDirectory)) {
      stop(paste("Error: Sample directory not found at", sampleDirectory))
    }
    if (!dir.exists(referenceDirectory)) {
      stop(paste("Error: Reference directory not found at", referenceDirectory))
    }
    
    # Define parameters
    amplColumnNumber <- 4
    removePcrDuplicates <- FALSE
    replicates <- 10000
    
    # 1. Extract genomic ranges and metadata from the BED file
    genomicRangesFromBed <- BedToGenomicRanges(bedFilepath,
                                               ampliconColumn = amplColumnNumber,
                                               split = "_")
    
    metadataFromGenomicRanges <- elementMetadata(genomicRangesFromBed)
    geneNames = metadataFromGenomicRanges["geneNames"][, 1]
    ampliconNames = metadataFromGenomicRanges["ampliconNames"][, 1]
    
    # 2. Identify test and reference BAM files
    sampleFilenames <- list.files(path = sampleDirectory,
                                  pattern = ".bam\$",
                                  full.names = TRUE)
    
    referenceFilenames <- list.files(path = referenceDirectory,
                                     pattern = ".bam\$",
                                     full.names = TRUE)
    
    if (length(sampleFilenames) == 0) {
      stop("Error: No BAM files found in sampleDirectory.")
    }
    if (length(referenceFilenames) == 0) {
      stop("Error: No BAM files found in referenceDirectory.")
    }
    
    # 3. Count reads overlapping amplicons from BAM files
    referenceReadCounts <- ReadCountsFromBam(referenceFilenames,
                                             genomicRangesFromBed,
                                             sampleNames = referenceFilenames,
                                             ampliconNames = ampliconNames,
                                             removeDup = removePcrDuplicates)
    
    sampleReadCounts <- ReadCountsFromBam(sampleFilenames,
                                          genomicRangesFromBed,
                                          sampleNames = sampleFilenames,
                                          ampliconNames = ampliconNames,
                                          removeDup = removePcrDuplicates)
    
    # 4. Normalize read counts using TMM normalization
    normalizedReadCounts <- CombinedNormalizedCounts(sampleReadCounts,
                                                     referenceReadCounts,
                                                     ampliconNames = ampliconNames)
    
    # After normalization data sets need to be splitted again to perform bootstrap
    samplesNormalizedReadCounts = normalizedReadCounts["samples"][[1]]
    referenceNormalizedReadCounts = normalizedReadCounts["reference"][[1]]
    
    # 5. Perform bootstrap-based subsampling analysis
    bootList <- BootList(geneNames,
                         samplesNormalizedReadCounts,
                         referenceNormalizedReadCounts,
                         replicates = replicates)
    
    # 6. Estimate background noise to handle low-amplicon gene bias
    backgroundNoise <- Background(geneNames,
                                  samplesNormalizedReadCounts,
                                  referenceNormalizedReadCounts,
                                  bootList,
                                  replicates = replicates,
                                  significanceLevel = 0.1,
                                  robust = TRUE)
    
    # 7. Generate genewise report tables
    reportTables <- ReportTables(geneNames,
                                 samplesNormalizedReadCounts,
                                 referenceNormalizedReadCounts,
                                 bootList,
                                 backgroundNoise)
    
    # Create output directory
    outputDir <- "cnv_output"
    if (!dir.exists(outputDir)) {
      dir.create(outputDir, recursive = TRUE)
    }
    
    # Save RDS objects for downstream analysis
    saveRDS(bootList, file = file.path(outputDir, "bootList.rds"))
    saveRDS(backgroundNoise, file = file.path(outputDir, "backgroundNoise.rds"))
    saveRDS(reportTables, file = file.path(outputDir, "reportTables.rds"))
    
    # Save report tables as CSV files
    for (sampleName in names(reportTables)) {
      cleanName <- gsub("[^[:alnum:]_.-]", "_", basename(sampleName))
      csvPath <- file.path(outputDir, paste0("report_", cleanName, ".csv"))
      write.csv(reportTables[[sampleName]], file = csvPath, row.names = TRUE)
    }
    
    # 8. Plot bootstrap distributions for visual inspection
    pdfPath <- file.path(outputDir, "bootstrap_distributions.pdf")
    pdf(pdfPath, width = 11, height = 8.5)
    plots <- PlotBootstrapDistributions(bootList, reportTables)
    if (is.list(plots)) {
      for (p in plots) {
        if (inherits(p, "ggplot") || inherits(p, "grob") || inherits(p, "ggplot_grob")) {
          print(p)
        }
      }
    } else {
      print(plots)
    }
    dev.off()
    
    cat("CNV detection pipeline completed successfully. Outputs saved to:", outputDir, "\n")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CNVPANELIZER_CNV_DETECTION_FROM_BAM_AND_BED":
        cnvpanelizer: \$(Rscript -e 'cat(as.character(packageVersion("cnvpanelizer")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cnv_detection_from_bam_and_bed.csv versions.yml
    """
}

workflow BIOC_CNVPANELIZER_CNV_DETECTION_FROM_BAM_AND_BED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ someFile.bed, sampleDirectory/*.bam, referenceDirectory/*.bam ] ]

    main:
    BIOC_CNVPANELIZER_CNV_DETECTION_FROM_BAM_AND_BED(ch_input)

    emit:
    tables   = BIOC_CNVPANELIZER_CNV_DETECTION_FROM_BAM_AND_BED.out.tables
    plots    = BIOC_CNVPANELIZER_CNV_DETECTION_FROM_BAM_AND_BED.out.plots
    objects  = BIOC_CNVPANELIZER_CNV_DETECTION_FROM_BAM_AND_BED.out.objects
    versions = BIOC_CNVPANELIZER_CNV_DETECTION_FROM_BAM_AND_BED.out.versions
}
