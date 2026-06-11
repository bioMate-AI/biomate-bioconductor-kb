#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GenomicInteractions — chiapet_analysis_and_feature_summarization
// Load ChIA-PET interaction data, annotate anchors with gene features (promoters, terminators, gene bodies), and summarize interactions per feature.
// Input: chiapet.data, hg19.refseq.transcripts
// Container: quay.io/biocontainers/bioconductor-genomicinteractions:1.44.0--r45hdfd78af_0
// R packages: GenomicFeatures, GenomicInteractions, GenomicRanges, Gviz, InteractionSet, knitr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMICINTERACTIONS_CHIAPET_ANALYSIS_AND_FEATURE_SUMMARIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-genomicinteractions:1.44.0--r45hdfd78af_0"

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
    .bm_deps <- c("GenomicFeatures", "GenomicInteractions", "GenomicRanges", "Gviz", "InteractionSet", "knitr")
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
    library(GenomicInteractions)
    library(InteractionSet)
    library(GenomicRanges)
    
    # -----------------------------------------------------------------------------
    # --- Load ChIA-PET data using makeGenomicInteractionsFromFile ---
    # -----------------------------------------------------------------------------
    chiapet.data <- "chiapet.data"
    if (!file.exists(chiapet.data)) {
      stop("Required input file 'chiapet.data' not found in the working directory.")
    }
    
    k562.rep1 = makeGenomicInteractionsFromFile (chiapet.data, type= "chiapet.tool" , experiment_name= "k562" , description= "k562 pol2 8wg16" )
    
    # -----------------------------------------------------------------------------
    # --- Access and edit metadata (name, description) ---
    # -----------------------------------------------------------------------------
    name (k562.rep1)
    description (k562.rep1) = "PolII-8wg16 Chia-PET for K562"
    head ( interactionCounts (k562.rep1))
    head ((k562.rep1) \$ fdr)
    
    # Save p-value histogram
    pdf("pvalue_histogram.pdf")
    hist ( - log10 (k562.rep1 \$ p.value))
    dev.off()
    
    anchorOne (k562.rep1)
    anchorTwo (k562.rep1)
    sprintf ( "Percentage of trans-chromosomal interactions %.2f" , 100 * sum ( is.trans (k562.rep1)) / length (k562.rep1))
    head ( calculateDistances (k562.rep1, method= "midpoint" ))
    
    # Subsetting examples
    k562.rep1[ 1 : 10 ]
    k562.rep1[ sample ( length (k562.rep1), min(100, length(k562.rep1)) )]
    
    # -----------------------------------------------------------------------------
    # --- Filter for cis-interactions using is.cis and calculate ---
    # -----------------------------------------------------------------------------
    k562.cis = k562.rep1[ is.cis (k562.rep1)]
    head ( calculateDistances (k562.cis, method= "midpoint" ))
    k562.short = k562.cis[ calculateDistances (k562.cis) < 1e6 ]
    
    # Save distances histogram
    pdf("distances_histogram.pdf")
    hist ( calculateDistances (k562.short))
    dev.off()
    
    chrom = c ( "chr17" , "chr18" )
    sub = as.vector ( seqnames ( anchorOne (k562.rep1)) %in% chrom & seqnames ( anchorTwo (k562.rep1)) %in% chrom)
    k562.rep1 = k562.rep1[sub]
    
    # -----------------------------------------------------------------------------
    # --- Define annotation features and annotate interactions ---
    # -----------------------------------------------------------------------------
    # Load hg19.refseq.transcripts from working directory
    if (file.exists("hg19.refseq.transcripts")) {
      refseq.transcripts <- tryCatch({
        readRDS("hg19.refseq.transcripts")
      }, error = function(e) {
        env <- new.env()
        load("hg19.refseq.transcripts", envir = env)
        objs <- ls(env)
        env[[objs[1]]]
      })
    } else {
      stop("Required input file 'hg19.refseq.transcripts' not found in the working directory.")
    }
    
    refseq.promoters = promoters (refseq.transcripts, upstream= 2500 , downstream= 2500 )
    refseq.transcripts.ul = unlist (refseq.transcripts)
    strand (refseq.transcripts.ul) = ifelse ( strand (refseq.transcripts.ul) == "+" , "-" , "+" )
    refseq.terminators.ul = promoters (refseq.transcripts.ul, upstream= 1000 , downstream= 1000 )
    strand (refseq.terminators.ul) = ifelse ( strand (refseq.terminators.ul) == "+" , "-" , "+" )
    refseq.terminators = relist (refseq.terminators.ul, refseq.transcripts)
    
    subsetByFeatures (k562.rep1, unlist (refseq.promoters))
    
    annotation.features = list ( promoter= refseq.promoters, terminator= refseq.terminators, gene.body= refseq.transcripts)
    annotateInteractions (k562.rep1, annotation.features)
    annotationFeatures (k562.rep1)
    
    p.one = anchorOne (k562.rep1) \$ node.class == "promoter"
    p.two = anchorTwo (k562.rep1) \$ node.class == "promoter"
    k562.rep1[p.one | p.two]
    
    # -----------------------------------------------------------------------------
    # --- Categorize interactions and subset by interaction types ---
    # -----------------------------------------------------------------------------
    cat_ints = categoriseInteractions (k562.rep1)
    write.csv(cat_ints, "categorised_interactions.csv", row.names=FALSE)
    
    k562.rep1[ isInteractionType (k562.rep1, "terminator" , "gene.body" )]
    k562.rep1[ is.pp (k562.rep1)]
    k562.rep1[ is.dd (k562.rep1)]
    k562.rep1[ is.pt (k562.rep1)]
    
    # -----------------------------------------------------------------------------
    # --- Plot interaction annotations using ---
    # -----------------------------------------------------------------------------
    pdf("interaction_annotations.pdf")
    plotInteractionAnnotations (k562.rep1, other= 5 )
    dev.off()
    
    pdf("interaction_annotations_promoter.pdf")
    plotInteractionAnnotations (k562.rep1, other= 5 , viewpoints= "promoter" )
    dev.off()
    
    # -----------------------------------------------------------------------------
    # --- Summarize interactions over specific features using ---
    # -----------------------------------------------------------------------------
    k562.rep1.promoter.annotation = summariseByFeatures (k562.rep1, refseq.promoters, "promoter" , distance.method= "midpoint" , annotate.self= TRUE )
    colnames (k562.rep1.promoter.annotation)
    write.csv(k562.rep1.promoter.annotation, "k562_rep1_promoter_annotation.csv", row.names=FALSE)
    
    i = order (k562.rep1.promoter.annotation \$ numberOfPromoterPromoterInteractions, decreasing= TRUE )[ 1 : 10 ]
    top_pp = k562.rep1.promoter.annotation[i, ]
    write.csv(top_pp, "top_promoter_promoter_interactions.csv", row.names=FALSE)
    
    i = order (k562.rep1.promoter.annotation \$ numberOfUniquePromoterDistalInteractions, decreasing= TRUE )[ 1 : 10 ]
    top_pd = k562.rep1.promoter.annotation[i, ]
    write.csv(top_pd, "top_promoter_distal_interactions.csv", row.names=FALSE)
    
    total = sum (k562.rep1.promoter.annotation \$ numberOfPromoterTerminatorInteractions > 0 )
    pt_pct_str = sprintf ( "%.2f%% of promoters have P-T interactions" , 100 * total / nrow (k562.rep1.promoter.annotation))
    writeLines(pt_pct_str, "promoter_terminator_percentage.txt")
    
    # Save the final annotated GenomicInteractions object
    saveRDS(k562.rep1, "k562_rep1_annotated.rds")

    writeLines(c(
        '"BIOC_GENOMICINTERACTIONS_CHIAPET_ANALYSIS_AND_FEATURE_SUMMARIZATION":',
        paste0('        GenomicInteractions: ', as.character(packageVersion("GenomicInteractions")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chiapet_analysis_and_feature_summarization.csv versions.yml
    """
}

workflow BIOC_GENOMICINTERACTIONS_CHIAPET_ANALYSIS_AND_FEATURE_SUMMARIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chiapet.data, hg19.refseq.transcripts ] ]

    main:
    BIOC_GENOMICINTERACTIONS_CHIAPET_ANALYSIS_AND_FEATURE_SUMMARIZATION(ch_input)

    emit:
    tables   = BIOC_GENOMICINTERACTIONS_CHIAPET_ANALYSIS_AND_FEATURE_SUMMARIZATION.out.tables
    plots    = BIOC_GENOMICINTERACTIONS_CHIAPET_ANALYSIS_AND_FEATURE_SUMMARIZATION.out.plots
    objects  = BIOC_GENOMICINTERACTIONS_CHIAPET_ANALYSIS_AND_FEATURE_SUMMARIZATION.out.objects
    versions = BIOC_GENOMICINTERACTIONS_CHIAPET_ANALYSIS_AND_FEATURE_SUMMARIZATION.out.versions
}
