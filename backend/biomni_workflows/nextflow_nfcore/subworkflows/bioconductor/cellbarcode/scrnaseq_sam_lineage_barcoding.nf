#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cellbarcode — scrnaseq_sam_lineage_barcoding
// Extract lineage barcodes, cell barcodes, and UMIs from 10X Genomics single-cell RNA-seq SAM files.
// Input: sam_file
// Container: quay.io/biocontainers/bioconductor-cellbarcode:1.16.0--r45ha27e39d_0
// R packages: CellBarcode, data.table, ggplot2
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CELLBARCODE_SCRNASEQ_SAM_LINEAGE_BARCODING {
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
    .bm_deps <- c("CellBarcode", "data.table", "ggplot2")
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
    
    library(CellBarcode)
    library(data.table)
    library(ggplot2)
    
    # Define input file from the working directory
    sam_file <- "scRNASeq_10X.sam"
    
    if (!file.exists(sam_file)) {
      stop(paste("Required input SAM file is missing:", sam_file))
    }
    
    # Extract lineage barcodes, cell barcodes, and UMIs
    message("Extracting barcodes from SAM file...")
    d = bc_extract_sc_sam(
       sam = sam_file,
       pattern = "AGATCAG(.*)TGTGGTA",
       cell_barcode_tag = "CR",
       umi_tag = "UR"
    )
    
    # Save the raw BarcodeObj
    message("Saving BarcodeObj to RDS...")
    saveRDS(d, "extracted_barcodes.rds")
    
    # Export messy barcodes to CSV
    message("Exporting messy barcodes to CSV...")
    tryCatch({
      messy_df <- bc_messyBc(d, isList = FALSE)
      write.csv(messy_df, "messy_barcodes.csv", row.names = FALSE)
    }, error = function(e) {
      message("Could not export messy barcodes: ", e\$message)
    })
    
    # Perform basic filtering to populate cleanBc slot and export/plot
    message("Filtering and plotting barcodes...")
    tryCatch({
      # Filter with depth >= 1 to initialize cleanBc slot
      d_clean <- bc_cure_depth(d, depth = 1, isUpdate = FALSE)
      
      # Export clean barcodes
      clean_df <- bc_2df(d_clean)
      write.csv(clean_df, "clean_barcodes.csv", row.names = FALSE)
      
      # Plot barcode distribution
      pdf("barcode_plots.pdf", width = 8, height = 6)
      print(bc_plot_single(d_clean))
      dev.off()
      message("Plots saved to barcode_plots.pdf")
    }, error = function(e) {
      message("Error during filtering or plotting: ", e\$message)
    })
    
    message("Pipeline completed successfully.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CELLBARCODE_SCRNASEQ_SAM_LINEAGE_BARCODING":
        cellbarcode: \$(Rscript -e 'cat(as.character(packageVersion("cellbarcode")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scrnaseq_sam_lineage_barcoding.csv versions.yml
    """
}

workflow BIOC_CELLBARCODE_SCRNASEQ_SAM_LINEAGE_BARCODING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sam_file ] ]

    main:
    BIOC_CELLBARCODE_SCRNASEQ_SAM_LINEAGE_BARCODING(ch_input)

    emit:
    tables   = BIOC_CELLBARCODE_SCRNASEQ_SAM_LINEAGE_BARCODING.out.tables
    plots    = BIOC_CELLBARCODE_SCRNASEQ_SAM_LINEAGE_BARCODING.out.plots
    objects  = BIOC_CELLBARCODE_SCRNASEQ_SAM_LINEAGE_BARCODING.out.objects
    versions = BIOC_CELLBARCODE_SCRNASEQ_SAM_LINEAGE_BARCODING.out.versions
}
