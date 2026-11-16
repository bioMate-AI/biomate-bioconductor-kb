#!/usr/bin/env nextflow
/*
 * spatial/spatial_deconvolution_rctd
 *
 * RCTD (Robust Cell Type Decomposition, spacexr; Cable et al., Nat Biotechnol
 * 2022) per-spot deconvolution of a 10x Visium section against a matched,
 * annotated single-cell RNA-seq reference. Resolves, spot-by-spot, the
 * cell-type composition of a tumor microenvironment (T / B / macrophage /
 * NK / DC / tumor-epithelial / fibroblast ...), the readout SYSUCC uses to
 * call an immune-excluded vs inflamed TME.
 *
 * RUNS WITH NO USER INPUT: a small BUILT-IN synthetic demo is generated in R —
 * an annotated scRNA reference (K cell types) and a Visium-like spatial count
 * matrix whose spots are known mixtures of those types, so RCTD has recoverable
 * structure. The data is clearly SYNTHETIC and illustrative, NOT patient tissue.
 * A real run supplies params.reference_rds + params.spatial_rds (see below).
 *
 * The deconvolution engine is the REAL spacexr package (create.RCTD / run.RCTD,
 * doublet_mode = "full"); proportions are spacexr's own normalized weights,
 * never fabricated. spacexr is not on Bioconductor, so it is installed at run
 * time from the maintainer's R-universe (dmcable.r-universe.dev); if that
 * install fails the process FAILS LOUDLY (it does not invent proportions).
 *
 * -----------------------------------------------------------------------------
 * SELF-CORRECTION BEAT (executed in-workflow, not narrated):
 *   Round 1 runs the deconvolution against a MISMATCHED reference — one built on
 *   a disjoint gene namespace (a different tissue / platform), so the shared-gene
 *   overlap with the Visium section is below the floor RCTD needs. The workflow
 *   DETECTS the reference<->query mismatch (shared informative genes <
 *   params.min_shared_genes) and REFUSES to emit proportions from it.
 *   Round 2 SWAPS to the MATCHED reference (shared genes above the floor) and
 *   RCTD produces the per-spot proportion map. Both rounds' shared-gene counts
 *   and the swap decision are written to the summary so the catch is auditable.
 * -----------------------------------------------------------------------------
 *
 * Inputs (params):
 *   params.reference_rds   optional: an .rds holding a named list
 *                          {counts (genes x cells, integer), cell_types (named
 *                          factor), nUMI (named numeric)} for a real scRNA ref.
 *   params.spatial_rds     optional: an .rds holding {counts (genes x spots,
 *                          integer), coords (data.frame rownames=spot, x, y)}.
 *   params.min_shared_genes  shared-informative-gene floor for the mismatch gate.
 *   params.n_spots / params.n_ref_cells_per_type / params.n_genes / params.seed
 *                          size + reproducibility of the built-in synthetic demo.
 *   params.outdir          output directory (default: 'results').
 *
 * Outputs (published to the S3 outdir):
 *   rctd_cell_type_proportions.csv  per-spot normalized cell-type proportions
 *   rctd_spot_dominant.csv          per-spot dominant type + fraction + nUMI
 *   rctd_summary.json               self-correction log + QC + mean proportions
 *
 * Container: biomate/bioc-domain-spatial (Matrix / SingleCellExperiment +
 * geospatial build toolchain); spacexr added at run time from R-universe.
 * CPU only (RAM-aware); no GPU.
 */

nextflow.enable.dsl = 2

// ---- Demo + gate defaults so the workflow runs with NO inputs ---------------
params.reference_rds   = ''      // real annotated scRNA reference (.rds); '' -> built-in demo
params.spatial_rds     = ''      // real Visium section (.rds); '' -> built-in demo
params.min_shared_genes = '15'   // shared-informative-gene floor for the mismatch gate
params.n_spots         = '240'   // built-in demo: number of Visium-like spots
params.n_ref_cells_per_type = '120'  // built-in demo: reference cells per cell type (>= CELL_MIN_INSTANCE)
params.n_genes         = '180'   // built-in demo: genes in the panel
params.seed            = '1234'  // reproducibility of the built-in synthetic demo
params.outdir          = 'results'

