#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ggbio — genomic_tracks_construction_and_navigation
// Build and navigate a multi-track genomic visualization containing an ideogram, gene models, alignment coverage/mismatches, and variants.
// Input: indexed_bam_file.bam, variants_file.vcf.bgz, TxDb_or_OrganismDb_or_EnsDb_package, BSgenome_package
// Container: quay.io/biocontainers/bioconductor-ggbio:1.58.0--r45hdfd78af_0
// R packages: AnnotationFilter, GenomeInfoDb, GenomicAlignments, GenomicRanges, VariantAnnotation, biovizBase, bsgenome_pkg, ensembldb, ggbio, txdb_pkg
// Bioconductor: 3.20 | R: 4.4
// Requires: AnnotationFilter, GenomeInfoDb, GenomicAlignments, GenomicRanges, VariantAnnotation, biovizBase, ensembldb, ggbio
// Visualizations: autoplot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create an ideogram track using Ideogram()
//  * 2. [Input & Preparation] Build a gene model track from an annotation database (e.g., Homo.sapiens, TxDb, or EnsDb) using autoplot()
//  * 3. [Input & Preparation] Load reference sequence from a BSgenome object and configure semantic zoom
//  * 4. [Input & Preparation] Build an alignment track from a BAM file using autoplot(), optionally calculating mismatches with stat = "mismatch"
//  * 5. [Input & Preparation] Build a variants track from a VCF file or VRanges object using autoplot()
//  * 6. [Visualization & Output] Combine all tracks into a single visualization using tracks() and customize heights and themes
//  * 7. [Core Analysis] Navigate the tracks using zoom(), nextView(), or prevView()

nextflow.enable.dsl = 2

