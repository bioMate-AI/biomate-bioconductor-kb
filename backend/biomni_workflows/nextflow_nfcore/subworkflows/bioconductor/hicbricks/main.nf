#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HiCBricks — import_from_2d_text
// Create a Brick container and load cis/trans contact matrices from 2D text files.
// Input: Bintable_100kb.bins, Sexton2012_yaffetanay_CisTrans_100000_corrected_chr2L.txt.gz
// Container: quay.io/biocontainers/bioconductor-hicbricks:1.28.0--r45hdfd78af_0
// R packages: curl, GenomicRanges, HiCBricks, knitr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HICBRICKS_IMPORT_FROM_2D_TEXT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-hicbricks:1.28.0--r45hdfd78af_0"

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
    .bm_deps <- c("curl", "GenomicRanges", "HiCBricks", "knitr")
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
    
    # Load the required library
    library("HiCBricks")
    
    # Define input file paths from the working directory
    Bintable_path <- "Bintable_100kb.bins"
    Matrix_file_chr2L <- "Sexton2012_yaffetanay_CisTrans_100000_corrected_chr2L.txt.gz"
    
    # Create the project directory
    out_dir <- "HiCBricks_project"
    if (!dir.exists(out_dir)) {
        dir.create(out_dir, recursive = TRUE)
    }
    
    # --- Create the project directory and initialize the Brick ---
    Create_many_Bricks(
        BinTable = Bintable_path, 
        bin_delim = " ", 
        output_directory = out_dir, 
        file_prefix = "HiCBricks_vignette_test", 
        remove_existing = TRUE, 
        experiment_name = "HiCBricks vignette test", 
        resolution = 100000
    )
    
    # --- Load the BrickContainer ---
    BrickContainer_dir <- out_dir
    My_BrickContainer <- load_BrickContainer(project_dir = BrickContainer_dir)
    
    # --- Populate the Brick objects with contact frequencies from ---
    # Since only the chr2L matrix file is provided in the user input, we load chr2L.
    Chromosomes <- c("chr2L")
    for (chr in Chromosomes) {
        Matrix_file <- Matrix_file_chr2L
        Brick_load_matrix(
            Brick = My_BrickContainer, 
            chr1 = chr, 
            chr2 = chr, 
            resolution = 100000, 
            matrix_file = Matrix_file, 
            delim = " ", 
            remove_prior = TRUE
        )
    }
    
    # Save the BrickContainer object to an RDS file
    saveRDS(My_BrickContainer, file = "My_BrickContainer.rds")
    
    # Export meaningful results to verify successful loading
    # Export the bin table
    bintable <- Brick_get_bintable(My_BrickContainer, resolution = 100000)
    write.csv(as.data.frame(bintable), file = "bintable_output.csv", row.names = FALSE)
    
    # Export matrix summary statistics for chr2L
    m_dims <- Brick_matrix_dimensions(Brick = My_BrickContainer, chr1 = "chr2L", chr2 = "chr2L", resolution = 100000)
    m_minmax <- Brick_matrix_minmax(Brick = My_BrickContainer, chr1 = "chr2L", chr2 = "chr2L", resolution = 100000)
    
    summary_stats <- data.frame(
        Metric = c("Rows", "Cols", "Min_Value", "Max_Value"),
        Value = c(m_dims[1], m_dims[2], m_minmax[1], m_minmax[2])
    )
    write.csv(summary_stats, file = "chr2L_matrix_summary.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_HICBRICKS_IMPORT_FROM_2D_TEXT":',
        paste0('        HiCBricks: ', as.character(packageVersion("HiCBricks")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_import_from_2d_text.csv versions.yml
    """
}

workflow BIOC_HICBRICKS_IMPORT_FROM_2D_TEXT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Bintable_100kb.bins, Sexton2012_yaffetanay_CisTrans_100000_corrected_chr2L.txt.gz ] ]

    main:
    BIOC_HICBRICKS_IMPORT_FROM_2D_TEXT(ch_input)

    emit:
    tables   = BIOC_HICBRICKS_IMPORT_FROM_2D_TEXT.out.tables
    plots    = BIOC_HICBRICKS_IMPORT_FROM_2D_TEXT.out.plots
    objects  = BIOC_HICBRICKS_IMPORT_FROM_2D_TEXT.out.objects
    versions = BIOC_HICBRICKS_IMPORT_FROM_2D_TEXT.out.versions
}
