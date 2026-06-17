#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: satuRn — differential_transcript_usage_analysis
// Perform differential transcript usage (DTU) analysis on transcript-level expression data using quasi-binomial generalized linear models, followed by statistical
// Input: Tasic_counts_vignette, Tasic_metadata_vignette
// Container: quay.io/biocontainers/bioconductor-saturn:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: AnnotationHub, BiocParallel, DEXSeq, SummarizedExperiment, edgeR, ensembldb, ggplot2, limma, satuRn, stageR
// Visualizations: plot (ggplot/base)
// QC: filter low-expression genes
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import transcript-to-gene annotation
//  * 2. [Core Analysis] Data wrangling (formatting transcript/gene IDs, removing single-isoform genes)
//  * 3. [Core Analysis] Feature-level filtering (using edgeR::filterByExpr)
//  * 4. [Visualization & Output] Constructing a SummarizedExperiment object with design formula
//  * 5. [Core Analysis] Fitting quasi-binomial GLMs using fitDTU
//  * 6. [Core Analysis] Setting up a contrast matrix
//  * 7. [Core Analysis] Testing for DTU using testDTU
//  * 8. [Visualization & Output] Visualizing DTU using plotDTU
//  * 9. [Core Analysis] (Optional) Post-processing with stageR for gene-level FDR control

nextflow.enable.dsl = 2

