#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GenomicAlignments — splice_junction_overlap_encoding
// Analyze aligned reads to determine their compatibility with known transcript splice junctions and identify skipped exons.
// Input: untreated3_chr4, TxDb.Dmelanogaster.UCSC.dm3.ensGene
// Container: quay.io/biocontainers/bioconductor-genomicalignments:1.46.0--r45h01b2380_0
// R packages: GenomicAlignments, TxDb.Dmelanogaster.UCSC.dm3.ensGene
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicAlignments, TxDb.Dmelanogaster.UCSC.dm3.ensGene
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load paired-end alignments from a BAM file using
//  * 2. [Input & Preparation] Filter for proper alignment pairs using isProperPair
//  * 3. [Input & Preparation] Extract exons grouped by transcript from the transcript
//  * 4. [Input & Preparation] Find overlaps between alignments and transcripts using
//  * 5. [Input & Preparation] Generate overlap encodings using encodeOverlaps
//  * 6. [Input & Preparation] Identify and extract splice-compatible overlaps

nextflow.enable.dsl = 2

process BIOC_GENOMICALIGNMENTS_SPLICE_JUNCTION_OVERLAP_ENCODING {
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
    .bm_deps <- c("GenomicAlignments", "TxDb.Dmelanogaster.UCSC.dm3.ensGene")
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
    library(GenomicAlignments)
    library(TxDb.Dmelanogaster.UCSC.dm3.ensGene)
    
    # Define input files (expected in the working directory)
    bam_file <- "untreated3_chr4.bam"
    
    # --- Load paired-end alignments from a BAM file using ---
    flag0 <- scanBamFlag(isDuplicate=FALSE, isNotPassingQualityControls=FALSE)
    param0 <- ScanBamParam(flag=flag0)
    U3.galp <- readGAlignmentPairs(bam_file, use.names=TRUE, param=param0)
    
    # --- Filter for proper alignment pairs using isProperPair ---
    U3.GALP <- U3.galp[isProperPair(U3.galp)]
    
    # --- Extract exons grouped by transcript from the transcript ---
    txdb <- TxDb.Dmelanogaster.UCSC.dm3.ensGene
    exbytx <- exonsBy(txdb, by="tx", use.names=TRUE)
    
    # --- Find overlaps between alignments and transcripts using ---
    U3.OV00 <- findOverlaps(U3.GALP, exbytx, ignore.strand=TRUE)
    
    # --- Generate overlap encodings using encodeOverlaps ---
    U3.grl <- grglist(U3.GALP)
    U3.ovenc <- encodeOverlaps(U3.grl, exbytx, hits=U3.OV00, flip.query.if.wrong.strand=TRUE)
    
    # --- Identify and extract splice-compatible overlaps ---
    U3.unique_encodings <- levels(U3.ovenc)
    U3.ovenc_table <- table(encoding(U3.ovenc))
    compatible_encodings <- sort(U3.ovenc_table[isCompatibleWithSplicing(U3.unique_encodings)])
    
    U3.OV00_is_comp <- isCompatibleWithSplicing(U3.ovenc)
    U3.compOV00 <- U3.OV00[U3.OV00_is_comp]
    
    # Write outputs to the working directory
    write.csv(as.data.frame(U3.ovenc_table), "all_overlap_encodings.csv", row.names=FALSE)
    write.csv(as.data.frame(compatible_encodings), "compatible_splicing_encodings.csv", row.names=FALSE)
    saveRDS(U3.compOV00, "compatible_overlaps.rds")
    saveRDS(U3.ovenc, "overlap_encodings.rds")
    
    # Generate a PDF plot of the compatible splicing encodings
    pdf("compatible_splicing_encodings_plot.pdf", width=10, height=6)
    par(mar=c(5, 12, 4, 2))
    barplot(compatible_encodings, las=2, horiz=TRUE, 
            main="Compatible Splicing Encodings Count",
            xlab="Count", col="skyblue")
    dev.off()

    writeLines(c(
        '"BIOC_GENOMICALIGNMENTS_SPLICE_JUNCTION_OVERLAP_ENCODING":',
        paste0('    GenomicAlignments: ', as.character(packageVersion('GenomicAlignments')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_splice_junction_overlap_encoding.csv versions.yml
    """
}

workflow BIOC_GENOMICALIGNMENTS_SPLICE_JUNCTION_OVERLAP_ENCODING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ untreated3_chr4, TxDb.Dmelanogaster.UCSC.dm3.ensGene ] ]

    main:
    BIOC_GENOMICALIGNMENTS_SPLICE_JUNCTION_OVERLAP_ENCODING(ch_input)

    emit:
    tables   = BIOC_GENOMICALIGNMENTS_SPLICE_JUNCTION_OVERLAP_ENCODING.out.tables
    plots    = BIOC_GENOMICALIGNMENTS_SPLICE_JUNCTION_OVERLAP_ENCODING.out.plots
    objects  = BIOC_GENOMICALIGNMENTS_SPLICE_JUNCTION_OVERLAP_ENCODING.out.objects
    versions = BIOC_GENOMICALIGNMENTS_SPLICE_JUNCTION_OVERLAP_ENCODING.out.versions
}
