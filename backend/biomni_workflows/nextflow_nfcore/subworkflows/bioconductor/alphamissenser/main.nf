#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: AlphaMissenseR — genomic_range_overlap
// Query and annotate user-defined genomic ranges (such as exons of a gene) with AlphaMissense pathogenicity predictions using DuckDB range joins.
// Input: bcl2l11_tbl
// Container: quay.io/biocontainers/bioconductor-alphamissenser:1.6.1--r45hdfd78af_0
// R packages: AlphaMissenseR, dplyr, tidyr
// Bioconductor: 3.20 | R: 4.4
// Requires: AlphaMissenseR, dplyr, tidyr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Connect to the AlphaMissense DuckDB database with write permissions
//  * 2. [Visualization & Output] Write the user ranges to a temporary table in DuckDB
//  * 3. [Core Analysis] Perform a fast database-side range join using db_range_join()
//  * 4. [Core Analysis] Disconnect from the database

nextflow.enable.dsl = 2

process BIOC_ALPHAMISSENSER_GENOMIC_RANGE_OVERLAP {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("AlphaMissenseR", "dplyr", "tidyr")
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
    
    library(AlphaMissenseR)
    library(dplyr)
    library(tidyr)
    
    # 1. Read user input
    if (file.exists("bcl2l11_tbl.rds")) {
      bcl2l11_tbl <- readRDS("bcl2l11_tbl.rds")
    } else if (file.exists("bcl2l11_tbl.csv")) {
      bcl2l11_tbl <- read.csv("bcl2l11_tbl.csv")
    } else {
      stop("Required input file 'bcl2l11_tbl' (as .rds or .csv) not found in the working directory.")
    }
    
    # Ensure it is a tibble
    bcl2l11_tbl <- dplyr::as_tibble(bcl2l11_tbl)
    
    # Ensure hg38 data is available in the database
    tryCatch({
      am_data("hg38")
    }, error = function(e) {
      message("Note: am_data('hg38') failed or was already loaded. Proceeding with join.")
    })
    
    # 2. Execute documented workflow
    db_rw <- db_connect ( read_only = FALSE )
    db_temporary_table (db_rw, bcl2l11_tbl, "bcl2l11" )
    rng <- db_range_join (db_rw, "hg38" , "bcl2l11" , "bcl2l11_overlaps" )
    
    # Collect results before disconnecting
    rng_df <- dplyr::collect(rng)
    
    db_disconnect (db_rw)
    
    # 3. Write outputs
    write.csv(rng_df, "bcl2l11_overlaps.csv", row.names = FALSE)
    saveRDS(rng_df, "bcl2l11_overlaps.rds")
    
    # Generate and write summary if columns exist
    if ("exon_id" %in% colnames(rng_df) && "am_class" %in% colnames(rng_df)) {
      summary_df <- rng_df %>%
        dplyr::count(exon_id, am_class) %>%
        tidyr::pivot_wider(names_from = "am_class", values_from = "n", values_fill = 0)
      write.csv(summary_df, "bcl2l11_overlaps_summary.csv", row.names = FALSE)
    } else if ("am_class" %in% colnames(rng_df)) {
      summary_df <- rng_df %>%
        dplyr::count(CHROM, am_class)
      write.csv(summary_df, "bcl2l11_overlaps_summary.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_ALPHAMISSENSER_GENOMIC_RANGE_OVERLAP":',
        paste0('    AlphaMissenseR: ', as.character(packageVersion('AlphaMissenseR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomic_range_overlap.csv versions.yml
    """
}

workflow BIOC_ALPHAMISSENSER_GENOMIC_RANGE_OVERLAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bcl2l11_tbl ] ]

    main:
    BIOC_ALPHAMISSENSER_GENOMIC_RANGE_OVERLAP(ch_input)

    emit:
    tables   = BIOC_ALPHAMISSENSER_GENOMIC_RANGE_OVERLAP.out.tables
    plots    = BIOC_ALPHAMISSENSER_GENOMIC_RANGE_OVERLAP.out.plots
    objects  = BIOC_ALPHAMISSENSER_GENOMIC_RANGE_OVERLAP.out.objects
    versions = BIOC_ALPHAMISSENSER_GENOMIC_RANGE_OVERLAP.out.versions
}