process BIOC_GGBIO_GENOMIC_TRACKS_CONSTRUCTION_AND_NAVIGATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("AnnotationFilter", "GenomeInfoDb", "GenomicAlignments", "GenomicRanges", "VariantAnnotation", "biovizBase", "bsgenome_pkg", "ensembldb", "ggbio", "txdb_pkg")
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
        library(ggbio)
        library(GenomicRanges)
        library(GenomicAlignments)
        library(VariantAnnotation)
        library(biovizBase)
        library(GenomeInfoDb)
        
        # -----------------------------------------------------------------------------
        # 1. Read User Input Files and Package Names
        # -----------------------------------------------------------------------------
        # Read package names from the specified files in the working directory
        txdb_pkg <- trimws(readLines("TxDb_or_OrganismDb_or_EnsDb_package", warn = FALSE)[1])
        bsgenome_pkg <- trimws(readLines("BSgenome_package", warn = FALSE)[1])
        
        # Load the user-specified packages
        library(txdb_pkg, character.only = TRUE)
        library(bsgenome_pkg, character.only = TRUE)
        
        # Retrieve the database and reference genome objects
        txdb_obj <- get(txdb_pkg)
        bg <- get(bsgenome_pkg)
        
        # Determine the genome assembly name (e.g., "hg19")
        genome_name <- unique(genome(bg))[1]
        if (is.na(genome_name) || genome_name == "") {
          genome_name <- "hg19"
        }
        
        # Define the BAM and VCF file paths
        fl.bam <- "indexed_bam_file.bam"
        fl.vcf <- "variants_file.vcf.bgz"
        # Ensure the BAM is indexed — BamFile()/readGAlignments ranged access needs a .bai.
        if (file.exists(fl.bam) && !file.exists(paste0(fl.bam, ".bai"))) Rsamtools::indexBam(fl.bam)
        
        # -----------------------------------------------------------------------------
        # 2. Determine Genomic Region of Interest (wh) Dynamically
        # -----------------------------------------------------------------------------
        # Read alignments to find a valid active genomic region
        # Use BamFile with yieldSize and ScanBamParam to avoid reading the entire file into memory
        bf <- BamFile(fl.bam, yieldSize = 1000)
        param_bam <- ScanBamParam(flag = scanBamFlag(isUnmappedQuery = FALSE))
        ga <- readGAlignments(bf, param = param_bam)
        
        wh_raw <- range(granges(ga))
        wh_raw <- wh_raw[1]
        target_chrom <- as.character(seqnames(wh_raw))
        
        # Adjust wh to have a standard width of 20,000 bp around the center of alignments
        wh_center <- start(wh_raw) + width(wh_raw)/2
        wh <- GRanges(target_chrom, IRanges(max(1, wh_center - 10000), wh_center + 10000))
        
        # -----------------------------------------------------------------------------
        # 3. Create Ideogram Track
        # -----------------------------------------------------------------------------
        supported_genomes <- c("hg19", "hg18", "mm10", "mm9")
        ideo_genome <- if (genome_name %in% supported_genomes) genome_name else "hg19"
        
        p.ideo <- tryCatch({
          Ideogram(genome = ideo_genome)
        }, error = function(e) {
          Ideogram(genome = "hg19")
        })
        
        # Highlight a region on the ideogram
        p.ideo_highlight <- p.ideo + xlim(GRanges(target_chrom, IRanges(max(1, wh_center - 5000000), wh_center + 5000000)))
        ggsave("plot_ideogram_highlight.pdf", p.ideo_highlight)
        
        # -----------------------------------------------------------------------------
        # 4. Build Gene Model Track
        # -----------------------------------------------------------------------------
        is_organism_db <- inherits(txdb_obj, "OrganismDb")
        is_ens_db <- inherits(txdb_obj, "EnsDb")
        is_tx_db <- inherits(txdb_obj, "TxDb")
        
        if (is_organism_db) {
          Homo.sapiens <- txdb_obj
          
          p.txdb <- autoplot(Homo.sapiens, which = wh)
          ggsave("plot_organism_db_default.pdf", p.txdb)
          
          p_custom <- autoplot(Homo.sapiens, which = wh, label.color = "black", color = "brown", fill = "brown")
          ggsave("plot_organism_db_custom_colors.pdf", p_custom)
          
          p_chevron <- autoplot(Homo.sapiens, which = wh, gap.geom = "chevron")
          ggsave("plot_organism_db_chevron.pdf", p_chevron)
          
          p_reduce <- autoplot(Homo.sapiens, which = wh, stat = "reduce")
          ggsave("plot_organism_db_reduce.pdf", p_reduce)
          
          cols <- columns(Homo.sapiens)
          write.csv(as.data.frame(cols), "organism_db_columns.csv", row.names = FALSE)
          
          if (all(c("TXNAME", "GO") %in% cols)) {
            p_expr <- autoplot(Homo.sapiens, which = wh, columns = c("TXNAME", "GO"), names.expr = "TXNAME::GO")
            ggsave("plot_organism_db_expr.pdf", p_expr)
          }
          
          txdb_for_crunch <- txdb(Homo.sapiens)
          
        } else if (is_tx_db) {
          txdb <- txdb_obj
          
          p.txdb <- autoplot(txdb, which = wh)
          ggsave("plot_txdb_default.pdf", p.txdb)
          
          txdb_for_crunch <- txdb
          
        } else if (is_ens_db) {
          ensdb <- txdb_obj
          library(AnnotationFilter)
          
          # Query genes in the region to find a valid gene name and ID
          genes_in_region <- genes(ensdb, filter = GRangesFilter(wh))
          if (length(genes_in_region) > 0) {
            target_gene_name <- genes_in_region\$gene_name[1]
            target_gene_id <- genes_in_region\$gene_id[1]
          } else {
            all_genes <- genes(ensdb)
            target_gene_name <- all_genes\$gene_name[1]
            target_gene_id <- all_genes\$gene_id[1]
          }
          
          p_ens1 <- autoplot(ensdb, GeneNameFilter(target_gene_name))
          ggsave("plot_ensdb_genename.pdf", p_ens1)
          
          formula_str <- paste0("~ symbol == '", target_gene_name, "'")
          p_ens2 <- autoplot(ensdb, as.formula(formula_str), names.expr = "gene_name")
          ggsave("plot_ensdb_formula.pdf", p_ens2)
          
          p_ens3 <- autoplot(ensdb, GRangesFilter(wh), names.expr = "gene_name")
          ggsave("plot_ensdb_granges.pdf", p_ens3)
          
          p_ens4 <- autoplot(ensdb, GeneIdFilter(target_gene_id))
          ggsave("plot_ensdb_geneid.pdf", p_ens4)
          
          p.txdb <- p_ens3
          
          library(ensembldb)
          txdb_for_crunch <- makeTxDbFromEnsDb(ensdb)
        }
        
        # -----------------------------------------------------------------------------
        # 5. GRangesList Gene Model Construction
        # -----------------------------------------------------------------------------
        txdb <- txdb_for_crunch
        gr.txdb <- crunch(txdb, which = wh)
        if (length(gr.txdb) > 0) {
          colnames(values(gr.txdb))[4] <- "model"
          grl <- split(gr.txdb, gr.txdb\$tx_id)
          names(grl) <- sample(LETTERS, size = length(grl), replace = TRUE)
          
          p_grl1 <- autoplot(grl, aes(type = model))
          ggsave("plot_grl_aes.pdf", p_grl1)
          
          p_grl2 <- ggplot() + geom_alignment(grl, type = "model")
          ggsave("plot_grl_geom_alignment.pdf", p_grl2)
        }
        
        # -----------------------------------------------------------------------------
        # 6. Load Reference Sequence and Configure Semantic Zoom
        # -----------------------------------------------------------------------------
        p.bg <- autoplot(bg, which = wh)
        ggsave("plot_bg_default.pdf", p.bg)
        
        p_bg_zoom100 <- p.bg + zoom(1/100)
        ggsave("plot_bg_zoom100.pdf", p_bg_zoom100)
        
        p_bg_zoom1000 <- p.bg + zoom(1/1000)
        ggsave("plot_bg_zoom1000.pdf", p_bg_zoom1000)
        
        p_bg_zoom2500 <- p.bg + zoom(1/2500)
        ggsave("plot_bg_zoom2500.pdf", p_bg_zoom2500)
        
        p_bg_segment <- autoplot(bg, which = resize(wh, width = width(wh)/2000), geom = "segment")
        ggsave("plot_bg_segment.pdf", p_bg_segment)
        
        # -----------------------------------------------------------------------------
        # 7. Build Alignment Track
        # -----------------------------------------------------------------------------
        wh <- keepSeqlevels(wh, target_chrom)
        
        p_bam1 <- autoplot(fl.bam, which = wh)
        ggsave("plot_bam_default.pdf", p_bam1)
        
        p_bam2 <- autoplot(fl.bam, which = resize(wh, width = width(wh)/10), geom = "gapped.pair")
        ggsave("plot_bam_gapped_pair.pdf", p_bam2)
        
        p.mis <- autoplot(fl.bam, bsgenome = bg, which = wh, stat = "mismatch")
        ggsave("plot_bam_mismatch.pdf", p.mis)
        
        p_bam_est1 <- autoplot(fl.bam, method = "estimate")
        ggsave("plot_bam_estimate.pdf", p_bam_est1)
        
        # Estimate coverage on available chromosomes
        bam_info <- idxstatsBam(fl.bam)
        seqlevels_in_bam <- seqlevels(Seqinfo(genome = genome_name))
        available_chroms <- seqlevels_in_bam[seqlevels_in_bam %in% bam_info\$seqnames]
        if (length(available_chroms) >= 2) {
          est_chroms <- available_chroms[1:2]
        } else {
          est_chroms <- rep(target_chrom, 2)
        }
        
        p_bam_est2 <- autoplot(fl.bam, method = "estimate", which = est_chroms, aes(y = log(..coverage..)))
        ggsave("plot_bam_estimate_log.pdf", p_bam_est2)
        
        # -----------------------------------------------------------------------------
        # 8. Build Variants Track
        # -----------------------------------------------------------------------------
        # Use ScanVcfParam to read only the region of interest to avoid OOM errors
        vcf_param <- ScanVcfParam(which = wh)
        vcf <- readVcf(fl.vcf, genome_name, param = vcf_param)
        
        # Safely subset columns using seq_len to prevent out-of-bounds errors on sites-only VCFs
        cols_to_keep <- seq_len(min(3, ncol(vcf)))
        vr <- as(vcf[, cols_to_keep, drop = FALSE], "VRanges")
        
        # Ensure seqlevels match target chromosome style
        if (!any(seqlevels(vr) %in% seqlevels(wh))) {
          vr <- renameSeqlevels(vr, value = setNames(target_chrom, seqlevels(vr)[1]))
        }
        
        # Define a small region containing variants for zooming
        vr_in_wh <- subsetByOverlaps(vr, wh)
        if (length(vr_in_wh) > 0) {
          var_pos <- start(vr_in_wh)[1]
          gr17 <- GRanges(target_chrom, IRanges(max(1, var_pos - 50), var_pos + 50))
        } else {
          gr17 <- GRanges(target_chrom, IRanges(start(wh) + 5000, start(wh) + 5100))
        }
        
        p.vr <- autoplot(vr, which = wh)
        ggsave("plot_vcf_default.pdf", p.vr)
        
        p_vr_xlim <- p.vr + xlim(gr17)
        ggsave("plot_vcf_xlim.pdf", p_vr_xlim)
        
        p_vr_zoom <- p.vr + xlim(gr17) + zoom()
        ggsave("plot_vcf_zoom.pdf", p_vr_zoom)
        
        p_vr_rect <- autoplot(vr, which = wh, geom = "rect", arrow = FALSE)
        ggsave("plot_vcf_rect.pdf", p_vr_rect)
        
        # -----------------------------------------------------------------------------
        # 9. Combine Tracks and Customize Layout
        # -----------------------------------------------------------------------------
        tks <- tracks(p.ideo, mismatch = p.mis, dbSNP = p.vr, ref = p.bg, gene = p.txdb,
                      heights = c(2, 3, 3, 1, 4)) + xlim(gr17) + theme_tracks_sunset()
        
        # Save combined tracks visualization
        pdf("tracks_sunset.pdf", width = 10, height = 12)
        print(tks)
        dev.off()
        
        # Save the tracks object as an RDS file
        saveRDS(tks, "tracks_object.rds")
        
        # -----------------------------------------------------------------------------
        # 10. Navigate Tracks
        # -----------------------------------------------------------------------------
        tks_zoom <- tks + zoom()
        
        pdf("tracks_sunset_zoom.pdf", width = 10, height = 12)
        print(tks_zoom)
        dev.off()

    writeLines(c(
        '"BIOC_GGBIO_GENOMIC_TRACKS_CONSTRUCTION_AND_NAVIGATION":',
        paste0('    ggbio: ', as.character(packageVersion('ggbio')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomic_tracks_construction_and_navigation.csv versions.yml
    """
}

workflow BIOC_GGBIO_GENOMIC_TRACKS_CONSTRUCTION_AND_NAVIGATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ indexed_bam_file.bam, variants_file.vcf.bgz, TxDb_or_OrganismDb_or_EnsDb_package, BSgenome_package ] ]

    main:
    BIOC_GGBIO_GENOMIC_TRACKS_CONSTRUCTION_AND_NAVIGATION(ch_input)

    emit:
    tables   = BIOC_GGBIO_GENOMIC_TRACKS_CONSTRUCTION_AND_NAVIGATION.out.tables
    plots    = BIOC_GGBIO_GENOMIC_TRACKS_CONSTRUCTION_AND_NAVIGATION.out.plots
    objects  = BIOC_GGBIO_GENOMIC_TRACKS_CONSTRUCTION_AND_NAVIGATION.out.objects
    versions = BIOC_GGBIO_GENOMIC_TRACKS_CONSTRUCTION_AND_NAVIGATION.out.versions
}
