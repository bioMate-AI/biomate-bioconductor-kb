#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cellbarcode — fastq_lineage_barcoding
// Perform quality control, filter, extract, cure, and quantify lineage barcodes and UMIs from raw FASTQ files.
// Input: fq_files, metadata
// Container: quay.io/biocontainers/bioconductor-cellbarcode:1.16.0--r45ha27e39d_0
// R packages: CellBarcode, data.table, ggplot2, magrittr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CELLBARCODE_FASTQ_LINEAGE_BARCODING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-cellbarcode:1.16.0--r45ha27e39d_0"

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
    .bm_deps <- c("CellBarcode", "data.table", "ggplot2", "magrittr")
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
    library(CellBarcode)
    library(ggplot2)
    library(data.table)
    
    # ----------------------------------------------------------------------
    # --- Read User Input Files from Working Directory ---
    # ----------------------------------------------------------------------
    
    # Read metadata (expects metadata.csv or metadata.tsv in the working directory)
    if (file.exists("metadata.csv")) {
      metadata <- read.csv("metadata.csv", row.names = 1, stringsAsFactors = FALSE)
    } else if (file.exists("metadata.tsv")) {
      metadata <- read.delim("metadata.tsv", row.names = 1, stringsAsFactors = FALSE)
    } else {
      stop("Metadata file (metadata.csv or metadata.tsv) not found in the working directory.")
    }
    
    # Find fastq.gz files in the working directory
    all_fq_files <- list.files(pattern = "\\\\.fastq\\\\.gz\$|\\\\.fq\\\\.gz\$", full.names = TRUE)
    if (length(all_fq_files) == 0) {
      stop("No fastq.gz files found in the working directory.")
    }
    
    # Align fq_files with metadata row names (sample names)
    sample_name <- rownames(metadata)
    fq_files <- sapply(sample_name, function(sn) {
      matched <- grep(sn, all_fq_files, value = TRUE)
      if (length(matched) == 0) {
        stop(paste("No fastq file found matching sample name:", sn))
      }
      matched[1]
    })
    names(fq_files) <- sample_name
    
    # ----------------------------------------------------------------------
    # --- Quality Control and Filtering ---
    # ----------------------------------------------------------------------
    
    # Evaluate sequence quality
    qc_noFilter <- bc_seq_qc(fq_files)
    
    # Visualize and save QC plots
    pdf("qc_plots.pdf", width = 10, height = 7)
    bc_plot_seqQc(qc_noFilter)
    dev.off()
    
    # Filter low-quality reads
    fq_filter <- bc_seq_filter(
      fq_files,
      min_average_quality = 30,
      min_read_length = 60,
      sample_name = sample_name)
    
    # ----------------------------------------------------------------------
    # --- Barcode and UMI Extraction ---
    # ----------------------------------------------------------------------
    
    pattern <- "([ACGA]{12})CTCGAGGTCATCGAAGTATC([ACGT]+)CCGTAGCAAGCTCGAGAGTAGACCTACT"
    bc_obj_umi <- bc_extract(
      fq_filter,
      sample_name = sample_name,
      pattern = pattern,
      maxLDist = 0,
      pattern_type = c(UMI = 1, barcode = 2))
    
    # ----------------------------------------------------------------------
    # --- Subset Samples (dynamically selecting the first two ---
    # ----------------------------------------------------------------------
    
    sub_samples <- sample_name[1:min(2, length(sample_name))]
    bc_obj_umi_sub <- bc_obj_umi[, sub_samples]
    
    # ----------------------------------------------------------------------
    # --- Filter UMI-barcode tags ---
    # ----------------------------------------------------------------------
    
    bc_obj_umi_sub <- bc_cure_umi(
        bc_obj_umi_sub, depth = 1, 
        isUniqueUMI = TRUE, 
        doFish = TRUE)
    
    # ----------------------------------------------------------------------
    # --- Filter by sequence/UMI depth ---
    # ----------------------------------------------------------------------
    
    bc_obj_umi_sub <- bc_cure_depth(bc_obj_umi_sub, depth = 3, isUpdate = TRUE)
    
    # ----------------------------------------------------------------------
    # --- Cluster and merge similar barcodes ---
    # ----------------------------------------------------------------------
    
    bc_cure_cluster(bc_obj_umi_sub)
    
    # ----------------------------------------------------------------------
    # --- Visualize barcode distributions ---
    # ----------------------------------------------------------------------
    
    pdf("barcode_distribution_single.pdf", width = 7, height = 7)
    bc_plot_single(bc_obj_umi_sub)
    dev.off()
    
    # ----------------------------------------------------------------------
    # --- Export quantified barcodes ---
    # ----------------------------------------------------------------------
    
    # Export to data.frame and save
    df_out <- bc_2df(bc_obj_umi_sub)
    write.csv(df_out, "quantified_barcodes.csv", row.names = FALSE)
    
    # Export to matrix and save
    mat_out <- bc_2matrix(bc_obj_umi_sub)
    write.csv(mat_out, "quantified_barcodes_matrix.csv")
    
    # Save the final BarcodeObj as an RDS file
    saveRDS(bc_obj_umi_sub, "final_barcode_obj.rds")

    writeLines(c(
        '"BIOC_CELLBARCODE_FASTQ_LINEAGE_BARCODING":',
        paste0('        cellbarcode: ', as.character(packageVersion("cellbarcode")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fastq_lineage_barcoding.csv versions.yml
    """
}

workflow BIOC_CELLBARCODE_FASTQ_LINEAGE_BARCODING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fq_files, metadata ] ]

    main:
    BIOC_CELLBARCODE_FASTQ_LINEAGE_BARCODING(ch_input)

    emit:
    tables   = BIOC_CELLBARCODE_FASTQ_LINEAGE_BARCODING.out.tables
    plots    = BIOC_CELLBARCODE_FASTQ_LINEAGE_BARCODING.out.plots
    objects  = BIOC_CELLBARCODE_FASTQ_LINEAGE_BARCODING.out.objects
    versions = BIOC_CELLBARCODE_FASTQ_LINEAGE_BARCODING.out.versions
}
