#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: karyoploteR — zoomed_region_plotting
// Zoom into a specific genomic region to plot detailed data points and arrows, controlling whether elements are clipped at the panel boundaries.
// Input: detail.region
// Container: quay.io/biocontainers/bioconductor-karyoploter:1.36.0--r45hdfd78af_0
// R packages: GenomicRanges, karyoploteR, regioneR
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, karyoploteR, regioneR
// Visualizations: karyotype plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Define the detail region to zoom into
//  * 2. [Visualization & Output] Initialize the zoomed plot using plotKaryotype with the
//  * 3. [Visualization & Output] Add background and base numbers
//  * 4. [Visualization & Output] Plot data points and arrows, specifying clipping=FALSE

nextflow.enable.dsl = 2

process BIOC_KARYOPLOTER_ZOOMED_REGION_PLOTTING {
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
    .bm_deps <- c("GenomicRanges", "karyoploteR", "regioneR")
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
    library(karyoploteR)
    library(regioneR)
    library(GenomicRanges)
    
    # --- Define the detail region to zoom into ---
    # Read the GRanges object from the declared user input file 'detail.region'
    detail.region <- readRDS("detail.region")
    
    # Extract dynamic coordinates from the user-provided region
    chrom <- as.character(seqnames(detail.region))[1]
    r_start <- start(detail.region)[1]
    r_end <- end(detail.region)[1]
    r_width <- r_end - r_start
    
    # Set up PDF output file to save the plot
    pdf("zoomed_region_plot.pdf", width = 10, height = 6)
    
    # --- Initialize the zoomed plot using plotKaryotype with the ---
    kp <- plotKaryotype(plot.type = 4, zoom = detail.region)
    
    # --- Add background and base numbers ---
    kpDataBackground(kp, data.panel = 1)
    kpAddBaseNumbers(kp)
    
    # --- Plot data points and arrows, specifying clipping=FALSE ---
    # Dynamically place them relative to the detail.region so they remain visible regardless of the input range
    kpPoints(kp, chr = chrom, x = r_end, y = 0.5, pch = 16, cex = 8, col = "#FAC67A")
    kpArrows(kp, chr = chrom, x0 = r_start - (r_width * 1.88), x1 = r_end - (r_width * 0.22), y0 = 0.2, y1 = 1.1, clipping = FALSE)
    kpArrows(kp, chr = chrom, x0 = r_end - (r_width * 0.44), x1 = r_end + (r_width * 1.33), y0 = 0.9, y1 = 0.5, clipping = FALSE)
    
    # Close the PDF device
    dev.off()
    
    # Save the resulting KaryoPlot object as an RDS file
    saveRDS(kp, "karyoplot_output.rds")

    writeLines(c(
        '"BIOC_KARYOPLOTER_ZOOMED_REGION_PLOTTING":',
        paste0('    karyoploteR: ', as.character(packageVersion('karyoploteR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_zoomed_region_plotting.csv versions.yml
    """
}

workflow BIOC_KARYOPLOTER_ZOOMED_REGION_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ detail.region ] ]

    main:
    BIOC_KARYOPLOTER_ZOOMED_REGION_PLOTTING(ch_input)

    emit:
    tables   = BIOC_KARYOPLOTER_ZOOMED_REGION_PLOTTING.out.tables
    plots    = BIOC_KARYOPLOTER_ZOOMED_REGION_PLOTTING.out.plots
    objects  = BIOC_KARYOPLOTER_ZOOMED_REGION_PLOTTING.out.objects
    versions = BIOC_KARYOPLOTER_ZOOMED_REGION_PLOTTING.out.versions
}
