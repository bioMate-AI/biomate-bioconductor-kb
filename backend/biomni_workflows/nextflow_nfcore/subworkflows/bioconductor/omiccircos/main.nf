#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: OmicCircos — circular_plot_simulation
// Generate a multi-track circular plot using simulated genomic mapping, link, and polygon data.
// Input: seg.f, seg.v, link.v, link.pg.v
// Container: quay.io/biocontainers/bioconductor-omiccircos:1.48.0--r45hdfd78af_0
// R packages: OmicCircos
// Bioconductor: 3.20 | R: 4.4
// Requires: OmicCircos
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Convert linear genomic coordinates to angle-based coordinates using segAnglePo. 2. Initialize a square plotting device. 3. Draw th

nextflow.enable.dsl = 2

process BIOC_OMICCIRCOS_CIRCULAR_PLOT_SIMULATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("OmicCircos")
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
        
        # Load required library
        library(OmicCircos)
        options(stringsAsFactors = FALSE)
        set.seed(1234)
        
        # Helper function to robustly read user input files
        read_input <- function(file_path) {
          if (!file.exists(file_path)) {
            stop(paste("Required input file missing:", file_path))
          }
          # Try reading as RDS first, then CSV, then TSV
          obj <- tryCatch({
            readRDS(file_path)
          }, error = function(e) {
            tryCatch({
              read.csv(file_path, header = TRUE, stringsAsFactors = FALSE)
            }, error = function(e2) {
              read.table(file_path, header = TRUE, sep = "\t", stringsAsFactors = FALSE)
            })
          })
          return(obj)
        }
        
        # Read the declared user input files from the working directory
        seg.f     <- read_input("seg.f")
        seg.v     <- read_input("seg.v")
        link.v    <- read_input("link.v")
        link.pg.v <- read_input("link.pg.v")
        
        # Process segment data and generate angle-based coordinates
        seg.name  <- unique(seg.f[,1])
        seg.num   <- length(seg.name)
        db        <- segAnglePo(seg.f, seg=seg.name)
        
        # Save the coordinate mapping database as a CSV output
        write.csv(db, "seg_angle_po.csv", row.names = FALSE)
        
        # Define colors safely (ensuring at least 10 colors to avoid out-of-bounds indexing)
        colors      <- rainbow(max(10, seg.num), alpha=0.5)
        link.pg.num <- nrow(link.pg.v)
        
        # Generate the circular plot and save as a PDF
        pdf("omiccircos_plot.pdf", width = 8, height = 8)
        
        par(mar=c(0, 0, 0, 0))
        plot(c(1,800), c(1,800), type="n", axes=FALSE, xlab="", ylab="", main="")
        
        # Draw the outer chromosome anchor track
        circos(R=400, cir=db, type="chr",  col=colors, print.chr.lab=TRUE, W=4, scale=TRUE)
        
        # Superimpose multiple mapping tracks
        circos(R=360, cir=db, W=40, mapping=seg.v, col.v=3, type="l",   B=TRUE, col=colors[1], lwd=2, scale=TRUE)
        circos(R=320, cir=db, W=40, mapping=seg.v, col.v=3, type="ls",  B=FALSE, col=colors[9], lwd=2, scale=TRUE)
        circos(R=280, cir=db, W=40, mapping=seg.v, col.v=3, type="lh",  B=TRUE, col=colors[7], lwd=2, scale=TRUE)
        circos(R=240, cir=db, W=40, mapping=seg.v, col.v=3, type="ml",  B=FALSE, col=colors, lwd=2, scale=TRUE)
        circos(R=200, cir=db, W=40, mapping=seg.v, col.v=3, type="ml2", B=TRUE, col=colors, lwd=2)
        circos(R=160, cir=db, W=40, mapping=seg.v, col.v=3, type="ml3", B=FALSE, cutoff=5, lwd=2)
        
        # Draw link curves and link polygons
        circos(R=150, cir=db, W=40, mapping=link.v, type="link", lwd=2, col=colors[c(1,7)])
        circos(R=150, cir=db, W=40, mapping=link.pg.v, type="link.pg", lwd=2, col=sample(colors, link.pg.num, replace=TRUE))
        
        dev.off()

    writeLines(c(
        '"BIOC_OMICCIRCOS_CIRCULAR_PLOT_SIMULATION":',
        paste0('    OmicCircos: ', as.character(packageVersion('OmicCircos')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_circular_plot_simulation.csv versions.yml
    """
}

workflow BIOC_OMICCIRCOS_CIRCULAR_PLOT_SIMULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ seg.f, seg.v, link.v, link.pg.v ] ]

    main:
    BIOC_OMICCIRCOS_CIRCULAR_PLOT_SIMULATION(ch_input)

    emit:
    tables   = BIOC_OMICCIRCOS_CIRCULAR_PLOT_SIMULATION.out.tables
    plots    = BIOC_OMICCIRCOS_CIRCULAR_PLOT_SIMULATION.out.plots
    objects  = BIOC_OMICCIRCOS_CIRCULAR_PLOT_SIMULATION.out.objects
    versions = BIOC_OMICCIRCOS_CIRCULAR_PLOT_SIMULATION.out.versions
}
