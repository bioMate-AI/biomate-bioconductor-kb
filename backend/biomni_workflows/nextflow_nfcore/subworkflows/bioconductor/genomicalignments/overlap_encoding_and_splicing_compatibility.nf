#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: genomicalignments — overlap_encoding_and_splicing_compatibility
// Analyze the compatibility of aligned reads with transcript structures (splicing junctions, skipped exons) using overlap encodings.
// Input: bamfile, txdb
// Container: quay.io/biocontainers/bioconductor-genomicalignments:1.46.0--r45h01b2380_0
// R packages: AnnotationDbi, GenomicAlignments, GenomicFeatures
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMICALIGNMENTS_OVERLAP_ENCODING_AND_SPLICING_COMPATIBILITY {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-genomicalignments:1.46.0--r45h01b2380_0"

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
    .bm_deps <- c("AnnotationDbi", "GenomicAlignments", "GenomicFeatures")
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
    
    # Check for required packages
    required_packages <- c("GenomicAlignments", "GenomicFeatures", "AnnotationDbi")
    for (pkg in required_packages) {
      if (!requireNamespace(pkg, quietly = TRUE)) {
        stop("Package '", pkg, "' is required but not installed.")
      }
    }
    
    library(GenomicAlignments)
    library(GenomicFeatures)
    library(AnnotationDbi)
    
    # Define input files in the working directory
    bamfile <- "input.bam"
    txdb_file <- "txdb.sqlite"
    
    # Validate input files
    if (!file.exists(bamfile)) {
      stop("Required BAM file '", bamfile, "' not found in the working directory.")
    }
    if (!file.exists(txdb_file)) {
      stop("Required TxDb SQLite file '", txdb_file, "' not found in the working directory.")
    }
    
    # 1. Load aligned reads from BAM file
    message("Loading aligned reads from BAM file...")
    flag0 <- scanBamFlag(isDuplicate=FALSE, isNotPassingQualityControls=FALSE)
    param0 <- ScanBamParam(flag=flag0)
    U1.GAL <- readGAlignments(bamfile, use.names=TRUE, param=param0)
    
    # 2. Extract exons grouped by transcript from the transcript database
    message("Loading transcript database and extracting exons...")
    txdb <- loadDb(txdb_file)
    exbytx <- exonsBy(txdb, by="tx", use.names=TRUE)
    
    # 3. Find overlaps between alignments and transcripts
    message("Finding overlaps...")
    U1.OV00 <- findOverlaps(U1.GAL, exbytx, ignore.strand=TRUE)
    
    # 4. Convert alignments to a GRangesList object
    message("Converting alignments to GRangesList...")
    U1.grl <- grglist(U1.GAL, order.as.in.query=TRUE)
    
    # 5. Encode overlaps and identify splice-compatible alignments
    message("Encoding overlaps and identifying splicing compatibility...")
    U1.ovenc <- encodeOverlaps(U1.grl, exbytx, hits=U1.OV00, flip.query.if.wrong.strand=TRUE)
    U1.OV00_is_comp <- isCompatibleWithSplicing(U1.ovenc)
    U1.compOV00 <- U1.OV00[U1.OV00_is_comp]
    
    # Write outputs
    message("Writing output files...")
    saveRDS(U1.compOV00, file="compatible_overlaps.rds")
    saveRDS(U1.ovenc, file="overlap_encodings.rds")
    
    comp_table <- table(Splicing_Compatible = U1.OV00_is_comp)
    write.csv(as.data.frame(comp_table), file="compatibility_summary.csv", row.names=FALSE)
    
    enc_table <- table(Encoding = encoding(U1.ovenc))
    write.csv(as.data.frame(enc_table), file="encoding_stats.csv", row.names=FALSE)
    
    pdf("compatibility_plot.pdf", width=6, height=6)
    barplot(comp_table, 
            main="Splicing Compatibility of Aligned Reads", 
            xlab="Compatible with Splicing", 
            ylab="Number of Overlaps", 
            col=c("tomato", "skyblue"))
    dev.off()
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_GENOMICALIGNMENTS_OVERLAP_ENCODING_AND_SPLICING_COMPATIBILITY":',
        paste0('        genomicalignments: ', as.character(packageVersion("genomicalignments")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_overlap_encoding_and_splicing_compatibility.csv versions.yml
    """
}

workflow BIOC_GENOMICALIGNMENTS_OVERLAP_ENCODING_AND_SPLICING_COMPATIBILITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bamfile, txdb ] ]

    main:
    BIOC_GENOMICALIGNMENTS_OVERLAP_ENCODING_AND_SPLICING_COMPATIBILITY(ch_input)

    emit:
    tables   = BIOC_GENOMICALIGNMENTS_OVERLAP_ENCODING_AND_SPLICING_COMPATIBILITY.out.tables
    plots    = BIOC_GENOMICALIGNMENTS_OVERLAP_ENCODING_AND_SPLICING_COMPATIBILITY.out.plots
    objects  = BIOC_GENOMICALIGNMENTS_OVERLAP_ENCODING_AND_SPLICING_COMPATIBILITY.out.objects
    versions = BIOC_GENOMICALIGNMENTS_OVERLAP_ENCODING_AND_SPLICING_COMPATIBILITY.out.versions
}
