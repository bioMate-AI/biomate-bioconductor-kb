#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CNVrd2 — simple_locus_cnv_and_tagging
// Measure copy number at a simple locus, cluster samples into copy number groups, and identify tagging SNPs/INDELs.
// Input: BamMXL, chr1.161600000.161611000.vcf.gz, sampleCNV
// Container: quay.io/biocontainers/bioconductor-cnvrd2:1.48.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CNVrd2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define region of interest with a CNVrd2 object
//  * 2. [Core Analysis] Count reads in windows with countReadInWindow
//  * 3. [Core Analysis] Segment samples with segmentSamples
//  * 4. [Core Analysis] Cluster segmentation scores into copy number groups with groupCNVs
//  * 5. [Visualization & Output] Plot copy number profiles with plotCNVrd2
//  * 6. [Core Analysis] Identify tag SNPs/INDELs with calculateLDSNPandCNV

nextflow.enable.dsl = 2

process BIOC_CNVRD2_SIMPLE_LOCUS_CNV_AND_TAGGING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    .bm_deps <- c("CNVrd2")
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
    
    # Load required library
    library(CNVrd2)
    
    # -----------------------------------------------------------------------------
    # 1. Input Validation and Reading
    # -----------------------------------------------------------------------------
    
    # Verify BamMXL directory exists
    if (!dir.exists("BamMXL")) {
      stop("Error: Directory 'BamMXL' not found in the working directory.")
    }
    
    # Verify VCF file exists
    vcfFile <- "chr1.161600000.161611000.vcf.gz"
    if (!file.exists(vcfFile)) {
      stop("Error: VCF file 'chr1.161600000.161611000.vcf.gz' not found in the working directory.")
    }
    
    # Read sampleCNV data frame
    if (file.exists("sampleCNV")) {
      sampleCNV <- tryCatch(readRDS("sampleCNV"), error = function(e) {
        tryCatch(read.csv("sampleCNV", header = TRUE, stringsAsFactors = FALSE), error = function(e2) {
          read.table("sampleCNV", header = TRUE, stringsAsFactors = FALSE)
        })
      })
    } else if (file.exists("sampleCNV.csv")) {
      sampleCNV <- read.csv("sampleCNV.csv", header = TRUE, stringsAsFactors = FALSE)
    } else if (file.exists("sampleCNV.rds")) {
      sampleCNV <- readRDS("sampleCNV.rds")
    } else {
      stop("Error: Required input file 'sampleCNV' (or sampleCNV.csv/rds) not found in the working directory.")
    }
    
    # Ensure the first column contains sample names as character strings
    sampleCNV[, 1] <- as.character(sampleCNV[, 1])
    
    # -----------------------------------------------------------------------------
    # 2. CNVrd2 Workflow Execution
    # -----------------------------------------------------------------------------
    
    # Step 1: Define region of interest with a CNVrd2 object
    objectCNVrd2 <- new("CNVrd2", windows = 1000, chr = "chr1",
                        st = 161100001, en = 162100000,
                        dirBamFile = "BamMXL",
                        genes = c(161592986, 161601753),
                        geneNames = "3B")
    
    # Step 2: Count reads in windows
    readCountMatrix <- countReadInWindow(Object = objectCNVrd2, correctGC = TRUE)
    
    # Step 3: Segment samples
    resultSegment <- segmentSamples(Object = objectCNVrd2, stdCntMatrix = readCountMatrix)
    
    # Step 4: Cluster segmentation scores into copy number groups
    objectCluster <- new("clusteringCNVs",
                         x = resultSegment\$segmentationScores[, 1], k = 4, EV = TRUE)
    
    copynumberGroups <- groupCNVs(Object = objectCluster)
    copynumberGroups <- groupCNVs(Object = objectCluster, rightLimit = 1.5)
    
    # Step 5: Plot copy number profiles
    # Identify a sample name to plot (using the first available sample)
    ii <- rownames(resultSegment\$segmentationScores)[1]
    if (is.null(ii) || is.na(ii)) {
      ii <- colnames(readCountMatrix)[1]
    }
    
    pdf("plotCNVrd2_output.pdf", width = 8, height = 6)
    plotCNVrd2(Object = objectCNVrd2, segmentObject = resultSegment, sampleName = ii)
    dev.off()
    
    # Step 6: Identify tag SNPs/INDELs
    tagSNPandINDELofMXL <- calculateLDSNPandCNV(sampleCNV = sampleCNV,
                                                vcfFile = vcfFile, cnvColumn = 2,
                                                population = "MXL", popColumn = 3,
                                                nChunkForVcf = 5, chr = "1",
                                                st = 161600001, en = 161611000,
                                                codeSNP= "Three", codeCNV = "ThreeGroup")
    
    # -----------------------------------------------------------------------------
    # 3. Export Results
    # -----------------------------------------------------------------------------
    
    write.csv(readCountMatrix, "readCountMatrix.csv", row.names = TRUE)
    saveRDS(resultSegment, "resultSegment.rds")
    write.csv(copynumberGroups\$allGroups, "copynumberGroups.csv", row.names = TRUE)
    write.csv(tagSNPandINDELofMXL, "tagSNPandINDELofMXL.csv", row.names = TRUE)
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_CNVRD2_SIMPLE_LOCUS_CNV_AND_TAGGING":',
        paste0('    CNVrd2: ', as.character(packageVersion('CNVrd2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_simple_locus_cnv_and_tagging.csv versions.yml
    """
}

workflow BIOC_CNVRD2_SIMPLE_LOCUS_CNV_AND_TAGGING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ BamMXL, chr1.161600000.161611000.vcf.gz, sampleCNV ] ]

    main:
    BIOC_CNVRD2_SIMPLE_LOCUS_CNV_AND_TAGGING(ch_input)

    emit:
    tables   = BIOC_CNVRD2_SIMPLE_LOCUS_CNV_AND_TAGGING.out.tables
    plots    = BIOC_CNVRD2_SIMPLE_LOCUS_CNV_AND_TAGGING.out.plots
    objects  = BIOC_CNVRD2_SIMPLE_LOCUS_CNV_AND_TAGGING.out.objects
    versions = BIOC_CNVRD2_SIMPLE_LOCUS_CNV_AND_TAGGING.out.versions
}
