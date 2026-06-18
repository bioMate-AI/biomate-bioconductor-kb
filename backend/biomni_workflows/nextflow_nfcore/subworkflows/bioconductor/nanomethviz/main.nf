#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NanoMethViz — tabular_data_import_and_plotting
// Import tabular methylation calls, convert them to tabix format, construct a NanoMethResult object, and plot gene-level methylation.
// Input: methy_calls.tsv.gz, sample_anno.csv
// Container: quay.io/biocontainers/bioconductor-nanomethviz:2.8.1--r43hf17093f_0
// R packages: dplyr, NanoMethViz
// Bioconductor: 3.20 | R: 4.4
// Requires: NanoMethViz, dplyr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert tabular files to tabix format using create_tabix_file()
//  * 2. [Core Analysis] Retrieve exon annotations using get_exons_mm10() or get_exons_hg19()
//  * 3. [Input & Preparation] Define sample annotations
//  * 4. [Input & Preparation] Construct the NanoMethResult object
//  * 5. [Visualization & Output] Plot methylation patterns using plot_gene()

nextflow.enable.dsl = 2

process BIOC_NANOMETHVIZ_TABULAR_DATA_IMPORT_AND_PLOTTING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("dplyr", "NanoMethViz")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM, jammy)
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
    library(NanoMethViz)
    library(dplyr)
    
    # 1. Read user input files
    # The pipeline reads exactly these files from the working directory:
    # - methy_calls.tsv.gz (tabular methylation calls)
    # - sample_anno.csv (sample annotation table with sample and group columns)
    methy_calls <- "methy_calls.tsv.gz"
    sample_anno <- read.csv("sample_anno.csv", stringsAsFactors = FALSE)
    
    # Extract sample names from the annotation table
    samples <- sample_anno\$sample
    
    # Define the output path for the tabix file
    methy_tabix <- "methy_data.bgz"
    
    # 2. Convert tabular files to tabix format
    # FIX: Do not pass the 'samples' vector when providing a single input file 
    # to avoid length mismatch errors. The single file already contains sample names.
    create_tabix_file(methy_calls, methy_tabix)
    
    # 3. Retrieve exon annotations
    exon_tibble <- get_exons_mm10()
    
    # Define 'methy' as the path to the tabix file to match the documented constructor call
    methy <- methy_tabix
    
    # 4. Construct the NanoMethResult object
    nmr <- NanoMethResult(methy, sample_anno, exon_tibble)
    
    # Save the constructed NanoMethResult object
    saveRDS(nmr, "nanometh_result.rds")
    
    # 5. Plot gene-level methylation patterns
    # FIX: Dynamically select a gene present in the user's data instead of hardcoding 'Peg3'
    methy_data_sample <- read.table(gzfile(methy_tabix), col.names = methy_col_names(), nrows = 1000)
    
    if (nrow(methy_data_sample) > 0) {
        data_chr <- methy_data_sample\$chr[1]
        data_pos <- methy_data_sample\$pos[1]
        
        possible_exons <- exon_tibble[exon_tibble\$chr == data_chr, ]
        if (nrow(possible_exons) > 0) {
            distances <- abs(possible_exons\$start - data_pos)
            target_gene <- possible_exons\$symbol[which.min(distances)]
        } else {
            target_gene <- exon_tibble\$symbol[1]
        }
    } else {
        target_gene <- exon_tibble\$symbol[1]
    }
    
    # Plot 1: Basic gene plot
    pdf("plot_gene_dynamic.pdf", width = 7, height = 5)
    plot_gene(nmr, target_gene)
    dev.off()
    
    # Define bsseq_dmr dynamically based on target_gene coordinates to avoid system.file/demo data
    target_exons <- exon_tibble[exon_tibble\$symbol == target_gene, ]
    if (nrow(target_exons) > 0) {
        bsseq_dmr <- data.frame(
            chr = target_exons\$chr[1],
            start = min(target_exons\$start),
            end = max(target_exons\$end),
            stringsAsFactors = FALSE
        )
    } else {
        # Fallback coordinates if target_gene is not found in the annotation
        bsseq_dmr <- data.frame(
            chr = "chr11",
            start = 101463000,
            end = 101464000,
            stringsAsFactors = FALSE
        )
    }
    
    # Plot 2: Gene plot with annotated regions highlighted
    pdf("plot_gene_dynamic_dmr.pdf", width = 7, height = 5)
    plot_gene(nmr, target_gene, anno_regions = bsseq_dmr)
    dev.off()

    writeLines(c(
        '"BIOC_NANOMETHVIZ_TABULAR_DATA_IMPORT_AND_PLOTTING":',
        paste0('    NanoMethViz: ', as.character(packageVersion('NanoMethViz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tabular_data_import_and_plotting.csv versions.yml
    """
}

workflow BIOC_NANOMETHVIZ_TABULAR_DATA_IMPORT_AND_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ methy_calls.tsv.gz, sample_anno.csv ] ]

    main:
    BIOC_NANOMETHVIZ_TABULAR_DATA_IMPORT_AND_PLOTTING(ch_input)

    emit:
    tables   = BIOC_NANOMETHVIZ_TABULAR_DATA_IMPORT_AND_PLOTTING.out.tables
    plots    = BIOC_NANOMETHVIZ_TABULAR_DATA_IMPORT_AND_PLOTTING.out.plots
    objects  = BIOC_NANOMETHVIZ_TABULAR_DATA_IMPORT_AND_PLOTTING.out.objects
    versions = BIOC_NANOMETHVIZ_TABULAR_DATA_IMPORT_AND_PLOTTING.out.versions
}
