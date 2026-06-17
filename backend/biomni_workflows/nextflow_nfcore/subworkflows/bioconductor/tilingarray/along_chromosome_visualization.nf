#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tilingArray — along_chromosome_visualization
// Visualize genomic expression profiles and segmentation boundaries along a chromosome region using dot plots or heatmaps aligned with GFF annotations.
// Input: segmentation_env.RData, gff_annotation.gff
// Container: quay.io/biocontainers/bioconductor-tilingarray:1.88.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RColorBrewer, tilingArray
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Plot expression data along the chromosome as a dot plot using plotAlongChrom
//  * 2. [Visualization & Output] Plot separate dot plots for different conditions using the sepPlot parameter
//  * 3. [Visualization & Output] Plot expression data as a heatmap using plotAlongChrom with what="heatmap"
//  * 4. [Visualization & Output] Optimize heatmap rendering speed and color palettes using makeRasterImage and colHeatmap

nextflow.enable.dsl = 2

process BIOC_TILINGARRAY_ALONG_CHROMOSOME_VISUALIZATION {
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
    .bm_deps <- c("RColorBrewer", "tilingArray")
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
        library("grid")
        library("RColorBrewer")
        library("tilingArray")
        
        # -----------------------------------------------------------------------------
        # Stage 1: Read and Parse User Input Files
        # -----------------------------------------------------------------------------
        
        gff_file <- "gff_annotation.gff"
        if (!file.exists(gff_file)) {
          stop("Required input file 'gff_annotation.gff' not found in the working directory.")
        }
        
        # Read GFF file robustly (handles both standard GFF and custom tab-delimited tables)
        first_line <- readLines(gff_file, n = 1)
        if (grepl("start", first_line) && grepl("end", first_line)) {
          gffSub <- read.table(gff_file, header = TRUE, sep = "\t", stringsAsFactors = FALSE)
        } else {
          gff_data <- read.delim(gff_file, header = FALSE, comment.char = "#", stringsAsFactors = FALSE)
          colnames(gff_data) <- c("chr", "source", "feature", "start", "end", "score", "strand", "frame", "attributes")
          
          extract_attr <- function(attr_str, key) {
            pattern <- paste0("(^|;)\\\\s*", key, "=\\\\s*([^;]+)")
            matches <- regexec(pattern, attr_str)
            regmatches(attr_str, matches)
            sapply(regmatches(attr_str, matches), function(x) {
              if (length(x) >= 3) return(x[3]) else return(NA)
            })
          }
          
          gffSub <- data.frame(
            id = 1:nrow(gff_data),
            chr = gff_data\$chr,
            start = as.numeric(gff_data\$start),
            end = as.numeric(gff_data\$end),
            strand = gff_data\$strand,
            source = gff_data\$source,
            feature = gff_data\$feature,
            Name = extract_attr(gff_data\$attributes, "Name"),
            gene = extract_attr(gff_data\$attributes, "gene"),
            stringsAsFactors = FALSE
          )
          
          if (all(is.na(gffSub\$Name))) {
            gffSub\$Name <- extract_attr(gff_data\$attributes, "ID")
          }
          if (all(is.na(gffSub\$gene))) {
            gffSub\$gene <- gffSub\$Name
          }
        }
        
        # Load segmentation environment
        env_file <- "segmentation_env.RData"
        if (!file.exists(env_file)) {
          stop("Required input file 'segmentation_env.RData' not found in the working directory.")
        }
        
        loadEnv <- new.env()
        load(env_file, envir = loadEnv)
        
        # Find the environment object containing segmentation classes
        segnf <- NULL
        for (obj_name in ls(loadEnv)) {
          obj <- loadEnv[[obj_name]]
          if (is.environment(obj)) {
            segnf <- obj
            break
          }
        }
        
        if (is.null(segnf)) {
          segnf <- loadEnv
        }
        
        # Dynamically determine chromosome name from the environment objects
        elements <- ls(segnf)
        pos_elem <- elements[grep("\\\\+\$", elements)][1]
        if (is.na(pos_elem)) pos_elem <- elements[1]
        if (is.na(pos_elem)) {
          stop("No segmentation objects found in the loaded environment.")
        }
        
        chr_name <- sub("\\\\.[+-]\$", "", pos_elem)
        pos_name <- paste0(chr_name, ".+")
        neg_name <- paste0(chr_name, ".-")
        
        if (!(pos_name %in% elements)) {
          assign(pos_name, get(pos_elem, envir = segnf), envir = segnf)
        }
        
        if (!(neg_name %in% elements)) {
          neg_elem <- elements[grep("\\\\-\$", elements)][1]
          if (is.na(neg_elem)) neg_elem <- elements[2]
          if (is.na(neg_elem)) neg_elem <- pos_elem
          assign(neg_name, get(neg_elem, envir = segnf), envir = segnf)
        }
        
        # Ensure column names exist for grouping and labeling
        if (is.null(colnames(segnf[[pos_name]]@y))) {
          nc <- ncol(segnf[[pos_name]]@y)
          half <- ceiling(nc / 2)
          colnames(segnf[[pos_name]]@y) <- c(paste0("GroupA", 1:half), paste0("GroupB", 1:(nc - half)))
        }
        if (is.null(colnames(segnf[[neg_name]]@y))) {
          colnames(segnf[[neg_name]]@y) <- colnames(segnf[[pos_name]]@y)
        }
        
        # Determine coordinate range dynamically from the data
        x_vals <- segnf[[pos_name]]@x
        if (length(x_vals) > 0) {
          coord_range <- c(min(x_vals, na.rm = TRUE), max(x_vals, na.rm = TRUE))
        } else {
          coord_range <- c(1, 10000)
        }
        
        # Save GFF annotation for reference (kept filename for compatibility)
        write.csv(gffSub, "gff_scaled_annotation.csv", row.names = FALSE)
        
        # -----------------------------------------------------------------------------
        # Stage 2: Execute Documented Visualization Workflow
        # -----------------------------------------------------------------------------
        
        # 1. Plot expression data along the chromosome as a dot plot using plotAlongChrom
        pdf("plot1_dots_averaged.pdf", width = 10, height = 8)
        grid.newpage()
        plotAlongChrom(segnf, chr=chr_name, coord=coord_range, what="dots", gff=gffSub)
        dev.off()
        
        # 2. Plot separate dot plots for different conditions using the sepPlot parameter
        segObj = new.env(parent = baseenv())
        nmLabel = colnames(segnf[[pos_name]]@y)
        lab = gsub("\\\\d","",nmLabel)
        for(nm in c(pos_name, neg_name)){
            s = get(nm,env = segnf)
            rpY =  tapply(1:length(lab),lab,function(i)rowMeans(s@y[,i, drop=FALSE]))
            s@y = do.call(cbind,rpY)
            assign(nm,s,segObj)
        }
        pdf("plot2_dots_separated.pdf", width = 10, height = 8)
        grid.newpage()
        plotAlongChrom(segObj, chr=chr_name, coord=coord_range, what="dots", gff=gffSub, sepPlot = T)
        dev.off()
        
        # Save the constructed segObj environment
        saveRDS(segObj, "segObj.rds")
        
        # 3. Plot expression data as a heatmap using plotAlongChrom with what="heatmap"
        pdf("plot3_heatmap_rect.pdf", width = 10, height = 8)
        grid.newpage()
        plotAlongChrom(segnf, chr=chr_name, coord=coord_range, what="heatmap", gff=gffSub,
                 rowNamesHeatmap=nmLabel, makeRasterImage=FALSE)
        dev.off()
        
        # 4. Optimize heatmap rendering speed and color palettes using makeRasterImage and colHeatmap
        pdf("plot4_heatmap_raster.pdf", width = 10, height = 8)
        grid.newpage()
        plotAlongChrom(segnf, chr=chr_name, coord=coord_range, what="heatmap", gff=gffSub,
                 rowNamesHeatmap=nmLabel, makeRasterImage=TRUE)
        dev.off()
        
        pdf("plot5_heatmap_raster_blue.pdf", width = 10, height = 8)
        grid.newpage()
        plotAlongChrom(segnf, chr=chr_name, coord=coord_range, what="heatmap", gff=gffSub,
                 rowNamesHeatmap=nmLabel, makeRasterImage=TRUE,
                 colHeatmap = colorRamp(brewer.pal(9, "Blues")))
        dev.off()

    writeLines(c(
        '"BIOC_TILINGARRAY_ALONG_CHROMOSOME_VISUALIZATION":',
        paste0('    tilingArray: ', as.character(packageVersion('tilingArray')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_along_chromosome_visualization.csv versions.yml
    """
}

workflow BIOC_TILINGARRAY_ALONG_CHROMOSOME_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ segmentation_env.RData, gff_annotation.gff ] ]

    main:
    BIOC_TILINGARRAY_ALONG_CHROMOSOME_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_TILINGARRAY_ALONG_CHROMOSOME_VISUALIZATION.out.tables
    plots    = BIOC_TILINGARRAY_ALONG_CHROMOSOME_VISUALIZATION.out.plots
    objects  = BIOC_TILINGARRAY_ALONG_CHROMOSOME_VISUALIZATION.out.objects
    versions = BIOC_TILINGARRAY_ALONG_CHROMOSOME_VISUALIZATION.out.versions
}
