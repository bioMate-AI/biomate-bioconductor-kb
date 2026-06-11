#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mastR — standard_signature_refinement
// Generate and refine a group-specific gene signature from a single transcriptomics dataset, including background tissue expression removal and visualization.
// Input: user_expression_data.RData, user_background_data.RData
// Container: quay.io/biocontainers/bioconductor-mastr:1.10.2--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GSEABase, edgeR, ggplot2, limma, mastR, org.Hs.eg.db
// Visualizations: plot (ggplot/base)
// QC: low-count filtering, missing-value handling, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Build a markers pool from public or customized sources using get_lm_sig(), get_gsc_sig(), and merge_markers(). 2. Pre-process the 

nextflow.enable.dsl = 2

process BIOC_MASTR_STANDARD_SIGNATURE_REFINEMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(mastR)
    library(edgeR)
    library(ggplot2)
    library(GSEABase)
    library(limma)
    library(org.Hs.eg.db)
    
    # ==========================================
    # STEP 1: Build Markers Pool from Package Reference Data
    # ==========================================
    
    # Retrieve reference datasets directly from the package namespace
    lm7 <- mastR::lm7
    lm22 <- mastR::lm22
    LM <- get_lm_sig(lm7.pattern = "^NK", lm22.pattern = "NK cells")
    
    msigdb_gobp_nk <- mastR::msigdb_gobp_nk
    MSig <- get_gsc_sig(
      gsc = msigdb_gobp_nk,
      pattern = "NATURAL_KILLER_CELL_MEDIATED"
    )
    MSig <- merge_markers(MSig)
    setName(MSig) <- "MSigDB"
    
    nk_markers <- mastR::nk_markers
    nk_m <- GeneSet(nk_markers\$HGNC_Symbol,
      geneIdType = SymbolIdentifier(),
      setName = "NK_markers"
    )
    gsc <- GeneSetCollection(c(nk_m, LM, MSig))
    Markers <- merge_markers(gsc)
    
    # ==========================================
    # STEP 2: Load and Adapt User Expression Data
    # ==========================================
    
    if (!file.exists("user_expression_data.RData")) {
      stop("Required input file 'user_expression_data.RData' not found in the working directory.")
    }
    
    # Load user expression data into a temporary environment to avoid collisions
    env_expr <- new.env()
    load("user_expression_data.RData", envir = env_expr)
    loaded_expr_names <- ls(env_expr)
    
    im_data_6 <- NULL
    for (obj_name in loaded_expr_names) {
      obj <- env_expr[[obj_name]]
      if (inherits(obj, "ExpressionSet") || is.matrix(obj) || inherits(obj, "DGEList")) {
        im_data_6 <- obj
        break
      }
    }
    
    if (is.null(im_data_6)) {
      stop("Could not find a valid ExpressionSet, matrix, or DGEList in 'user_expression_data.RData'.")
    }
    
    # Adapt the user's expression data structure to match the expected "celltype:ch1" column and "NK" target group
    if (inherits(im_data_6, "ExpressionSet")) {
      pdata <- Biobase::pData(im_data_6)
      nk_col <- NULL
      for (col in colnames(pdata)) {
        if (any(pdata[[col]] %in% c("NK", "NK cells", "Natural Killer"), na.rm = TRUE)) {
          nk_col <- col
          break
        }
      }
      if (!is.null(nk_col)) {
        pdata[["celltype:ch1"]] <- as.character(pdata[[nk_col]])
        pdata[["celltype:ch1"]][pdata[["celltype:ch1"]] %in% c("NK cells", "Natural Killer")] <- "NK"
      } else {
        stop("Target group 'NK' (or 'NK cells', 'Natural Killer') not found in the user expression data.")
      }
      Biobase::pData(im_data_6) <- pdata
    } else if (inherits(im_data_6, "DGEList")) {
      pdata <- im_data_6\$samples
      nk_col <- NULL
      for (col in colnames(pdata)) {
        if (any(pdata[[col]] %in% c("NK", "NK cells", "Natural Killer"), na.rm = TRUE)) {
          nk_col <- col
          break
        }
      }
      if (!is.null(nk_col)) {
        im_data_6\$samples[["celltype:ch1"]] <- as.character(pdata[[nk_col]])
        im_data_6\$samples[["celltype:ch1"]][im_data_6\$samples[["celltype:ch1"]] %in% c("NK cells", "Natural Killer")] <- "NK"
      } else {
        stop("Target group 'NK' (or 'NK cells', 'Natural Killer') not found in the user expression data.")
      }
    } else if (is.matrix(im_data_6)) {
      stop("Expression data provided as a matrix lacks metadata. Please provide an ExpressionSet or DGEList containing group labels with an 'NK' group.")
    }
    
    # Determine if user data uses ENSEMBL or SYMBOL
    if (inherits(im_data_6, "ExpressionSet")) {
      feature_names <- rownames(Biobase::exprs(im_data_6))
    } else if (inherits(im_data_6, "DGEList")) {
      feature_names <- rownames(im_data_6\$counts)
    } else {
      feature_names <- rownames(im_data_6)
    }
    
    is_ensembl <- any(grepl("^ENSG[0-9]+", head(feature_names)))
    user_gene_id <- if (is_ensembl) "ENSEMBL" else "SYMBOL"
    
    # ==========================================
    # STEP 3: Process Data and Select Group-Specific Signature
    # ==========================================
    
    proc_data <- process_data(
      data = im_data_6,
      group_col = "celltype:ch1",
      target_group = "NK",
      markers = geneIds(Markers),
      gene_id = user_gene_id
    )
    proc_data\$voomE <- proc_data\$vfit\$E
    
    set.seed(123)
    sig_ct <- select_sig(proc_data, feature_selection = "auto")
    
    if (user_gene_id == "ENSEMBL") {
      deg_up <- mapIds(
        org.Hs.eg.db::org.Hs.eg.db,
        geneIds(sig_ct[["UP"]]),
        "SYMBOL", "ENSEMBL"
      )
      deg_up <- na.omit(deg_up)
    } else {
      deg_up <- geneIds(sig_ct[["UP"]])
      names(deg_up) <- deg_up
    }
    
    m_ct <- intersect(geneIds(Markers), deg_up)
    names(m_ct) <- names(deg_up)[match(m_ct, deg_up)]
    
    # ==========================================
    # STEP 4: Load and Adapt User Background Data
    # ==========================================
    
    if (!file.exists("user_background_data.RData")) {
      stop("Required input file 'user_background_data.RData' not found in the working directory.")
    }
    
    env_bg <- new.env()
    load("user_background_data.RData", envir = env_bg)
    loaded_bg_names <- ls(env_bg)
    
    user_background_data <- NULL
    for (obj_name in loaded_bg_names) {
      obj <- env_bg[[obj_name]]
      if (is.matrix(obj) || inherits(obj, "DGEList") || inherits(obj, "ExpressionSet")) {
        user_background_data <- obj
        break
      }
    }
    
    if (is.null(user_background_data)) {
      stop("Could not find a valid matrix, DGEList, or ExpressionSet in 'user_background_data.RData'.")
    }
    
    if (inherits(user_background_data, "ExpressionSet")) {
      user_background_data <- Biobase::exprs(user_background_data)
    } else if (inherits(user_background_data, "DGEList")) {
      user_background_data <- edgeR::cpm(user_background_data, log = TRUE)
    }
    
    if (max(user_background_data, na.rm = TRUE) > 100) {
      user_background_data <- log2(user_background_data + 1)
    }
    
    # Construct ccle_crc_5 structure to match the documented code's expectations
    ccle_crc_5 <- list(
      counts = user_background_data,
      samples = data.frame(
        cancer = rep("CRC", ncol(user_background_data)),
        row.names = colnames(user_background_data),
        stringsAsFactors = FALSE
      )
    )
    
    # ==========================================
    # STEP 5: Filter Background Expression and Refine Signature
    # ==========================================
    
    bg_mat <- ccle_crc_5\$counts[, ccle_crc_5\$samples\$cancer == "CRC", drop = FALSE]
    sig_mat <- proc_data\$voomE[, proc_data\$samples\$celltype.ch1 == "NK", drop = FALSE]
    
    keep_threshold <- min(2, ncol(bg_mat) - 1)
    keep <- rowSums(bg_mat > 1, na.rm = TRUE) > keep_threshold
    bg_mat <- bg_mat[keep, , drop = FALSE]
    
    bg_is_ensembl <- any(grepl("^ENSG[0-9]+", head(rownames(bg_mat))))
    bg_gene_id <- if (bg_is_ensembl) "ENSEMBL" else "SYMBOL"
    
    m_ccl <- remove_bg_exp_mat(
      sig_mat = sig_mat,
      bg_mat = bg_mat,
      markers = geneIds(Markers),
      gene_id = c(user_gene_id, bg_gene_id)
    )
    
    sig_NK_CRC <- intersect(m_ct, m_ccl)
    
    # ==========================================
    # STEP 6: Save Outputs
    # ==========================================
    
    # Save the final refined signature to CSV and RDS
    write.csv(data.frame(Gene = sig_NK_CRC), "final_refined_signature.csv", row.names = FALSE)
    saveRDS(sig_NK_CRC, "final_refined_signature.rds")
    
    # ==========================================
    # STEP 7: Visualization
    # ==========================================
    
    tryCatch({
      pdf("signature_refinement_plots.pdf", width = 10, height = 8)
      
      # Heatmap
      sig_heatmap(
        data = proc_data,
        sigs = sig_NK_CRC,
        group_col = "celltype.ch1",
        markers = geneIds(Markers),
        gene_id = user_gene_id,
        slot = "voomE",
        scale = "row",
        show_column_den = FALSE,
        show_row_den = FALSE,
        show_column_names = FALSE,
        show_row_names = FALSE
      )
      
      # Boxplot
      p_box <- sig_boxplot(
        data = proc_data,
        sigs = sig_NK_CRC,
        group_col = "celltype.ch1",
        target_group = "NK",
        gene_id = user_gene_id,
        slot = "voomE"
      )
      print(p_box)
      
      # Scatter Plot
      p_scatter <- sig_scatter_plot(
        data = proc_data,
        sigs = sig_NK_CRC,
        group_col = "celltype.ch1",
        target_group = "NK",
        gene_id = user_gene_id,
        slot = "voomE"
      )
      print(p_scatter)
      
      # GSEA Plot
      p_gsea <- sig_gseaplot(
        data = proc_data,
        sigs = list(sig = sig_NK_CRC, markers = geneIds(Markers)),
        group_col = "celltype.ch1",
        target_group = "NK",
        gene_id = user_gene_id,
        slot = "voomE",
        method = "gseaplot"
      )
      if (!is.null(p_gsea)) print(p_gsea)
      
      dev.off()
    }, error = function(e) {
      warning("An error occurred during visualization: ", e\$message)
      if (names(dev.cur()) != "null device") dev.off()
    })

    writeLines(c(
        '"BIOC_MASTR_STANDARD_SIGNATURE_REFINEMENT":',
        paste0('    mastR: ', as.character(packageVersion('mastR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_signature_refinement.csv versions.yml
    """
}

workflow BIOC_MASTR_STANDARD_SIGNATURE_REFINEMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_expression_data.RData, user_background_data.RData ] ]

    main:
    BIOC_MASTR_STANDARD_SIGNATURE_REFINEMENT(ch_input)

    emit:
    tables   = BIOC_MASTR_STANDARD_SIGNATURE_REFINEMENT.out.tables
    plots    = BIOC_MASTR_STANDARD_SIGNATURE_REFINEMENT.out.plots
    objects  = BIOC_MASTR_STANDARD_SIGNATURE_REFINEMENT.out.objects
    versions = BIOC_MASTR_STANDARD_SIGNATURE_REFINEMENT.out.versions
}
