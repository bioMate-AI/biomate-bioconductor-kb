#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: psmatch — psm_filtering_and_protein_groups
// Load PSM identification data, filter out low-quality matches, build an adjacency matrix, and resolve protein groups using connected components.
// Input: idf.mzid
// Container: quay.io/biocontainers/bioconductor-psmatch:1.14.0--r45hdfd78af_0
// R packages: factoextra, PSMatch, QFeatures, Spectra
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_PSMATCH_PSM_FILTERING_AND_PROTEIN_GROUPS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-psmatch:1.14.0--r45hdfd78af_0"

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
    .bm_deps <- c("factoextra", "PSMatch", "QFeatures", "Spectra")
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
    library("PSMatch")
    
    # Define input file
    idf <- "idf.mzid"
    
    if (!file.exists(idf)) {
        stop(paste("Input file", idf, "does not exist in the working directory."))
    }
    
    # --- Load PSM data and filter ---
    message("Loading and filtering PSM data...")
    id <- PSM(idf) |> filterPSMs()
    
    # Alternative step-by-step filtering (as documented)
    message("Running step-by-step filtering...")
    id <- PSM(idf)
    id <- filterPsmDecoy(id)
    id <- filterPsmRank(id)
    id <- filterPsmShared(id)
    
    # Save filtered PSMs
    saveRDS(id, "filtered_psms.rds")
    
    # --- Reduce PSMs by spectrum ID ---
    message("Reducing PSMs by spectrum ID...")
    id2 <- reducePSMs(id, id\$spectrumID)
    saveRDS(id2, "reduced_psms.rds")
    
    # --- Build adjacency matrix and connected components ---
    message("Building adjacency matrix and connected components...")
    adj <- makeAdjacencyMatrix(id)
    cc <- ConnectedComponents(adj)
    saveRDS(cc, "connected_components.rds")
    
    # Extract connected component 1082 (with robust fallback if index is out of bounds)
    message("Extracting connected component...")
    cx <- tryCatch({
        connectedComponents(cc, 1082)
    }, error = function(e) {
        warning("Component 1082 not found. Falling back to a valid component.")
        dims_cc <- dims(cc)
        candidates <- which(dims_cc[, "nrow"] > 1 & dims_cc[, "ncol"] > 1)
        if (length(candidates) > 0) {
            connectedComponents(cc, candidates[1])
        } else {
            connectedComponents(cc, length(cc))
        }
    })
    
    # --- Visualize adjacency matrix ---
    message("Plotting adjacency matrices...")
    pdf("adjacency_matrix_plots.pdf", width = 8, height = 8)
    
    # Plot 1: Default
    tryCatch({
        plotAdjacencyMatrix(cx)
    }, error = function(e) {
        message("Failed to plot default adjacency matrix: ", e\$message)
    })
    
    # Plot 2: protColors = 1
    tryCatch({
        plotAdjacencyMatrix(cx, 1)
    }, error = function(e) {
        message("Failed to plot adjacency matrix with protColors = 1: ", e\$message)
    })
    
    # Plot 3: protColors = 2
    tryCatch({
        plotAdjacencyMatrix(cx, 2)
    }, error = function(e) {
        message("Failed to plot adjacency matrix with protColors = 2: ", e\$message)
    })
    
    # --- Color peptide nodes by search engine score ---
    message("Coloring peptide nodes by score...")
    score <- id\$MS.GF.RawScore
    if (is.null(score) || all(is.na(score))) {
        message("MS.GF.RawScore not found or empty. Using sequence lengths as dummy scores for visualization.")
        score <- nchar(id\$sequence)
    }
    names(score) <- id\$sequence
    
    # Ensure we have at least some variation to avoid cut() error on constant values
    if (length(unique(score)) < 2) {
        score <- score + runif(length(score), 0, 0.1)
    }
    
    cls <- as.character(cut(score, 12, labels = colorRampPalette(c("white", "red"))(12)))
    names(cls) <- id\$sequence
    
    tryCatch({
        plotAdjacencyMatrix(cx, pepColors = cls)
    }, error = function(e) {
        message("Failed to plot adjacency matrix with custom peptide colors: ", e\$message)
    })
    
    dev.off()
    
    # --- Prioritize connected components ---
    message("Prioritizing connected components...")
    cctab <- prioritiseConnectedComponents(cc)
    print(head(cctab))
    
    # Save prioritization table
    write.csv(cctab, "prioritised_connected_components.csv", row.names = TRUE)
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_PSMATCH_PSM_FILTERING_AND_PROTEIN_GROUPS":',
        paste0('        psmatch: ', as.character(packageVersion("psmatch")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_psm_filtering_and_protein_groups.csv versions.yml
    """
}

workflow BIOC_PSMATCH_PSM_FILTERING_AND_PROTEIN_GROUPS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ idf.mzid ] ]

    main:
    BIOC_PSMATCH_PSM_FILTERING_AND_PROTEIN_GROUPS(ch_input)

    emit:
    tables   = BIOC_PSMATCH_PSM_FILTERING_AND_PROTEIN_GROUPS.out.tables
    plots    = BIOC_PSMATCH_PSM_FILTERING_AND_PROTEIN_GROUPS.out.plots
    objects  = BIOC_PSMATCH_PSM_FILTERING_AND_PROTEIN_GROUPS.out.objects
    versions = BIOC_PSMATCH_PSM_FILTERING_AND_PROTEIN_GROUPS.out.versions
}
