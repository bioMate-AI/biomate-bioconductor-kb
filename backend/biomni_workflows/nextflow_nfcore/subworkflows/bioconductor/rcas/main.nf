#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rcas — single_sample_rcas_analysis
// Perform comprehensive annotation, coverage profiling, motif discovery, and functional enrichment on a single set of query regions.
// Input: queryRegions.bed, annotation.gtf
// Container: quay.io/biocontainers/bioconductor-rcas:1.36.0--r45hdfd78af_0
// R packages: data.table, ggplot2, RCAS, seqLogo
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RCAS_SINGLE_SAMPLE_RCAS_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rcas:1.36.0--r45hdfd78af_0"

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
    .bm_deps <- c("data.table", "ggplot2", "RCAS", "seqLogo")
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
    library(RCAS)
    library(data.table)
    library(ggplot2)
    library(seqLogo)
    
    # --- Import BED and GTF files ---
    queryRegions <- importBed(filePath = "queryRegions.bed", sampleN = 10000)
    gff <- importGtf(filePath = "annotation.gtf")
    
    # --- Query overlaps between query regions and reference ---
    overlaps <- as.data.table(queryGff(queryRegions = queryRegions, gffData = gff))
    
    # Find targeted gene types and plot
    biotype_col <- grep('gene_biotype', colnames(overlaps), value = TRUE)
    df_biotype <- overlaps[, length(unique(queryIndex)), by = biotype_col]
    colnames(df_biotype) <- c("feature", "count")
    df_biotype\$percent <- round(df_biotype\$count / length(queryRegions) * 100, 1)
    df_biotype <- df_biotype[order(count, decreasing = TRUE)]
    
    p1 <- ggplot2::ggplot(df_biotype, aes(x = reorder(feature, -percent), y = percent)) + 
      geom_bar(stat = 'identity', aes(fill = feature)) + 
      geom_label(aes(y = percent + 0.5), label = df_biotype\$count) + 
      labs(x = 'transcript feature', y = paste0('percent overlap (n = ', length(queryRegions), ')')) + 
      theme_bw(base_size = 14) + 
      theme(axis.text.x = element_text(angle = 90))
    
    ggsave("biotype_overlap_plot.pdf", plot = p1, width = 10, height = 8)
    write.csv(df_biotype, "biotype_overlaps.csv", row.names = FALSE)
    
    # --- Extract transcript features from the GTF ---
    txdbFeatures <- getTxdbFeaturesFromGRanges(gff)
    
    # --- Summarize query regions across transcript features ---
    summary <- summarizeQueryRegions(queryRegions = queryRegions, txdbFeatures = txdbFeatures)
    df_summary <- data.frame(summary)
    df_summary\$percent <- round((df_summary\$count / length(queryRegions)), 3) * 100
    df_summary\$feature <- rownames(df_summary)
    
    p2 <- ggplot2::ggplot(df_summary, aes(x = reorder(feature, -percent), y = percent)) + 
      geom_bar(stat = 'identity', aes(fill = feature)) + 
      geom_label(aes(y = percent + 3), label = df_summary\$count) + 
      labs(x = 'transcript feature', y = paste0('percent overlap (n = ', length(queryRegions), ')')) + 
      theme_bw(base_size = 14) + 
      theme(axis.text.x = element_text(angle = 90))
    
    ggsave("transcript_feature_overlap_plot.pdf", plot = p2, width = 10, height = 8)
    write.csv(df_summary, "transcript_feature_overlaps.csv", row.names = FALSE)
    
    # --- Generate targeted genes table ---
    dt <- getTargetedGenesTable(queryRegions = queryRegions, txdbFeatures = txdbFeatures)
    dt <- dt[order(transcripts, decreasing = TRUE)]
    write.csv(dt, "targeted_genes_table.csv", row.names = FALSE)
    
    # --- Profile coverage at feature boundaries ---
    cvgF <- getFeatureBoundaryCoverage(queryRegions = queryRegions, featureCoords = txdbFeatures\$transcripts, flankSize = 1000, boundaryType = 'fiveprime', sampleN = 10000)
    cvgT <- getFeatureBoundaryCoverage(queryRegions = queryRegions, featureCoords = txdbFeatures\$transcripts, flankSize = 1000, boundaryType = 'threeprime', sampleN = 10000)
    cvgF\$boundary <- 'fiveprime'
    cvgT\$boundary <- 'threeprime'
    df_cvg <- rbind(cvgF, cvgT)
    
    p3 <- ggplot2::ggplot(df_cvg, aes(x = bases, y = meanCoverage)) + 
      geom_ribbon(fill = 'lightgreen', aes(ymin = meanCoverage - standardError * 1.96, ymax = meanCoverage + standardError * 1.96)) + 
      geom_line(color = 'black') + 
      facet_grid(~ boundary) + 
      theme_bw(base_size = 14)
    
    ggsave("feature_boundary_coverage_plot.pdf", plot = p3, width = 10, height = 6)
    
    # --- Calculate coverage profiles across all features ---
    cvgList <- calculateCoverageProfileList(queryRegions = queryRegions, targetRegionsList = txdbFeatures, sampleN = 10000)
    
    p4 <- ggplot2::ggplot(cvgList, aes(x = bins, y = meanCoverage)) + 
      geom_ribbon(fill = 'lightgreen', aes(ymin = meanCoverage - standardError * 1.96, ymax = meanCoverage + standardError * 1.96)) + 
      geom_line(color = 'black') + 
      theme_bw(base_size = 14) + 
      facet_wrap(~ feature, ncol = 3)
    
    ggsave("coverage_profile_list_plot.pdf", plot = p4, width = 12, height = 10)
    
    # --- Discover motifs and get summary table ---
    motifResults <- runMotifDiscovery(queryRegions = queryRegions, resizeN = 15, sampleN = 10000, genomeVersion = 'hg19', motifWidth = 6, motifN = 1, nCores = 1)
    
    # Save sequence logo
    pdf("motif_seqlogo.pdf", width = 6, height = 4)
    seqLogo::seqLogo(getPWM(motifResults\$matches_query[[1]]))
    dev.off()
    
    motif_summary <- getMotifSummaryTable(motifResults)
    write.csv(motif_summary, "motif_summary_table.csv", row.names = FALSE)
    
    # --- Find enriched functions ---
    targetedGenes <- unique(overlaps\$gene_id)
    res <- RCAS::findEnrichedFunctions(targetGenes = targetedGenes, species = 'hsapiens')
    res <- res[order(res\$p_value),]
    resGO <- res[grep('GO:BP', res\$source),]
    write.csv(resGO, "enriched_functions_GO_BP.csv", row.names = FALSE)
    
    # --- Generate a full HTML report ---
    runReport(queryFilePath = 'queryRegions.bed', gffFilePath = 'annotation.gtf')

    writeLines(c(
        '"BIOC_RCAS_SINGLE_SAMPLE_RCAS_ANALYSIS":',
        paste0('        rcas: ', as.character(packageVersion("rcas")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_sample_rcas_analysis.csv versions.yml
    """
}

workflow BIOC_RCAS_SINGLE_SAMPLE_RCAS_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ queryRegions.bed, annotation.gtf ] ]

    main:
    BIOC_RCAS_SINGLE_SAMPLE_RCAS_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RCAS_SINGLE_SAMPLE_RCAS_ANALYSIS.out.tables
    plots    = BIOC_RCAS_SINGLE_SAMPLE_RCAS_ANALYSIS.out.plots
    objects  = BIOC_RCAS_SINGLE_SAMPLE_RCAS_ANALYSIS.out.objects
    versions = BIOC_RCAS_SINGLE_SAMPLE_RCAS_ANALYSIS.out.versions
}
