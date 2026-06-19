#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: karyoploteR — custom_low_level_plotting
// Plot custom numeric data points, lines, segments, and bars across multiple data panels with custom axes and backgrounds.
// Input: rand.data, sel.data
// Container: quay.io/biocontainers/bioconductor-karyoploter:1.36.0--r45hdfd78af_0
// R packages: karyoploteR, regioneR
// Bioconductor: 3.20 | R: 4.4
// Requires: karyoploteR, regioneR
// Visualizations: karyotype plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Initialize a multi-panel karyotype plot using
//  * 2. [Visualization & Output] Add backgrounds to specific data panels using
//  * 3. [Visualization & Output] Add custom axes using kpAxis
//  * 4. [Visualization & Output] Plot data points, lines, segments, and bars using

nextflow.enable.dsl = 2

process BIOC_KARYOPLOTER_CUSTOM_LOW_LEVEL_PLOTTING {
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
    .bm_deps <- c("karyoploteR", "regioneR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        
        # Load required libraries
        library(karyoploteR)
        library(regioneR)
        
        # Helper function to robustly read the user input files
        read_input_file <- function(filepath) {
          if (!file.exists(filepath)) {
            stop(paste("Required input file missing:", filepath))
          }
          
          # Try reading as RDS
          res <- tryCatch(readRDS(filepath), error = function(e) NULL)
          if (!is.null(res)) return(res)
          
          # Try reading as table (whitespace/tab delimited)
          res <- tryCatch(read.table(filepath, header = TRUE, stringsAsFactors = FALSE), error = function(e) NULL)
          if (!is.null(res) && ncol(res) >= 3) return(res)
          
          # Try reading as CSV
          res <- tryCatch(read.csv(filepath, header = TRUE, stringsAsFactors = FALSE), error = function(e) NULL)
          if (!is.null(res) && ncol(res) >= 3) return(res)
          
          stop(paste("Could not parse file:", filepath))
        }
        
        # Read the exact user input files from the working directory
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        rand.data <- read_input_file("rand.data")
        sel.data <- read_input_file("sel.data")
        
        # Convert GRanges to data.frame to allow \$chr, \$start, \$end access and write.csv
        if (inherits(rand.data, "GRanges")) {
          rand.data <- toDataframe(rand.data)
        }
        if (inherits(sel.data, "GRanges")) {
          sel.data <- toDataframe(sel.data)
        }
        
        # Set up the output PDF file for the plot
        pdf("karyoplot_custom_low_level.pdf", width = 12, height = 10)
        
        # --- Initialize a multi-panel karyotype plot using ---
        kp <- plotKaryotype(genome="hg19", plot.type=2, chromosomes=c("chr1", "chr2", "chr3"))
        
        # --- Add backgrounds to specific data panels using ---
        # --- Add custom axes using kpAxis ---
        # --- Plot data points, lines, segments, and bars using ---
        
        kpDataBackground(kp, data.panel = 1, r0=0, r1=0.45)
        kpAxis(kp, ymin=-1, ymax=1, r0=0.05, r1=0.4, col="gray50", cex=0.5)
        kpPoints(kp, chr=rand.data\$chr, x=rand.data\$start, y=rand.data\$y,
                 ymin=-1, ymax=1, r0=0.05, r1=0.4, col="black", pch=".", cex=2)
        kpPoints(kp, chr=sel.data\$chr, x=sel.data\$start, y=sel.data\$y,
                 ymin=-1, ymax=1, r0=0.05, r1=0.4, col="red")
        kpText(kp, chr=sel.data\$chr, x=sel.data\$start, y=sel.data\$y,
               ymin=-1, ymax=1, r0=0.05, r1=0.4, labels=as.character(seq_len(nrow(sel.data))), col="red",
               pos=4, cex=0.8)
        
        
        #Upper part: data.panel=1
        kpDataBackground(kp, data.panel = 1, r0=0.5, r1=1)
        kpAxis(kp, ymin=-1, ymax=1, r0=0.5, r1=1, col="gray50", cex=0.5, numticks = 5)
        kpAbline(kp, h=c(-0.5, 0, 0.5), col="gray50", ymin=-1, ymax=1, r0=0.5, r1=1)
        kpLines(kp, chr=rand.data\$chr, x=rand.data\$start, y=rand.data\$y,
                col="#AA88FF", ymin=-1, ymax=1, r0=0.5, r1=1)
        #Use kpSegments to add small tic to the line
        kpSegments(kp, chr=rand.data\$chr, x0=rand.data\$start, x1=rand.data\$start,
                   y0=rand.data\$y-0.1, y1=rand.data\$y+0.1,
                   col="#8866DD", ymin=-1, ymax=1, r0=0.5, r1=1)
        #Plot the same line but inverting the data by pssing a r0>r1
        kpLines(kp, chr=rand.data\$chr, x=rand.data\$start, y=rand.data\$y,
                col="#FF88AA", ymin=-1, ymax=1, r0=1, r1=0.5)
        
        
        #Lower part: data.panel=2
        kpDataBackground(kp, r0=0, r1=0.29, color = "#EEFFEE", data.panel = 2)
        kpAxis(kp, col="#AADDAA", ymin=-1, ymax=1, r0=0, r1=0.29, data.panel = 2,
               numticks = 2, cex=0.5, tick.len = 0)
        kpAbline(kp, h=0, col="#AADDAA", ymin=-1, ymax=1, r0=0, r1=0.29, data.panel = 2)
        kpBars(kp, chr=rand.data\$chr, x0=rand.data\$start, x1=rand.data\$end, y1 = rand.data\$y,
                col="#AADDAA", ymin=-1, ymax=1, r0=0, r1=0.29, data.panel = 2, border="#AADDAA" )
        
        kpDataBackground(kp, r0=0.34, r1=0.63, color = "#EEEEFF", data.panel = 2)
        kpAxis(kp, col="#AAAADD", ymin=-1, ymax=1, r0=0.34, r1=0.63, data.panel = 2, 
               numticks = 2, cex=0.5, tick.len = 0)
        kpAbline(kp, h=0, col="#AAAADD", ymin=-1, ymax=1, r0=0.34, r1=0.63, data.panel = 2)
        kpSegments(kp, chr=rand.data\$chr, x0=rand.data\$start, x1=rand.data\$end, 
                   y0=rand.data\$y-0.2, y1=rand.data\$y, 
                   col="#AAAADD", ymin=-1, ymax=1, r0=0.34, r1=0.63, data.panel = 2, lwd=2)
        
        kpDataBackground(kp, r0=0.68, r1=0.97, color = "#FFEEEE", data.panel = 2)
        kpAxis(kp, col="#DDAAAA", ymin=-1, ymax=1, r0=0.68, r1=0.97, data.panel = 2,
               numticks = 2, cex=0.5, tick.len = 0)
        kpPoints(kp, chr=rand.data\$chr, x=rand.data\$start, y=rand.data\$y,
                col="#DDAAAA", ymin=-1, ymax=1, r0=0.68, r1=0.97, data.panel = 2, pch=".", cex=3)
        
        # Close the PDF graphics device
        dev.off()
        
        # Save the KaryoPlot object and processed data summaries as outputs
        saveRDS(kp, "karyoplot_object.rds")
        write.csv(rand.data, "processed_rand_data.csv", row.names = FALSE)
        write.csv(sel.data, "processed_sel_data.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_KARYOPLOTER_CUSTOM_LOW_LEVEL_PLOTTING":',
        paste0('    karyoploteR: ', as.character(packageVersion('karyoploteR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_low_level_plotting.csv versions.yml
    """
}

workflow BIOC_KARYOPLOTER_CUSTOM_LOW_LEVEL_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rand.data, sel.data ] ]

    main:
    BIOC_KARYOPLOTER_CUSTOM_LOW_LEVEL_PLOTTING(ch_input)

    emit:
    tables   = BIOC_KARYOPLOTER_CUSTOM_LOW_LEVEL_PLOTTING.out.tables
    plots    = BIOC_KARYOPLOTER_CUSTOM_LOW_LEVEL_PLOTTING.out.plots
    objects  = BIOC_KARYOPLOTER_CUSTOM_LOW_LEVEL_PLOTTING.out.objects
    versions = BIOC_KARYOPLOTER_CUSTOM_LOW_LEVEL_PLOTTING.out.versions
}
