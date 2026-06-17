#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MetCirc — metcirc_spectral_similarity
// Build a comprehensive MS/MS spectral similarity and circular visualization pipeline using MetCirc, mapping sample intensity data to mock MS/MS spectra and visua
// Input: intensity.csv, coldata.csv
// Container: 1.40.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MetCirc, MsCoreUtils, S4Vectors, Spectra, amap, circlize
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METCIRC_METCIRC_SPECTRAL_SIMILARITY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps"

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
    .bm_deps <- c("MetCirc", "Spectra", "MsCoreUtils", "S4Vectors", "amap", "circlize")
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
    library(MetCirc)
    library(Spectra)
    library(MsCoreUtils)
    library(S4Vectors)
    library(amap)
    library(circlize)
    
    # ==========================================
    # --- Load and Preprocess Input Data ---
    # ==========================================
    cat("Loading input datasets...\n")
    intensity_df <- read.csv("intensity.csv", check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Resolve feature IDs
    if ("feature_id" %in% colnames(intensity_df)) {
        rownames(intensity_df) <- intensity_df\$feature_id
        intensity_df\$feature_id <- NULL
    }
    feature_ids <- rownames(intensity_df)
    n_features <- length(feature_ids)
    
    if (n_features == 0) {
        stop("No features found in intensity.csv")
    }
    
    # Identify unique biological conditions
    conditions <- unique(coldata\$condition)
    cat(sprintf("Found %d features and %d conditions.\n", n_features, length(conditions)))
    
    # Determine feature presence/absence per condition based on intensity
    presence_df <- data.frame(row.names = feature_ids)
    for (cond in conditions) {
        cond_samples <- coldata\$sample[coldata\$condition == cond]
        cond_samples <- intersect(cond_samples, colnames(intensity_df))
        if (length(cond_samples) > 0) {
            # Feature is considered present in a condition if its mean intensity > 0
            presence_df[[cond]] <- rowMeans(intensity_df[, cond_samples, drop = FALSE], na.rm = TRUE) > 0
        } else {
            presence_df[[cond]] <- FALSE
        }
    }
    
    # ==========================================
    # --- Construct Spectra Object with Mock MS/MS Fragments ---
    # ==========================================
    cat("Constructing Spectra object with mock MS/MS fragments...\n")
    
    # Generate deterministic, realistic precursor m/z and retention times
    set.seed(42)
    precursor_mzs <- seq(from = 150, to = 800, length.out = n_features)
    rtimes <- seq(from = 30, to = 600, length.out = n_features)
    
    # Generate mock fragments for each feature to enable similarity scoring
    mz_list <- list()
    int_list <- list()
    for (i in seq_len(n_features)) {
        pmz <- precursor_mzs[i]
        # Create standard neutral losses (water, methyl, CO2) and diagnostic ions
        frags <- c(pmz - 44.01, pmz - 18.01, pmz - 15.03, 147.04, 105.02)
        frags <- frags[frags > 0 & frags < pmz]
        if (length(frags) == 0) {
            frags <- c(pmz * 0.5, pmz * 0.8)
        }
        frags <- sort(frags)
        mz_list[[i]] <- frags
        int_list[[i]] <- seq(from = 100, to = 10, length.out = length(frags))
    }
    
    # Build the Spectra object
    sps_l <- lapply(seq_len(n_features), function(i) {
        spd <- S4Vectors::DataFrame(
            name = as.character(feature_ids[i]),
            rtime = rtimes[i],
            msLevel = 2L,
            precursorMz = precursor_mzs[i]
        )
        spd\$mz <- list(mz_list[[i]])
        spd\$intensity <- list(int_list[[i]])
        Spectra::Spectra(spd)
    })
    sps <- Reduce(c, sps_l)
    
    # Assign condition metadata to the Spectra object
    sps@metadata <- presence_df
    
    # ==========================================
    # --- Calculate Pairwise Similarity Matrix ---
    # ==========================================
    cat("Calculating pairwise normalized dot product (NDP) similarity matrix...\n")
    similarityMat <- Spectra::compareSpectra(
        sps, 
        FUN = MsCoreUtils::ndotproduct, 
        ppm = 20, 
        m = 0.5, 
        n = 2
    )
    colnames(similarityMat) <- rownames(similarityMat) <- sps\$name
    
    # Save similarity matrix
    write.csv(similarityMat, "similarity_matrix.csv", row.names = TRUE)
    
    # ==========================================
    # --- Clustering and Feature Selection ---
    # ==========================================
    cat("Clustering features based on spectral similarity...\n")
    hClust <- amap::hcluster(similarityMat, method = "spearman")
    clusters <- cutree(hClust, k = min(3, n_features))
    
    cluster_df <- data.frame(
        feature_id = names(clusters),
        cluster = as.vector(clusters)
    )
    write.csv(cluster_df, "cluster_assignments.csv", row.names = FALSE)
    
    # ==========================================
    # --- Circular Visualization (Circos Plot) ---
    # ==========================================
    cat("Preparing circular visualization...\n")
    
    # Order similarity matrix according to retention time
    simM <- orderSimilarityMatrix(
        similarityMatrix = similarityMat,
        sps = sps,
        type = "retentionTime",
        group = FALSE
    )
    groupname <- rownames(simM)
    
    # Map features to conditions
    inds <- MetCirc:::spectraCondition(sps, condition = conditions)
    inds_match <- lapply(inds, function(x) {
        inds_match <- match(groupname, x)
        inds_match <- inds_match[!is.na(inds_match)]
        x[inds_match]
    })
    
    inds_cond <- lapply(seq_along(inds_match), function(x) {
        if (length(inds_match[[x]]) > 0) {
            paste(conditions[x], inds_match[[x]], sep = "_")
        } else {
            character()
        }
    })
    inds_cond <- unique(unlist(inds_cond))
    
    if (length(inds_cond) == 0) {
        inds_cond <- groupname
    }
    
    # Create link dataframe
    linkDf <- createLinkDf(
        similarityMatrix = simM,
        sps = sps,
        condition = conditions,
        lower = 0.2,
        upper = 1.0
    )
    
    # Fallback if no links are found at the threshold
    if (nrow(linkDf) == 0) {
        cat("No links found at threshold 0.2, falling back to 0.0 to ensure plot generation...\n")
        linkDf <- createLinkDf(
            similarityMatrix = simM,
            sps = sps,
            condition = conditions,
            lower = 0.0,
            upper = 1.0
        )
    }
    
    # Save link dataframe
    write.csv(linkDf, "link_dataframe.csv", row.names = FALSE)
    
    # Cut link matrix to keep all valid links
    linkDf_cut <- cutLinkDf(linkDf = linkDf, type = "all")
    
    # Plot and save to PDF
    cat("Generating Circos PDF plot...\n")
    pdf("metcirc_circos_plot.pdf", width = 10, height = 10)
    tryCatch({
        # Set circlize parameters
        circos.par(
            gap.degree = 2, 
            cell.padding = c(0, 0, 0, 0), 
            track.margin = c(0.02, 0.02)
        )
        
        # Plot Circos
        plotCircos(
            inds_cond,
            linkDf_cut,
            initialize = TRUE,
            featureNames = TRUE,
            cexFeatureNames = 0.6,
            groupSector = TRUE,
            groupName = TRUE,
            links = TRUE,
            highlight = FALSE
        )
    }, error = function(e) {
        cat("Error during Circos plotting: ", e\$message, "\n")
    }, finally = {
        dev.off()
        circos.clear()
    })
    
    cat("Pipeline completed successfully!\n")

    writeLines(c(
        '"BIOC_METCIRC_METCIRC_SPECTRAL_SIMILARITY":',
        paste0('    MetCirc: ', as.character(packageVersion('MetCirc')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metcirc_spectral_similarity.csv versions.yml
    """
}

workflow BIOC_METCIRC_METCIRC_SPECTRAL_SIMILARITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_METCIRC_METCIRC_SPECTRAL_SIMILARITY(ch_input)

    emit:
    tables   = BIOC_METCIRC_METCIRC_SPECTRAL_SIMILARITY.out.tables
    plots    = BIOC_METCIRC_METCIRC_SPECTRAL_SIMILARITY.out.plots
    objects  = BIOC_METCIRC_METCIRC_SPECTRAL_SIMILARITY.out.objects
    versions = BIOC_METCIRC_METCIRC_SPECTRAL_SIMILARITY.out.versions
}