process BIOC_SATURN_DIFFERENTIAL_TRANSCRIPT_USAGE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("satuRn", "AnnotationHub", "ensembldb", "edgeR", "ggplot2", "DEXSeq", "stageR", "SummarizedExperiment")
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
        
        # Load required libraries
        library(SummarizedExperiment)
        library(satuRn)
        library(AnnotationHub)
        library(ensembldb)
        library(edgeR)
        library(ggplot2)
        library(DEXSeq)
        library(stageR)
        
        # Helper function to robustly load user input files from the working directory
        load_input <- function(filename) {
          if (!file.exists(filename)) {
            exts <- c(".rds", ".csv", ".tsv", ".txt")
            found <- FALSE
            for (ext in exts) {
              if (file.exists(paste0(filename, ext))) {
                filename <- paste0(filename, ext)
                found <- TRUE
                break
              }
            }
            if (!found) {
              stop(paste("Required input file not found:", filename))
            }
          }
        
          if (grepl("\\\\.rds\$", filename, ignore.case = TRUE)) {
            return(readRDS(filename))
          } else if (grepl("\\\\.csv\$", filename, ignore.case = TRUE)) {
            return(read.csv(filename, row.names = 1, check.names = FALSE))
          } else if (grepl("\\\\.(tsv|txt)\$", filename, ignore.case = TRUE)) {
            return(read.delim(filename, row.names = 1, check.names = FALSE))
          } else {
            res <- tryCatch(readRDS(filename), error = function(e) NULL)
            if (!is.null(res)) return(res)
            res <- tryCatch(read.csv(filename, row.names = 1, check.names = FALSE), error = function(e) NULL)
            if (!is.null(res)) return(res)
            stop(paste("Could not parse file:", filename))
          }
        }
        
        # 1. Load User Input Data
        Tasic_counts_vignette <- as.matrix(load_input("Tasic_counts_vignette"))
        Tasic_metadata_vignette <- load_input("Tasic_metadata_vignette")
        
        # 2. Import transcript-to-gene annotation
        ah <- AnnotationHub() # load the annotation resource.
        
        # Infer organism from transcript IDs to avoid hardcoding
        sample_tx <- rownames(Tasic_counts_vignette)[1]
        if (grepl("^ENST", sample_tx)) {
            org <- "Homo sapiens"
        } else if (grepl("^ENSMUST", sample_tx)) {
            org <- "Mus musculus"
        } else if (grepl("^ENSRNOT", sample_tx)) {
            org <- "Rattus norvegicus"
        } else if (grepl("^ENSGART", sample_tx)) {
            org <- "Gallus gallus"
        } else if (grepl("^ENSDART", sample_tx)) {
            org <- "Danio rerio"
        } else {
            org <- "Mus musculus" # fallback
        }
        
        all <- query(ah, c("EnsDb", org))
        ahEdb <- all[[tail(names(all), 1)]] # dynamically get the latest release
        txs <- transcripts(ahEdb)
        
        # 3. Data wrangling
        txInfo <- as.data.frame(matrix(data = NA, nrow = length(txs), ncol = 2))
        colnames(txInfo) <- c("isoform_id", "gene_id")
        txInfo\$isoform_id <- txs\$tx_id
        txInfo\$gene_id <- txs\$gene_id
        rownames(txInfo) <- txInfo\$isoform_id
        
        rownames(Tasic_counts_vignette) <- sub("\\\\..*", "", 
                                               rownames(Tasic_counts_vignette)) 
        
        txInfo <- txInfo[txInfo\$isoform_id %in% rownames(Tasic_counts_vignette), ]
        txInfo <- subset(txInfo, 
                         duplicated(gene_id) | duplicated(gene_id, fromLast = TRUE))
        
        Tasic_counts_vignette <- Tasic_counts_vignette[which(
          rownames(Tasic_counts_vignette) %in% txInfo\$isoform_id), ]
          
        # Define group dynamically to avoid hardcoding specific metadata columns
        if (!"group" %in% colnames(Tasic_metadata_vignette)) {
            if (all(c("brain_region", "cluster") %in% colnames(Tasic_metadata_vignette))) {
                Tasic_metadata_vignette\$group <- paste(Tasic_metadata_vignette\$brain_region, 
                                                       Tasic_metadata_vignette\$cluster, 
                                                       sep = ".")
            } else {
                Tasic_metadata_vignette\$group <- Tasic_metadata_vignette[[1]]
            }
        }
        Tasic_metadata_vignette\$group <- make.names(as.character(Tasic_metadata_vignette\$group))
        
        # 4. Feature-level filtering
        filter_edgeR <- filterByExpr(Tasic_counts_vignette,
            design = NULL,
            group = Tasic_metadata_vignette\$group,
            lib.size = NULL,
            min.count = 10,
            min.total.count = 30,
            large.n = 20,
            min.prop = 0.7
        )
        
        table(filter_edgeR)
        Tasic_counts_vignette <- Tasic_counts_vignette[filter_edgeR, ]
        
        txInfo <- txInfo[which(
          txInfo\$isoform_id %in% rownames(Tasic_counts_vignette)), ]
        
        txInfo <- subset(txInfo, 
                         duplicated(gene_id) | duplicated(gene_id, fromLast = TRUE))
        Tasic_counts_vignette <- Tasic_counts_vignette[which(rownames(
          Tasic_counts_vignette) %in% txInfo\$isoform_id), ]
        
        txInfo <- txInfo[match(rownames(Tasic_counts_vignette), txInfo\$isoform_id), ]
        
        # 5. Construct SummarizedExperiment
        sumExp <- SummarizedExperiment::SummarizedExperiment(
            assays = list(counts = Tasic_counts_vignette),
            colData = Tasic_metadata_vignette,
            rowData = txInfo
        )
        
        metadata(sumExp)\$formula <- ~ 0 + as.factor(colData(sumExp)\$group)
        
        # 6. Fit quasi-binomial GLMs
        system.time({
        sumExp <- satuRn::fitDTU(
            object = sumExp,
            formula = ~ 0 + group,
            parallel = FALSE,
            BPPARAM = BiocParallel::bpparam(),
            verbose = TRUE
        )
        })
        
        # 7. Set up contrast matrix
        group <- as.factor(Tasic_metadata_vignette\$group)
        design <- model.matrix(~ 0 + group) # construct design matrix
        colnames(design) <- levels(group)
        
        lvl <- levels(group)
        if (length(lvl) >= 3) {
            contrast_exprs <- c(
                paste0(lvl[1], " - ", lvl[2]),
                paste0(lvl[1], " - ", lvl[3])
            )
        } else if (length(lvl) == 2) {
            contrast_exprs <- c(
                paste0(lvl[1], " - ", lvl[2])
            )
        } else {
            stop("At least two groups are required for contrasts.")
        }
        
        L <- limma::makeContrasts(contrasts = contrast_exprs, levels = design)
        colnames(L) <- paste0("Contrast", seq_len(ncol(L)))
        
        # 8. Test for DTU (capturing diagnostic plots to PDF)
        pdf("diagnostic_plots.pdf")
        sumExp <- satuRn::testDTU(
            object = sumExp,
            contrasts = L,
            diagplot1 = TRUE,
            diagplot2 = TRUE,
            sort = FALSE
        )
        dev.off()
        
        # Save test results to CSV dynamically
        for (i in seq_len(ncol(L))) {
            contrast_name <- colnames(L)[i]
            res_name <- paste0("fitDTUResult_", contrast_name)
            write.csv(as.data.frame(rowData(sumExp)[[res_name]]), paste0(res_name, ".csv"))
        }
        
        # 9. Visualize DTU
        group1 <- colnames(sumExp)[colData(sumExp)\$group == lvl[1]]
        group2 <- colnames(sumExp)[colData(sumExp)\$group == lvl[2]]
        
        # Dynamically select top significant transcripts from Contrast1
        res_c1 <- as.data.frame(rowData(sumExp)[["fitDTUResult_Contrast1"]])
        top_txs <- rownames(res_c1)[order(res_c1\$empirical_pval)][1:min(6, nrow(res_c1))]
        
        coef1 <- as.numeric(colnames(design) == lvl[1])
        coef2 <- as.numeric(colnames(design) == lvl[2])
        
        plots <- satuRn::plotDTU(
            object = sumExp,
            contrast = "Contrast1",
            groups = list(group1, group2),
            coefficients = list(coef1, coef2),
            summaryStat = "model",
            transcripts = top_txs,
            genes = NULL,
            top.n = 6
        )
        
        pdf("dtu_plots.pdf")
        for (i in seq_along(plots)) {
            current_plot <- plots[[i]] +
                scale_fill_manual(labels = c(lvl[1], lvl[2]), values = c("royalblue4", "firebrick")) +
                scale_x_discrete(labels = c(lvl[1], lvl[2]))
        
            print(current_plot)
        }
        dev.off()
        
        # 10. Post-processing with stageR for gene-level FDR control
        pvals <- rowData(sumExp)[["fitDTUResult_Contrast1"]]\$empirical_pval
        
        geneID <- factor(rowData(sumExp)\$gene_id)
        geneSplit <- split(seq(along = geneID), geneID)
        pGene <- sapply(geneSplit, function(i) min(pvals[i]))
        pGene[is.na(pGene)] <- 1
        theta <- unique(sort(pGene))
        
        q <- DEXSeq:::perGeneQValueExact(pGene, theta, geneSplit) 
        qScreen <- rep(NA_real_, length(pGene))
        qScreen <- q[match(pGene, theta)]
        qScreen <- pmin(1, qScreen)
        names(qScreen) <- names(geneSplit)
        
        tx2gene <- as.data.frame(rowData(sumExp)[c("isoform_id", "gene_id")])
        colnames(tx2gene) <- c("transcript", "gene")
        
        pConfirmation <- matrix(matrix(pvals),
            ncol = 1,
            dimnames = list(rownames(tx2gene), "transcript")
        )
        
        stageRObj <- stageR::stageRTx(
            pScreen = qScreen,
            pConfirmation = pConfirmation,
            pScreenAdjusted = TRUE,
            tx2gene = tx2gene
        )
        
        stageRObj <- stageR::stageWiseAdjustment(
            object = stageRObj,
            method = "dtu",
            alpha = 0.05,
            allowNA = TRUE
        )
        
        padj <- stageR::getAdjustedPValues(stageRObj,
            order = TRUE,
            onlySignificantGenes = FALSE
        )
        
        # Save final outputs
        write.csv(padj, "stageR_adjusted_pvals.csv", row.names = FALSE)
        saveRDS(sumExp, "satuRn_sumExp_result.rds")
        
        # Print session info
        sessionInfo()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # filter low-expression genes — alias of low-count filtering metric
    # (Chen 2016 F1000 edgeR filterByExpr semantics).
    .fleg_kept <- NA_real_; .fleg_files <- character(0)
    for (.fleg_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .fleg_obj <- tryCatch(readRDS(.fleg_rds), error = function(e) NULL)
      .fleg_mat <- if (is.matrix(.fleg_obj) || is.data.frame(.fleg_obj)) .fleg_obj else NULL
      if (!is.null(.fleg_mat) && nrow(.fleg_mat) > 100) {
        .fleg_m <- suppressWarnings(as.matrix(.fleg_mat))
        .fleg_rowmed <- suppressWarnings(apply(.fleg_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
        .fleg_kept <- sum(is.finite(.fleg_rowmed) & .fleg_rowmed >= 1) / nrow(.fleg_m)
        .fleg_files <- c(.fleg_files, .fleg_rds); break
      }
    }
    .gates_by_label[["filter low-expression genes"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = if (is.finite(.fleg_kept)) round(.fleg_kept, 4) else NA_real_,
      passes = isTRUE(is.finite(.fleg_kept) && .fleg_kept >= 0.3 && .fleg_kept <= 0.6),
      status = if (is.finite(.fleg_kept)) paste0("computed (median count >= 1 rows / total)")
               else "not_computed (no expression matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SATURN_DIFFERENTIAL_TRANSCRIPT_USAGE_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("filter low-expression genes"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SATURN_DIFFERENTIAL_TRANSCRIPT_USAGE_ANALYSIS":',
        paste0('    satuRn: ', as.character(packageVersion('satuRn')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_transcript_usage_analysis.csv versions.yml
    """
}

workflow BIOC_SATURN_DIFFERENTIAL_TRANSCRIPT_USAGE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Tasic_counts_vignette, Tasic_metadata_vignette ] ]

    main:
    BIOC_SATURN_DIFFERENTIAL_TRANSCRIPT_USAGE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SATURN_DIFFERENTIAL_TRANSCRIPT_USAGE_ANALYSIS.out.tables
    plots    = BIOC_SATURN_DIFFERENTIAL_TRANSCRIPT_USAGE_ANALYSIS.out.plots
    objects  = BIOC_SATURN_DIFFERENTIAL_TRANSCRIPT_USAGE_ANALYSIS.out.objects
    versions = BIOC_SATURN_DIFFERENTIAL_TRANSCRIPT_USAGE_ANALYSIS.out.versions
}
