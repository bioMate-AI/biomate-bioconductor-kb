#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: seqcat — targeted_variant_validation
// Extract and visualize the genotypes of specific known variants of interest across multiple sample profiles.
// Input: example.vcf.gz
// Container: quay.io/biocontainers/bioconductor-seqcat:1.32.0--r45hdfd78af_0
// R packages: ggplot2, seqCAT
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_SEQCAT_TARGETED_VARIANT_VALIDATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-seqcat:1.32.0--r45hdfd78af_0"

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
    .bm_deps <- c("ggplot2", "seqCAT")
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
    library("seqCAT")
    library("ggplot2")
    
    # Define input file
    vcf <- "example.vcf.gz"
    
    # Check if input file exists
    if (!file.exists(vcf)) {
      stop(paste("Required input file", vcf, "not found in the working directory."))
    }
    
    # Create profiles
    hct116 <- create_profile(vcf, "HCT116")
    rko <- create_profile(vcf, "RKO", min_depth = 15, filter_gd = FALSE)
    
    # Define known variants of interest
    known_variants <- data.frame(chr  = c(12, 12, 12, 12),
                                 pos  = c(25358650, 21788465, 21797029, 25398281),
                                 gene = c("LYRM5", "LDHB", "LDHB", "KRAS"),
                                 stringsAsFactors = FALSE)
    
    # Extract genotypes for these variants across profiles
    variant_list <- list_variants(list(hct116, rko), known_variants)
    
    # Save raw variant list
    write.csv(variant_list, "variant_list_raw.csv", row.names = FALSE)
    
    # Format the variant list for plotting
    row.names(variant_list) <- paste0(variant_list\$chr, ":", variant_list\$pos,
                                      " (", variant_list\$gene, ")")
    to_remove <- c("chr", "pos", "gene")
    variant_list_formatted <- variant_list[, !names(variant_list) %in% to_remove]
    
    # Save formatted variant list
    write.csv(variant_list_formatted, "variant_list_formatted.csv", row.names = TRUE)
    
    # Plot the genotype grid
    genotype_grid <- plot_variant_list(variant_list_formatted)
    
    # Save the plot and the plot object
    ggsave("genotype_grid.pdf", plot = genotype_grid, width = 8, height = 6)
    saveRDS(genotype_grid, "genotype_grid.rds")

    writeLines(c(
        '"BIOC_SEQCAT_TARGETED_VARIANT_VALIDATION":',
        paste0('        seqcat: ', as.character(packageVersion("seqcat")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_targeted_variant_validation.csv versions.yml
    """
}

workflow BIOC_SEQCAT_TARGETED_VARIANT_VALIDATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example.vcf.gz ] ]

    main:
    BIOC_SEQCAT_TARGETED_VARIANT_VALIDATION(ch_input)

    emit:
    tables   = BIOC_SEQCAT_TARGETED_VARIANT_VALIDATION.out.tables
    plots    = BIOC_SEQCAT_TARGETED_VARIANT_VALIDATION.out.plots
    objects  = BIOC_SEQCAT_TARGETED_VARIANT_VALIDATION.out.objects
    versions = BIOC_SEQCAT_TARGETED_VARIANT_VALIDATION.out.versions
}