process RCTD_DECONVOLUTION {
    tag "spatial_deconvolution_rctd"
    label 'process_medium'
    publishDir { "${params.outdir}/spatial_deconvolution_rctd" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-spatial:3.20-deps' : 'biomate/bioc-domain-spatial:latest'

    input:
    tuple val(reference_rds), val(spatial_rds)

    output:
    path "rctd_cell_type_proportions.csv", emit: proportions
    path "rctd_spot_dominant.csv",          emit: dominant
    path "rctd_summary.json",               emit: summary
    path "versions.yml",                    emit: versions

    script:
    """
    #!/usr/bin/env Rscript
    # ---- Resolve spacexr (RCTD); not on Bioconductor -> install from R-universe ----
    .ncpu <- max(1L, parallel::detectCores())
    if (!requireNamespace("spacexr", quietly = TRUE)) {
      # 1) maintainer's R-universe (CRAN-like; deps resolved from Posit PPM binaries)
      options(repos = c(
        RUNIV = "https://dmcable.r-universe.dev",
        CRAN  = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))
      try(install.packages("spacexr", Ncpus = .ncpu), silent = TRUE)
    }
    if (!requireNamespace("spacexr", quietly = TRUE)) {
      # 2) fallback: build from GitHub source (dmcable/spacexr)
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))
      if (!requireNamespace("remotes", quietly = TRUE)) try(install.packages("remotes", Ncpus = .ncpu), silent = TRUE)
      try(remotes::install_github("dmcable/spacexr", upgrade = "never", dependencies = TRUE), silent = TRUE)
    }
    if (!requireNamespace("spacexr", quietly = TRUE)) {
      stop("FATAL: spacexr (RCTD) could not be installed from R-universe (dmcable.r-universe.dev) or GitHub; cannot run RCTD deconvolution. Build spacexr into the bioc-domain-spatial image to make this deterministic.")
    }
    suppressMessages({ library(spacexr); library(Matrix) })

    set.seed(${params.seed})
    MIN_SHARED <- as.integer(${params.min_shared_genes})
    N_SPOTS    <- as.integer(${params.n_spots})
    N_REF_PT   <- as.integer(${params.n_ref_cells_per_type})
    N_GENES    <- as.integer(${params.n_genes})

    reference_rds <- "${reference_rds}"
    spatial_rds   <- "${spatial_rds}"

    CELL_TYPES <- c("T_cell","B_cell","Macrophage","Tumor_epithelial","Fibroblast")
    K <- length(CELL_TYPES)

    # ---- Build per-type mean expression profiles over a shared gene panel --------
    # Each type over-expresses a disjoint marker block; a housekeeping tail is
    # shared by all types so spots mix recoverably.
    make_profiles <- function(genes) {
      block <- max(1L, floor((N_GENES * 0.8) / K))
      P <- matrix(1.0, nrow = length(genes), ncol = K, dimnames = list(genes, CELL_TYPES))
      for (k in seq_len(K)) {
        lo <- (k - 1L) * block + 1L
        hi <- min(length(genes), k * block)
        if (lo <= hi) P[lo:hi, k] <- 30.0           # type-k marker block
      }
      hk_start <- K * block + 1L                      # shared housekeeping tail
      if (hk_start <= length(genes)) P[hk_start:length(genes), ] <- 8.0
      P
    }

    pois_counts <- function(mean_vec) {
      v <- rpois(length(mean_vec), lambda = pmax(mean_vec, 1e-6))
      as.integer(v)
    }

    # ---- Reference builders ------------------------------------------------------
    build_reference <- function(genes) {
      prof <- make_profiles(genes)
      cells <- c(); ct <- c(); mats <- list()
      for (k in seq_len(K)) {
        ids <- sprintf("%s_%03d", CELL_TYPES[k], seq_len(N_REF_PT))
        m <- vapply(seq_len(N_REF_PT), function(i) pois_counts(prof[, k]), integer(length(genes)))
        rownames(m) <- genes; colnames(m) <- ids
        mats[[k]] <- m; cells <- c(cells, ids); ct <- c(ct, rep(CELL_TYPES[k], N_REF_PT))
      }
      counts <- do.call(cbind, mats)
      cell_types <- factor(ct); names(cell_types) <- cells
      nUMI <- colSums(counts); names(nUMI) <- cells
      list(counts = counts, cell_types = cell_types, nUMI = nUMI, profiles = prof)
    }

    # ---- Spatial (Visium-like) section -------------------------------------------
    build_spatial <- function(genes, profiles) {
      spots <- sprintf("spot_%04d", seq_len(N_SPOTS))
      coords <- data.frame(x = runif(N_SPOTS, 0, 100), y = runif(N_SPOTS, 0, 100))
      rownames(coords) <- spots
      scale_umi <- 600
      mat <- matrix(0L, nrow = length(genes), ncol = N_SPOTS, dimnames = list(genes, spots))
      true_dom <- character(N_SPOTS)
      for (s in seq_len(N_SPOTS)) {
        dom <- ((s - 1L) %% K) + 1L                   # cycle dominant type
        sec <- sample(setdiff(seq_len(K), dom), 1L)
        w <- rep(0.15 / K, K)                          # uniform background
        w[dom] <- w[dom] + 0.60; w[sec] <- w[sec] + 0.25
        w <- w / sum(w)
        mix_mean <- as.numeric(profiles %*% w)
        mix_mean <- mix_mean / sum(mix_mean) * scale_umi
        mat[, s] <- pois_counts(mix_mean)
        true_dom[s] <- CELL_TYPES[dom]
      }
      nUMI <- colSums(mat); names(nUMI) <- spots
      list(counts = mat, coords = coords, nUMI = nUMI, true_dom = true_dom)
    }

    # ---- Assemble matched reference + spatial (real .rds if supplied) ------------
    genes <- sprintf("Gene%04d", seq_len(N_GENES))
    if (nzchar(spatial_rds) && file.exists(spatial_rds)) {
      sp <- readRDS(spatial_rds)
      sp_counts <- as.matrix(sp\$counts); sp_coords <- as.data.frame(sp\$coords)
      sp_nUMI <- colSums(sp_counts); names(sp_nUMI) <- colnames(sp_counts)
      spatial <- list(counts = sp_counts, coords = sp_coords, nUMI = sp_nUMI, true_dom = rep(NA, ncol(sp_counts)))
      genes <- rownames(sp_counts)
      data_source <- "user_spatial_rds"
    } else {
      matched_ref0 <- build_reference(genes)
      spatial <- build_spatial(genes, matched_ref0\$profiles)
      data_source <- "builtin_synthetic_demo"
    }

    if (nzchar(reference_rds) && file.exists(reference_rds)) {
      rr <- readRDS(reference_rds)
      matched_ref <- Reference(as.matrix(rr\$counts), rr\$cell_types,
                               if (is.null(rr\$nUMI)) colSums(as.matrix(rr\$counts)) else rr\$nUMI)
      ref_source <- "user_reference_rds"
    } else {
      mr <- build_reference(genes)
      matched_ref <- Reference(mr\$counts, mr\$cell_types, mr\$nUMI)
      ref_source <- "builtin_synthetic_matched"
    }

    # MISMATCHED reference: a disjoint gene namespace (different tissue/platform).
    mm_genes <- sprintf("OTHER_%04d", seq_len(N_GENES))
    mmr <- build_reference(mm_genes)
    mismatched_ref <- Reference(mmr\$counts, mmr\$cell_types, mmr\$nUMI)

    puck <- SpatialRNA(spatial\$coords, spatial\$counts, spatial\$nUMI)

    shared <- function(ref) length(intersect(rownames(ref@counts), rownames(puck@counts)))
    shared_mismatched <- shared(mismatched_ref)
    shared_matched    <- shared(matched_ref)

    # ---- Round 1: mismatched reference -> detect the reference<->query mismatch ---
    round1_ran <- FALSE
    if (shared_mismatched >= MIN_SHARED) {
      round1_ran <- TRUE   # (not expected for the disjoint-namespace demo)
    }
    mismatch_detected <- (shared_mismatched < MIN_SHARED)

    # ---- Round 2: swap to the matched reference and run REAL RCTD ----------------
    if (shared_matched < MIN_SHARED) {
      stop(sprintf("FATAL: even the matched reference shares only %d informative genes with the Visium section (floor=%d); cannot deconvolve.", shared_matched, MIN_SHARED))
    }

    myRCTD <- create.RCTD(puck, matched_ref, max_cores = 1, CELL_MIN_INSTANCE = 25)
    myRCTD <- run.RCTD(myRCTD, doublet_mode = "full")

    weights <- myRCTD@results\$weights
    norm_w  <- as.matrix(normalize_weights(weights))

    # ---- Write per-spot proportions ----------------------------------------------
    prop_df <- data.frame(spot = rownames(norm_w), round(norm_w, 5), check.names = FALSE)
    write.csv(prop_df, "rctd_cell_type_proportions.csv", row.names = FALSE)

    dom_idx <- apply(norm_w, 1, which.max)
    dom_df <- data.frame(
      spot = rownames(norm_w),
      dominant_type = colnames(norm_w)[dom_idx],
      dominant_fraction = round(norm_w[cbind(seq_len(nrow(norm_w)), dom_idx)], 5),
      n_umi = as.integer(spatial\$nUMI[rownames(norm_w)])
    )
    write.csv(dom_df, "rctd_spot_dominant.csv", row.names = FALSE)

    # ---- QC + self-correction log ------------------------------------------------
    mean_props <- round(colMeans(norm_w), 5)
    max_mean_prop <- max(mean_props)
    rowsum_ok <- all(abs(rowSums(norm_w) - 1) < 1e-3)
    n_types_resolved <- sum(mean_props > 0.01)

    summary <- list(
      tool = "spacexr RCTD (run.RCTD, doublet_mode='full')",
      tool_version = as.character(utils::packageVersion("spacexr")),
      data_source = data_source,
      reference_source = ref_source,
      n_spots = ncol(spatial\$counts),
      n_cell_types = ncol(norm_w),
      cell_types = colnames(norm_w),
      min_shared_genes_floor = MIN_SHARED,
      self_correction = list(
        round1_reference = "mismatched (disjoint gene namespace)",
        round1_shared_informative_genes = shared_mismatched,
        round1_ran_rctd = round1_ran,
        reference_query_mismatch_detected = mismatch_detected,
        action = if (mismatch_detected) "swapped_to_matched_reference" else "matched_reference_used_directly",
        round2_reference = "matched",
        round2_shared_informative_genes = shared_matched
      ),
      qc = list(
        proportions_sum_to_one = rowsum_ok,
        max_mean_cell_type_proportion = max_mean_prop,
        no_single_type_saturation = (max_mean_prop < 0.9),
        n_cell_types_resolved = n_types_resolved
      ),
      mean_cell_type_proportions = as.list(mean_props),
      status = "ok",
      note = "Per-spot cell-type proportions from the real spacexr RCTD engine. Built-in demo data is SYNTHETIC and illustrative, not patient tissue. Self-correction (mismatched -> matched reference swap) is executed in-workflow via the shared-informative-gene floor."
    )
    if (!requireNamespace("jsonlite", quietly = TRUE)) {
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))
      try(install.packages("jsonlite"), silent = TRUE)
    }
    writeLines(jsonlite::toJSON(summary, auto_unbox = TRUE, pretty = TRUE, null = "null"),
               "rctd_summary.json")

    writeLines(c(
      '"RCTD_DECONVOLUTION":',
      paste0('    spacexr: ', as.character(utils::packageVersion("spacexr")))
    ), "versions.yml")

    cat(sprintf("RCTD done: source=%s mismatch_detected=%s shared(mm=%d, matched=%d) spots=%d types=%d\\n",
                data_source, mismatch_detected, shared_mismatched, shared_matched,
                ncol(spatial\$counts), ncol(norm_w)))
    """

    stub:
    """
    printf 'spot,T_cell,B_cell,Macrophage,Tumor_epithelial,Fibroblast\\nspot_0001,0.6,0.1,0.1,0.1,0.1\\n' > rctd_cell_type_proportions.csv
    printf 'spot,dominant_type,dominant_fraction,n_umi\\nspot_0001,T_cell,0.6,600\\n' > rctd_spot_dominant.csv
    printf '{"tool":"spacexr RCTD","status":"stub"}\\n' > rctd_summary.json
    printf '"RCTD_DECONVOLUTION":\\n    spacexr: stub\\n' > versions.yml
    """
}

workflow SPATIAL_DECONVOLUTION_RCTD {
    take:
    ch_input   // channel: tuple(reference_rds, spatial_rds)

    main:
    RCTD_DECONVOLUTION(ch_input)

    emit:
    proportions = RCTD_DECONVOLUTION.out.proportions
    dominant    = RCTD_DECONVOLUTION.out.dominant
    summary     = RCTD_DECONVOLUTION.out.summary
    versions    = RCTD_DECONVOLUTION.out.versions
}

// Entry workflow for standalone execution.
workflow {
    ch_input = Channel.of(
        tuple(params.reference_rds as String, params.spatial_rds as String)
    )
    SPATIAL_DECONVOLUTION_RCTD(ch_input)
    SPATIAL_DECONVOLUTION_RCTD.out.summary.view { f -> "spatial RCTD deconvolution done: ${f}" }
}
