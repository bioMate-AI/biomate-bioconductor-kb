#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ggmanh — gds_variant_annotation_plotting
// Annotate GWAS summary statistics with gene/consequence information from a GDS file and plot the annotated Manhattan plot.
// Input: gwas_alleles.csv
// Container: quay.io/biocontainers/bioconductor-ggmanh:1.14.0--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SeqArray, ggmanh, ggplot2
// Visualizations: Manhattan plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Annotate variants using gds_annotate()
//  * 2. [Visualization & Output] Plot the annotated data using manhattan_plot()

nextflow.enable.dsl = 2

process BIOC_GGMANH_GDS_VARIANT_ANNOTATION_PLOTTING {
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
    .bm_deps <- c("ggmanh", "SeqArray", "ggplot2")
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
    library(ggmanh)
    library(SeqArray)
    library(ggplot2)
    
    # 1. Read the user input file
    input_file <- "gwas_alleles.csv"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    simdata_label <- read.csv(input_file, stringsAsFactors = FALSE)
    
    # Ensure chromosome is a factor to avoid plotting ambiguity
    if ("chromosome" %in% colnames(simdata_label)) {
      chrs <- unique(simdata_label\$chromosome)
      suppressWarnings({
        num_chrs <- as.numeric(chrs)
        if (any(!is.na(num_chrs))) {
          chrs_sorted <- c(sort(num_chrs[!is.na(num_chrs)]), sort(chrs[is.na(num_chrs)]))
          simdata_label\$chromosome <- factor(simdata_label\$chromosome, levels = chrs_sorted)
        } else {
          simdata_label\$chromosome <- factor(simdata_label\$chromosome)
        }
      })
    }
    
    # 2. Annotate variants using gds_annotate()
    # This uses the default GDS file bundled with ggmanh since gdsfile is not specified
    simdata_label\$label <- gds_annotate(x = simdata_label, annot.method = "position", chr = "chromosome", pos = "position", ref = "Reference", alt = "Alternate")
    
    # Save the annotated data to a CSV file
    write.csv(simdata_label, "annotated_gwas_variants.csv", row.names = FALSE)
    
    # 3. Plot the annotated data using manhattan_plot()
    # We capture the plot object and save it to a PDF file
    plot_obj <- manhattan_plot(simdata_label, outfn = NULL, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position", label.colname = "label")
    
    # Save the plot to a PDF file
    ggsave("annotated_manhattan_plot.pdf", plot = plot_obj, width = 10, height = 6)
    
    # Save the plot object as an RDS for downstream customization
    saveRDS(plot_obj, "annotated_manhattan_plot.rds")

    writeLines(c(
        '"BIOC_GGMANH_GDS_VARIANT_ANNOTATION_PLOTTING":',
        paste0('    ggmanh: ', as.character(packageVersion('ggmanh')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gds_variant_annotation_plotting.csv versions.yml
    """
}

workflow BIOC_GGMANH_GDS_VARIANT_ANNOTATION_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gwas_alleles.csv ] ]

    main:
    BIOC_GGMANH_GDS_VARIANT_ANNOTATION_PLOTTING(ch_input)

    emit:
    tables   = BIOC_GGMANH_GDS_VARIANT_ANNOTATION_PLOTTING.out.tables
    plots    = BIOC_GGMANH_GDS_VARIANT_ANNOTATION_PLOTTING.out.plots
    objects  = BIOC_GGMANH_GDS_VARIANT_ANNOTATION_PLOTTING.out.objects
    versions = BIOC_GGMANH_GDS_VARIANT_ANNOTATION_PLOTTING.out.versions
}
