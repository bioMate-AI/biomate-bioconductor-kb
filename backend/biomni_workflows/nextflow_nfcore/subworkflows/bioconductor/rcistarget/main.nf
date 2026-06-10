#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RcisTarget — tfbs_motif_enrichment
// Identify enriched transcription factor binding motifs and predict candidate target genes from a gene list.
// Input: gene_list.txt, motif_rankings.db
// Container: quay.io/biocontainers/bioconductor-rcistarget:1.29.0--r45hdfd78af_0
// R packages: DT, RcisTarget, reshape2, visnetwork
// Bioconductor: 3.20 | R: 4.4
// Requires: RcisTarget
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Identify DNA motifs over-represented near the transcription start site (TSS) using the ranking database
//  * 2. [Core Analysis] Filter and retain motifs annotated to TFs with a high Normalized Enrichment Score (NES)
//  * 3. [Core Analysis] Predict candidate target genes ranked above the leading edge for each enriched motif

nextflow.enable.dsl = 2

process BIOC_RCISTARGET_TFBS_MOTIF_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("DT", "RcisTarget", "reshape2", "visnetwork")
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
            library(RcisTarget)
            
            # -----------------------------------------------------------------------------
            # Input Validation
            # -----------------------------------------------------------------------------
            if (!file.exists("gene_list.txt")) {
              stop("Error: Required input file 'gene_list.txt' not found in the working directory.")
            }
            
            if (!file.exists("motif_rankings.db")) {
              stop("Error: Required input file 'motif_rankings.db' not found in the working directory.")
            }
            
            # -----------------------------------------------------------------------------
            # Load User Inputs
            # -----------------------------------------------------------------------------
            # Read gene list (one gene symbol per line)
            gene_list_raw <- readLines("gene_list.txt")
            gene_list_clean <- unique(trimws(gene_list_raw))
            gene_list_clean <- gene_list_clean[gene_list_clean != ""]
            
            if (length(gene_list_clean) == 0) {
              stop("Error: 'gene_list.txt' is empty or contains no valid gene symbols.")
            }
            
            # RcisTarget functions expect a named list of gene sets
            geneLists <- list(query_gene_set = gene_list_clean)
            
            # Load the motif rankings database
            motifRankings <- importRankings("motif_rankings.db")
            
            # -----------------------------------------------------------------------------
            # Retrieve Motif Annotations (without using data() or system.file)
            # -----------------------------------------------------------------------------
            motifAnnot <- NULL
            tryCatch({
              # Attempt to retrieve standard HGNC annotations from the package environment
              pkg_env <- as.environment("package:RcisTarget")
              if (exists("motifAnnotations_hgnc", envir = pkg_env)) {
                motifAnnot <- get("motifAnnotations_hgnc", envir = pkg_env)
              } else if (exists("motifAnnotations_mgi", envir = pkg_env)) {
                motifAnnot <- get("motifAnnotations_mgi", envir = pkg_env)
              } else {
                # Fallback: search for any motif annotation object in the environment
                ns_objs <- ls(envir = pkg_env)
                annot_objs <- ns_objs[grep("motifAnnotations", ns_objs)]
                if (length(annot_objs) > 0) {
                  motifAnnot <- get(annot_objs[1], envir = pkg_env)
                }
              }
            }, error = function(e) {
              message("Warning: Could not load motif annotations from package environment: ", e\$message)
            })
            
            # Fallback to a minimal annotation structure if none could be loaded
            if (is.null(motifAnnot)) {
              warning("Using empty/placeholder motif annotations.")
              
              motif_names <- NULL
              if (.hasSlot(motifRankings, "rankings")) {
                rnk <- motifRankings@rankings
                motif_names <- rownames(rnk)
                if (is.null(motif_names) && length(rnk) > 0) {
                  motif_names <- rnk[[1]]
                }
              }
              
              if (is.null(motif_names)) {
                motif_names <- character(0)
              }
              
              motifAnnot <- data.frame(
                motif = as.character(motif_names),
                TF = "Unknown",
                directAnnotation = TRUE,
                stringsAsFactors = FALSE
              )
            }
            
            # -----------------------------------------------------------------------------
            # Stage 1: Identify DNA motifs over-represented near the TSS
            # -----------------------------------------------------------------------------
            message("Stage 1: Calculating Motif Enrichment (AUC)...")
            motifs_AUC <- calcAUC(
              geneSets = geneLists,
              rankings = motifRankings
            )
            
            # -----------------------------------------------------------------------------
            # Stage 2: Filter and retain motifs annotated to TFs with a high NES
            # -----------------------------------------------------------------------------
            message("Stage 2: Annotating motifs and filtering by NES...")
            motifEnrichmentTable <- addMotifAnnotation(
              auc = motifs_AUC,
              motifAnnot = motifAnnot
            )
            
            # -----------------------------------------------------------------------------
            # Stage 3: Predict candidate target genes ranked above the leading edge
            # -----------------------------------------------------------------------------
            message("Stage 3: Identifying leading edge target genes...")
            motifEnrichmentTable_wGenes <- addSignificantGenes(
              motifEnrichmentTable = motifEnrichmentTable,
              geneSets = geneLists,
              rankings = motifRankings,
              method = "aprox"
            )
            
            # -----------------------------------------------------------------------------
            # Save Outputs
            # -----------------------------------------------------------------------------
            message("Saving results...")
            
            # Save the complete R object
            saveRDS(motifEnrichmentTable_wGenes, "motif_enrichment_results.rds")
            
            # Flatten list columns for CSV export compatibility
            flat_table <- motifEnrichmentTable_wGenes
            for (col in colnames(flat_table)) {
              if (is.list(flat_table[[col]])) {
                flat_table[[col]] <- sapply(flat_table[[col]], function(x) paste(x, collapse = ";"))
              }
            }
            write.csv(flat_table, "motif_enrichment_results.csv", row.names = FALSE)
            
            # Generate diagnostic plot of NES scores
            pdf("nes_distribution.pdf", width = 7, height = 5)
            if ("NES" %in% colnames(motifEnrichmentTable_wGenes) && nrow(motifEnrichmentTable_wGenes) > 0) {
              hist(
                motifEnrichmentTable_wGenes\$NES,
                breaks = 30,
                col = "skyblue",
                border = "white",
                main = "Distribution of Normalized Enrichment Scores (NES)",
                xlab = "NES"
              )
              abline(v = 3.0, col = "red", lty = 2, lwd = 2)
              legend("topright", legend = "NES Threshold (3.0)", col = "red", lty = 2, lwd = 2)
            } else {
              plot(1, type = "n", axes = FALSE, xlab = "", ylab = "")
              text(1, 1, "No enriched motifs found or NES column missing.", cex = 1.2)
            }
            dev.off()
            
            message("Pipeline completed successfully. Outputs written to 'motif_enrichment_results.rds', 'motif_enrichment_results.csv', and 'nes_distribution.pdf'.")

    writeLines(c(
        '"BIOC_RCISTARGET_TFBS_MOTIF_ENRICHMENT":',
        paste0('    RcisTarget: ', as.character(packageVersion('RcisTarget')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tfbs_motif_enrichment.csv versions.yml
    """
}

workflow BIOC_RCISTARGET_TFBS_MOTIF_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_list.txt, motif_rankings.db ] ]

    main:
    BIOC_RCISTARGET_TFBS_MOTIF_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_RCISTARGET_TFBS_MOTIF_ENRICHMENT.out.tables
    plots    = BIOC_RCISTARGET_TFBS_MOTIF_ENRICHMENT.out.plots
    objects  = BIOC_RCISTARGET_TFBS_MOTIF_ENRICHMENT.out.objects
    versions = BIOC_RCISTARGET_TFBS_MOTIF_ENRICHMENT.out.versions
}
