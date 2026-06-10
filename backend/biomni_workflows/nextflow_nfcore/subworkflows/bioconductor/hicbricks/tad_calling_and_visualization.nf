#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HiCBricks — tad_calling_and_visualization
// Call Topologically Associated Domains (TADs) using the LSD algorithm and plot a rotated heatmap with TAD borders.
// Input: My_BrickContainer
// Container: quay.io/biocontainers/bioconductor-hicbricks:1.28.0--r45hdfd78af_0
// R packages: GenomicRanges, HiCBricks
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HICBRICKS_TAD_CALLING_AND_VISUALIZATION {
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
    .bm_deps <- c("GenomicRanges", "HiCBricks")
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
    library(HiCBricks)
    library(GenomicRanges)
    
    # 1. Load the user-provided BrickContainer object
    if (!file.exists("My_BrickContainer")) {
      stop("Error: The required input file 'My_BrickContainer' was not found in the working directory.")
    }
    
    My_BrickContainer <- readRDS("My_BrickContainer")
    
    # 2. Call TADs across chromosomes using the LSD algorithm
    Chromosome <- c("chr2L", "chr3L", "chr3R", "chrX")
    di_window <- 10
    lookup_window <- 30
    
    TAD_ranges <- Brick_local_score_differentiator(
      Brick = My_BrickContainer, 
      chrs = Chromosome, 
      resolution = 100000, 
      di_window = di_window, 
      lookup_window = lookup_window, 
      strict = TRUE, 
      fill_gaps = TRUE, 
      chunk_size = 500
    )
    
    # 3. Save the called TAD ranges into the Brick container
    Name <- paste("LSD", di_window, lookup_window, sep = "_")
    Brick_add_ranges(
      Brick = My_BrickContainer, 
      ranges = TAD_ranges, 
      rangekey = Name, 
      resolution = 100000
    )
    
    # 4. Retrieve the saved TAD ranges
    TAD_ranges <- Brick_get_ranges(
      Brick = My_BrickContainer, 
      rangekey = Name, 
      resolution = 100000
    )
    
    # 5. Define custom log-transformation function
    Failsafe_log10 <- function(x) {
      x[is.na(x) | is.nan(x) | is.infinite(x)] <- 0
      return(log10(x + 1))
    }
    
    # 6. Plot a 45-degree rotated heatmap with overlaid TAD borders
    output_pdf <- "chr3R-1-10MB-normal-colours-log10-rotate-3-tads.pdf"
    
    Brick_vizart_plot_heatmap(
      File = output_pdf, 
      Bricks = list(My_BrickContainer), 
      tad_ranges = TAD_ranges, 
      x_coords = "chr3R:1:10000000", 
      y_coords = "chr3R:1:10000000", 
      resolution = 100000, 
      colours = "#230C0F", 
      FUN = Failsafe_log10, 
      value_cap = 0.99, 
      distance = 60, 
      legend_title = "Log10 Hi-C signal", 
      palette = "Reds", 
      width = 15, 
      height = 5, 
      line_width = 0.8, 
      cut_corners = TRUE, 
      rotate = TRUE, 
      return_object = TRUE
    )
    
    # 7. Save meaningful outputs to the working directory
    saveRDS(TAD_ranges, file = "TAD_ranges.rds")
    write.csv(as.data.frame(TAD_ranges), file = "TAD_ranges.csv", row.names = FALSE)
    saveRDS(My_BrickContainer, file = "My_BrickContainer_updated.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_HICBRICKS_TAD_CALLING_AND_VISUALIZATION":
        HiCBricks: \$(Rscript -e 'cat(as.character(packageVersion("HiCBricks")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tad_calling_and_visualization.csv versions.yml
    """
}

workflow BIOC_HICBRICKS_TAD_CALLING_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ My_BrickContainer ] ]

    main:
    BIOC_HICBRICKS_TAD_CALLING_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_HICBRICKS_TAD_CALLING_AND_VISUALIZATION.out.tables
    plots    = BIOC_HICBRICKS_TAD_CALLING_AND_VISUALIZATION.out.plots
    objects  = BIOC_HICBRICKS_TAD_CALLING_AND_VISUALIZATION.out.objects
    versions = BIOC_HICBRICKS_TAD_CALLING_AND_VISUALIZATION.out.versions
}
