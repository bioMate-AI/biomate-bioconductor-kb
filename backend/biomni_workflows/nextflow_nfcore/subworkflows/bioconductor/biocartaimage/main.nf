#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BioCartaImage — biocarta_pathway_imaging
// Map microscopy image intensities to BioCarta pathway genes and generate customized pathway visualizations.
// Input: image.tif
// Container: 1.8.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BioCartaImage, EBImage
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOCARTAIMAGE_BIOCARTA_PATHWAY_IMAGING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20-deps"

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
    .bm_deps <- c("BioCartaImage")
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
    
    # --- Load required libraries ---
    library(BioCartaImage)
    library(grid)
    if (!requireNamespace("EBImage", quietly = TRUE)) {
        stop("EBImage package is required to read the input microscopy image.")
    }
    
    # --- Read and process the input microscopy image ---
    message("Reading input microscopy image...")
    img <- EBImage::readImage("image.tif")
    img_arr <- as.array(img)
    
    # Handle multi-channel or 3D images by extracting the first channel/slice
    if (length(dim(img_arr)) >= 3) {
        img_mat <- img_arr[, , 1]
    } else {
        img_mat <- img_arr
    }
    
    # --- Retrieve BioCarta Pathway Information ---
    pathway_id <- "h_RELAPathway"
    message(paste("Retrieving pathway information for:", pathway_id))
    p <- get_pathway(pathway_id)
    genes <- genes_in_pathway(p)
    
    if (length(genes) == 0) {
        stop("No genes found in the specified pathway.")
    }
    
    # --- Map Image Intensities to Pathway Genes ---
    # Divide the microscopy image into sub-regions to simulate distinct gene expression levels
    dims <- dim(img_mat)
    rows <- seq(1, dims[1], length.out = 5)
    cols <- seq(1, dims[2], length.out = 5)
    intensities <- numeric(length(genes))
    
    idx <- 1
    for (i in 1:4) {
        for (j in 1:4) {
            if (idx <= length(genes)) {
                sub_img <- img_mat[rows[i]:rows[i+1], cols[j]:cols[j+1]]
                intensities[idx] <- mean(sub_img, na.rm = TRUE)
                idx <- idx + 1
            }
        }
    }
    
    # Fill any remaining genes with the global mean intensity
    if (idx <= length(genes)) {
        intensities[idx:length(genes)] <- mean(img_mat, na.rm = TRUE)
    }
    
    names(intensities) <- genes
    
    # Normalize intensities to [0, 1] for color mapping
    min_val <- min(intensities, na.rm = TRUE)
    max_val <- max(intensities, na.rm = TRUE)
    range_val <- max_val - min_val
    if (range_val == 0) range_val <- 1
    
    norm_intensities <- (intensities - min_val) / range_val
    
    # Create a color palette (yellow to red) representing expression intensity
    col_fun <- colorRamp(c("yellow", "red"))
    gene_colors <- rgb(col_fun(norm_intensities), maxColorValue = 255)
    names(gene_colors) <- genes
    
    # Save the mapping to a CSV file
    df_out <- data.frame(
        Entrez_ID = genes,
        Simulated_Intensity = intensities,
        Normalized_Intensity = norm_intensities,
        Assigned_Color = gene_colors,
        stringsAsFactors = FALSE
    )
    write.csv(df_out, "gene_pathway_mapping.csv", row.names = FALSE)
    message("Saved gene-to-pathway mapping to gene_pathway_mapping.csv")
    
    # --- Standard Pathway Visualization ---
    message("Generating standard pathway visualization...")
    pdf("biocarta_pathway_analysis.pdf", width = 10, height = 10)
    grid.newpage()
    grid.biocarta(pathway_id, color = gene_colors)
    dev.off()
    message("Saved standard pathway visualization to biocarta_pathway_analysis.pdf")
    
    # --- Advanced Custom Pathway Visualization ---
    message("Generating advanced custom pathway visualization...")
    pdf("biocarta_custom_annotations.pdf", width = 10, height = 10)
    grid.newpage()
    
    # Create the base BioCarta grob
    grob <- biocartaGrob(pathway_id)
    
    # Add custom annotations (colored circles representing intensity) to the left of each gene
    for (gene in genes) {
        val <- norm_intensities[gene]
        col <- gene_colors[gene]
        
        # Use tryCatch to handle any genes that might fail to map to coordinates
        grob <- tryCatch({
            mark_gene(grob, gene, function(x, y) {
                pos <- pos_by_polygon(x, y, where = "left")
                # Draw a custom circle indicator next to the gene node
                circleGrob(
                    x = pos[1] - 8, 
                    y = pos[2], 
                    r = 6 * val + 3, 
                    default.units = "native",
                    gp = gpar(fill = col, col = "black", lwd = 1.5)
                )
            })
        }, error = function(e) {
            warning(paste("Could not mark gene:", gene, "-", e\$message))
            grob
        })
    }
    
    grid.draw(grob)
    dev.off()
    message("Saved advanced custom pathway visualization to biocarta_custom_annotations.pdf")

    writeLines(c(
        '"BIOC_BIOCARTAIMAGE_BIOCARTA_PATHWAY_IMAGING":',
        paste0('    BioCartaImage: ', as.character(packageVersion('BioCartaImage')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biocarta_pathway_imaging.csv versions.yml
    """
}

workflow BIOC_BIOCARTAIMAGE_BIOCARTA_PATHWAY_IMAGING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BIOCARTAIMAGE_BIOCARTA_PATHWAY_IMAGING(ch_input)

    emit:
    tables   = BIOC_BIOCARTAIMAGE_BIOCARTA_PATHWAY_IMAGING.out.tables
    plots    = BIOC_BIOCARTAIMAGE_BIOCARTA_PATHWAY_IMAGING.out.plots
    objects  = BIOC_BIOCARTAIMAGE_BIOCARTA_PATHWAY_IMAGING.out.objects
    versions = BIOC_BIOCARTAIMAGE_BIOCARTA_PATHWAY_IMAGING.out.versions
}
