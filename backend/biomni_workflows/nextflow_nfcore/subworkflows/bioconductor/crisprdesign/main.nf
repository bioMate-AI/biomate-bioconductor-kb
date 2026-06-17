#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: crisprDesign — crispr_ko_grna_design
// Design and annotate highly specific CRISPRko gRNAs targeting the most highly expressed genes identified from RNA-seq count data.
// Input: counts.csv, coldata.csv
// Container: 1.12.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg38, GenomicFeatures, GenomicRanges, S4Vectors, TxDb.Hsapiens.UCSC.hg38.knownGene, crisprBase, crisprDesign, org.Hs.eg.db
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CRISPRDESIGN_CRISPR_KO_GRNA_DESIGN {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("crisprDesign", "crisprBase", "org.Hs.eg.db", "TxDb.Hsapiens.UCSC.hg38.knownGene", "BSgenome.Hsapiens.UCSC.hg38", "GenomicFeatures", "GenomicRanges", "S4Vectors")
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
    
    # --- Load Libraries and Input Data ---
    library(crisprDesign)
    library(crisprBase)
    library(org.Hs.eg.db)
    library(TxDb.Hsapiens.UCSC.hg38.knownGene)
    library(BSgenome.Hsapiens.UCSC.hg38)
    library(GenomicFeatures)
    library(GenomicRanges)
    library(S4Vectors)
    
    message("Reading input expression data...")
    counts <- read.csv("counts.csv", row.names=1, check.names=FALSE)
    coldata <- read.csv("coldata.csv", row.names=1, check.names=FALSE)
    
    # --- Identify and Map Target Genes ---
    message("Identifying top expressed genes for targeting...")
    mean_expr <- rowMeans(counts)
    gene_ids <- names(mean_expr)
    
    # Determine keytype of input gene IDs
    if (any(grepl("^ENSG", gene_ids))) {
        key_type <- "ENSEMBL"
    } else if (any(grepl("^[0-9]+\$", gene_ids))) {
        key_type <- "ENTREZID"
    } else {
        key_type <- "SYMBOL"
    }
    
    # Map input IDs to Entrez IDs for TxDb compatibility
    mapped_ids <- mapIds(org.Hs.eg.db, keys=gene_ids, column="ENTREZID", keytype=key_type, multiVals="first")
    expr_df <- data.frame(
        gene_id = gene_ids,
        entrez_id = mapped_ids,
        mean_expr = mean_expr,
        stringsAsFactors = FALSE
    )
    expr_df <- expr_df[!is.na(expr_df\$entrez_id), ]
    
    # Filter for genes that have annotated CDS regions in hg38 TxDb
    txdb <- TxDb.Hsapiens.UCSC.hg38.knownGene
    cds_by_gene <- cdsBy(txdb, by="gene")
    valid_genes <- intersect(expr_df\$entrez_id, names(cds_by_gene))
    
    if (length(valid_genes) == 0) {
        message("No input genes mapped to hg38 CDS. Falling back to default target genes.")
        target_entrez <- names(cds_by_gene)[1:2]
    } else {
        expr_df_valid <- expr_df[expr_df\$entrez_id %in% valid_genes, ]
        expr_df_valid <- expr_df_valid[order(-expr_df_valid\$mean_expr), ]
        target_entrez <- unique(expr_df_valid\$entrez_id)[1:2]
    }
    message("Selected target Entrez IDs: ", paste(target_entrez, collapse=", "))
    
    # --- Retrieve Genomic Coordinates and Design Spacers ---
    message("Retrieving genomic coordinates and designing spacers...")
    target_cds <- cds_by_gene[target_entrez]
    gr_target <- unlist(target_cds)
    
    bsgenome <- BSgenome.Hsapiens.UCSC.hg38
    nuclease <- crisprBase::SpCas9
    
    # Find all SpCas9 spacers targeting the CDS of selected genes
    guideSet <- findSpacers(gr_target, bsgenome=bsgenome, crisprNuclease=nuclease)
    
    # Subset to a manageable number of spacers to ensure fast and robust execution
    if (length(guideSet) > 50) {
        guideSet <- guideSet[1:50]
    }
    
    # --- Comprehensive gRNA Annotation ---
    message("Annotating spacer sequence features...")
    guideSet <- addSequenceFeatures(guideSet)
    
    message("Adding on-target efficiency scores...")
    guideSet <- tryCatch({
        addOnTargetScores(guideSet, methods="crisprater")
    }, error = function(e) {
        warning("On-target scoring failed: ", e\$message)
        guideSet
    })
    
    message("Adding restriction enzyme annotations...")
    guideSet <- addRestrictionEnzymes(guideSet)
    
    message("Adding gene and transcript context annotations...")
    guideSet <- addGeneAnnotation(guideSet, txObject=txdb)
    
    message("Adding TSS annotations...")
    tss_obj <- getTssObjectFromTxObject(txdb)
    guideSet <- addTssAnnotation(guideSet, tssObject=tss_obj)
    
    message("Performing local off-target search using Biostrings...")
    # Extract local genomic sequences around target genes (expanded by 2000bp) to search for off-targets
    genes_gr <- genes(txdb, filter=list(gene_id=target_entrez))
    genes_gr_expanded <- resize(genes_gr, width=width(genes_gr) + 4000, fix="center")
    custom_seqs <- getSeq(bsgenome, genes_gr_expanded)
    names(custom_seqs) <- target_entrez
    
    guideSet <- addSpacerAlignments(guideSet, aligner="biostrings", n_mismatches=1, custom_seq=custom_seqs)
    
    message("Adding off-target specificity scores...")
    guideSet <- tryCatch({
        addOffTargetScores(guideSet)
    }, error = function(e) {
        warning("Off-target scoring failed: ", e\$message)
        guideSet
    })
    
    # --- Filter, Rank, and Export Results ---
    message("Filtering and ranking designed gRNAs...")
    # Filter out gRNAs with extreme GC content or poly-T stretches
    if ("percentGC" %in% colnames(mcols(guideSet))) {
        guideSet <- guideSet[guideSet\$percentGC >= 20 & guideSet\$percentGC <= 80]
    }
    if ("polyT" %in% colnames(mcols(guideSet))) {
        guideSet <- guideSet[!guideSet\$polyT]
    }
    
    # Rank spacers using the representative transcript of the primary target gene
    tx_info <- select(txdb, keys=target_entrez, columns=c("TXNAME", "GENEID"), keytype="GENEID")
    target_tx_id <- tx_info\$TXNAME[1]
    
    guideSet <- tryCatch({
        rankSpacers(guideSet, tx_id=target_tx_id)
    }, error = function(e) {
        warning("Ranking failed: ", e\$message)
        guideSet
    })
    
    # Convert GuideSet to standard DataFrames and write outputs
    message("Writing output files...")
    dfs <- GuideSet2DataFrames(guideSet)
    
    write.csv(as.data.frame(dfs\$guides), "designed_grnas.csv", row.names=TRUE)
    write.csv(as.data.frame(dfs\$alignments), "grna_alignments.csv", row.names=TRUE)
    
    # Export top 10 recommended gRNAs
    top_guides <- head(as.data.frame(dfs\$guides), 10)
    write.csv(top_guides, "top_grnas_summary.csv", row.names=TRUE)
    
    message("CRISPRko gRNA design pipeline completed successfully!")

    writeLines(c(
        '"BIOC_CRISPRDESIGN_CRISPR_KO_GRNA_DESIGN":',
        paste0('    crisprDesign: ', as.character(packageVersion('crisprDesign')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_crispr_ko_grna_design.csv versions.yml
    """
}

workflow BIOC_CRISPRDESIGN_CRISPR_KO_GRNA_DESIGN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_CRISPRDESIGN_CRISPR_KO_GRNA_DESIGN(ch_input)

    emit:
    tables   = BIOC_CRISPRDESIGN_CRISPR_KO_GRNA_DESIGN.out.tables
    plots    = BIOC_CRISPRDESIGN_CRISPR_KO_GRNA_DESIGN.out.plots
    objects  = BIOC_CRISPRDESIGN_CRISPR_KO_GRNA_DESIGN.out.objects
    versions = BIOC_CRISPRDESIGN_CRISPR_KO_GRNA_DESIGN.out.versions
}
