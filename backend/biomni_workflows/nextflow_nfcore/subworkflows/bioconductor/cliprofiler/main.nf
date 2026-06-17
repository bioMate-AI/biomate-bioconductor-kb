#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cliProfiler — transcript_feature_profiling
// Profile and visualize CLIP-seq peaks across standard transcript features (metagene, introns, exons, gene types, and splice sites) using GENCODE GFF3 annotations
// Input: peaks.rds, annotation.gff3
// Container: quay.io/biocontainers/bioconductor-cliprofiler:1.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, cliProfiler, ggplot2, rtracklayer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load peak data and GFF3 annotation
//  * 2. [Core Analysis] Generate metagene profile using metaGeneProfile
//  * 3. [Core Analysis] Generate intron profile using intronProfile
//  * 4. [Core Analysis] Generate exon profile using exonProfile
//  * 5. [Core Analysis] Generate gene type profile using geneTypeProfile
//  * 6. [Core Analysis] Generate splice site profile using spliceSiteProfile

nextflow.enable.dsl = 2

process BIOC_CLIPROFILER_TRANSCRIPT_FEATURE_PROFILING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("cliProfiler", "ggplot2", "GenomicRanges", "rtracklayer")
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
    library(cliProfiler)
    library(ggplot2)
    library(GenomicRanges)
    library(rtracklayer)
    
    # ==========================================
    # 1. Load peak data and GFF3 annotation
    # ==========================================
    
    # Read the user-provided files from the working directory
    test <- readRDS("peaks.rds")
    test_gff3 <- "annotation.gff3"
    
    # Ensure the GRanges object is loaded correctly
    if (!inherits(test, "GRanges")) {
      stop("Input 'peaks.rds' must be a GRanges object.")
    }
    
    # ==========================================
    # 2. Generate metagene profile
    # ==========================================
    
    message("Generating metagene profiles...")
    
    # Standard metagene profile
    meta <- metaGeneProfile(object = test, annotation = test_gff3)
    saveRDS(meta[[1]], "metagene_profile_granges.rds")
    write.csv(as.data.frame(meta[[1]]), "metagene_profile.csv", row.names = FALSE)
    
    # Plot with custom title
    p1 <- meta[[2]] + ggtitle("Meta Profile 2")
    ggsave("metagene_profile_plot.pdf", plot = p1, width = 8, height = 6)
    
    # Metagene profile including introns
    meta_intron <- metaGeneProfile(object = test, annotation = test_gff3, include_intron = TRUE)
    ggsave("metagene_profile_with_introns.pdf", plot = meta_intron[[2]], width = 8, height = 6)
    
    # Grouped metagene profile (assigning Treatment groups dynamically based on input size)
    test\$Treat <- rep(c("Treatment 1", "Treatment 2"), length.out = length(test))
    meta_group <- metaGeneProfile(object = test, annotation = test_gff3, group = "Treat")
    ggsave("metagene_profile_grouped.pdf", plot = meta_group[[2]], width = 8, height = 6)
    
    # Filtered metagene profile
    tryCatch({
      meta_filtered <- metaGeneProfile(object = test, annotation = test_gff3, exlevel = 3, extranscript_support_level = c(4,5,6))
      saveRDS(meta_filtered[[1]], "metagene_profile_filtered_granges.rds")
      if (length(meta_filtered) >= 2 && !is.null(meta_filtered[[2]])) {
        ggsave("metagene_profile_filtered.pdf", plot = meta_filtered[[2]], width = 8, height = 6)
      }
    }, error = function(e) {
      message("Warning: Filtered metagene profile failed: ", e\$message)
    })
    
    # Split metagene profile
    meta_split <- metaGeneProfile(object = test, annotation = test_gff3, split = TRUE)
    ggsave("metagene_profile_split.pdf", plot = meta_split[[2]], width = 8, height = 6)
    
    
    # ==========================================
    # 3. Generate intron profile
    # ==========================================
    
    message("Generating intron profiles...")
    
    intron <- intronProfile(test, test_gff3)
    saveRDS(intron[[1]], "intron_profile_granges.rds")
    write.csv(as.data.frame(intron[[1]]), "intron_profile.csv", row.names = FALSE)
    ggsave("intron_profile_plot.pdf", plot = intron[[2]], width = 8, height = 6)
    
    # Grouped intron profile
    intron_group <- intronProfile(test, test_gff3, group = "Treat")
    ggsave("intron_profile_grouped.pdf", plot = intron_group[[2]], width = 8, height = 6)
    
    # Filtered intron profile
    tryCatch({
      intron_filtered <- intronProfile(test, test_gff3, group = "Treat", exlevel = 3, extranscript_support_level = c(4,5,6))
      saveRDS(intron_filtered[[1]], "intron_profile_filtered_granges.rds")
      if (length(intron_filtered) >= 2 && !is.null(intron_filtered[[2]])) {
        ggsave("intron_profile_filtered.pdf", plot = intron_filtered[[2]], width = 8, height = 6)
      }
    }, error = function(e) {
      message("Warning: Filtered intron profile failed: ", e\$message)
    })
    
    # Length-filtered intron profile
    tryCatch({
      intron_len_filtered <- intronProfile(test, test_gff3, group = "Treat", maxLength = 10000, minLength = 50)
      saveRDS(intron_len_filtered[[1]], "intron_profile_len_filtered_granges.rds")
      if (length(intron_len_filtered) >= 2 && !is.null(intron_len_filtered[[2]])) {
        ggsave("intron_profile_len_filtered.pdf", plot = intron_len_filtered[[2]], width = 8, height = 6)
      }
    }, error = function(e) {
      message("Warning: Length-filtered intron profile failed: ", e\$message)
    })
    
    
    # ==========================================
    # 4. Generate exon profile
    # ==========================================
    
    message("Generating exon profiles...")
    
    exon <- exonProfile(test, test_gff3)
    saveRDS(exon[[1]], "exon_profile_granges.rds")
    write.csv(as.data.frame(exon[[1]]), "exon_profile.csv", row.names = FALSE)
    ggsave("exon_profile_plot.pdf", plot = exon[[2]], width = 8, height = 6)
    
    
    # ==========================================
    # 5. Generate gene type profile
    # ==========================================
    
    message("Generating gene type profiles...")
    
    geneTP <- geneTypeProfile(test, test_gff3)
    saveRDS(geneTP[[1]], "gene_type_profile_granges.rds")
    write.csv(as.data.frame(geneTP[[1]]), "gene_type_profile.csv", row.names = FALSE)
    ggsave("gene_type_profile_plot.pdf", plot = geneTP[[2]], width = 8, height = 6)
    
    
    # ==========================================
    # 6. Generate splice site profile
    # ==========================================
    
    message("Generating splice site profiles...")
    
    SSprofile <- spliceSiteProfile(test, test_gff3, flanking=200, bin=40)
    saveRDS(SSprofile[[1]], "splice_site_profile_granges.rds")
    write.csv(as.data.frame(SSprofile[[1]]), "splice_site_profile.csv", row.names = FALSE)
    ggsave("splice_site_profile_plot.pdf", plot = SSprofile[[2]], width = 8, height = 6)
    
    # Filtered splice site profile
    tryCatch({
      SSprofile_filtered <- spliceSiteProfile(test, test_gff3, flanking=200, bin=40, exlevel=3, extranscript_support_level = 6, title = "Splice Site Profile")
      saveRDS(SSprofile_filtered[[1]], "splice_site_profile_filtered_granges.rds")
      ggsave("splice_site_profile_filtered_plot.pdf", plot = SSprofile_filtered[[2]], width = 8, height = 6)
    }, error = function(e) {
      message("Warning: Filtered splice site profile failed: ", e\$message)
    })
    
    message("Pipeline completed successfully. All outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_CLIPROFILER_TRANSCRIPT_FEATURE_PROFILING":',
        paste0('    cliProfiler: ', as.character(packageVersion('cliProfiler')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_transcript_feature_profiling.csv versions.yml
    """
}

workflow BIOC_CLIPROFILER_TRANSCRIPT_FEATURE_PROFILING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peaks.rds, annotation.gff3 ] ]

    main:
    BIOC_CLIPROFILER_TRANSCRIPT_FEATURE_PROFILING(ch_input)

    emit:
    tables   = BIOC_CLIPROFILER_TRANSCRIPT_FEATURE_PROFILING.out.tables
    plots    = BIOC_CLIPROFILER_TRANSCRIPT_FEATURE_PROFILING.out.plots
    objects  = BIOC_CLIPROFILER_TRANSCRIPT_FEATURE_PROFILING.out.objects
    versions = BIOC_CLIPROFILER_TRANSCRIPT_FEATURE_PROFILING.out.versions
}
