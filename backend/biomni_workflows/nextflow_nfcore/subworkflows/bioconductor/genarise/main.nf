#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: genarise — dual_color_microarray_analysis
// Preprocess raw dual-color microarray data, perform background correction, normalize, filter low-quality spots, resolve replicates, and identify differentially e
// Input: raw_intensities.txt
// Container: quay.io/biocontainers/bioconductor-genarise:1.86.0--r45hdfd78af_0
// R packages: genArise
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENARISE_DUAL_COLOR_MICROARRAY_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-genarise:1.86.0--r45hdfd78af_0"

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
    .bm_deps <- c("genArise")
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
    
    # Load the genArise package
    library(genArise)
    
    # Define the input file name
    file.name <- "raw_intensities.txt"
    
    # 1. Read raw data using read.spot
    my.spot <- read.spot(file.name, cy3 = 1, cy5 = 2, bg.cy3 = 3, bg.cy5 = 4, ids = 5, header = FALSE, sep = "\t", is.ifc = FALSE)
    
    # Save the raw spot object
    saveRDS(my.spot, "raw_spot.rds")
    
    # Extract spot data for diagnostic plots
    datos <- attr(my.spot, "spotData")
    M <- log(datos\$Cy3, 2) - log(datos\$Cy5, 2)
    R <- log(datos\$BgCy3, 2)
    G <- log(datos\$BgCy5, 2)
    
    # Open PDF device to save diagnostic and Z-score plots
    pdf("diagnostic_and_zscore_plots.pdf")
    
    # Diagnostic plots using imageLimma
    tryCatch({
      imageLimma(z = M, row = 23, column = 24, meta.row = 2, meta.column = 2, low = NULL, high = NULL)
    }, error = function(e) {
      warning("imageLimma for M failed: ", e\$message)
    })
    
    tryCatch({
      imageLimma(z = R, row = 23, column = 24, meta.row = 2, meta.column = 2, low = "white", high = "red")
    }, error = function(e) {
      warning("imageLimma for R failed: ", e\$message)
    })
    
    tryCatch({
      imageLimma(z = G, row = 23, column = 24, meta.row = 2, meta.column = 2, low = "white", high = "green")
    }, error = function(e) {
      warning("imageLimma for G failed: ", e\$message)
    })
    
    # Diagnostic plots: ri.plot, ma.plot, cys.plot
    tryCatch({ ri.plot(my.spot) }, error = function(e) { warning("ri.plot failed: ", e\$message) })
    tryCatch({ ma.plot(my.spot) }, error = function(e) { warning("ma.plot failed: ", e\$message) })
    tryCatch({ cys.plot(my.spot) }, error = function(e) { warning("cys.plot failed: ", e\$message) })
    
    # 2. Perform background correction using bg.correct
    c.spot <- bg.correct(my.spot)
    saveRDS(c.spot, "background_corrected_spot.rds")
    write.csv(attr(c.spot, "spotData"), "background_corrected_data.csv", row.names = FALSE)
    
    # 3. Normalize data using grid.norm and global.norm
    # Grid normalization
    tryCatch({
      n.spot_grid <- grid.norm(mySpot = my.spot, nr = 23, nc = 24)
      saveRDS(n.spot_grid, "grid_normalized_spot.rds")
    }, error = function(e) {
      warning("grid.norm failed: ", e\$message)
    })
    
    # Global normalization
    n.spot <- global.norm(mySpot = my.spot)
    saveRDS(n.spot, "global_normalized_spot.rds")
    write.csv(attr(n.spot, "spotData"), "global_normalized_data.csv", row.names = FALSE)
    
    # 4. Filter low-quality spots using filter.spot
    f.spot <- filter.spot(mySpot = my.spot)
    saveRDS(f.spot, "filtered_spot.rds")
    write.csv(attr(f.spot, "spotData"), "filtered_data.csv", row.names = FALSE)
    
    # 5. Handle replicate spots using spotUnique, alter.unique, and meanUnique
    u.spot_unique <- spotUnique(mySpot = my.spot)
    saveRDS(u.spot_unique, "unique_spot.rds")
    
    u.spot_alter <- alter.unique(mySpot = my.spot)
    saveRDS(u.spot_alter, "alter_unique_spot.rds")
    
    u.spot <- meanUnique(mySpot = my.spot)
    saveRDS(u.spot, "mean_unique_spot.rds")
    write.csv(attr(u.spot, "spotData"), "mean_unique_data.csv", row.names = FALSE)
    
    # 6. Calculate Z-scores using Zscore
    s.spot_ri <- Zscore(my.spot, type="ri")
    saveRDS(s.spot_ri, "zscore_ri_dataset.rds")
    
    s.spot <- Zscore(my.spot, type="ma")
    saveRDS(s.spot, "zscore_ma_dataset.rds")
    
    # 7. Plot Z-score plots using Zscore.plot
    tryCatch({
      Zscore.plot(s.spot_ri, Zscore.min=1)
    }, error = function(e) {
      warning("Zscore.plot for RI failed: ", e\$message)
    })
    
    tryCatch({
      Zscore.plot(s.spot, Zscore.min=1)
    }, error = function(e) {
      warning("Zscore.plot for MA failed: ", e\$message)
    })
    
    # Close PDF device
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_GENARISE_DUAL_COLOR_MICROARRAY_ANALYSIS":
        genarise: \$(Rscript -e 'cat(as.character(packageVersion("genarise")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dual_color_microarray_analysis.csv versions.yml
    """
}

workflow BIOC_GENARISE_DUAL_COLOR_MICROARRAY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_intensities.txt ] ]

    main:
    BIOC_GENARISE_DUAL_COLOR_MICROARRAY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GENARISE_DUAL_COLOR_MICROARRAY_ANALYSIS.out.tables
    plots    = BIOC_GENARISE_DUAL_COLOR_MICROARRAY_ANALYSIS.out.plots
    objects  = BIOC_GENARISE_DUAL_COLOR_MICROARRAY_ANALYSIS.out.objects
    versions = BIOC_GENARISE_DUAL_COLOR_MICROARRAY_ANALYSIS.out.versions
}
