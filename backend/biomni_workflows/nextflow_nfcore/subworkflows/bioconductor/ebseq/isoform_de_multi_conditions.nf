#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: EBSeq — isoform_de_multi_conditions
// Identify isoform expression patterns across three or more biological conditions while accounting for isoform estimation uncertainty.
// Input: multi_condition_isoform_counts.csv, isoform_annotations.csv, multi_conditions.csv
// Container: quay.io/biocontainers/bioconductor-ebseq:2.8.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: EBSeq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read User Input Files
//  * 2. [Core Analysis] Run EBSeq Multi-Condition Workflow
//  * 3. [Core Analysis] Diagnostics and Visualization
//  * 4. [Core Analysis] Write Output Files

nextflow.enable.dsl = 2

process BIOC_EBSEQ_ISOFORM_DE_MULTI_CONDITIONS {
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
    .bm_deps <- c("EBSeq")
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
        
        # Load required library
        library(EBSeq)
        
        # ==========================================
        # --- Read User Input Files ---
        # ==========================================
        
        # Read raw isoform counts matrix
        counts_df <- read.csv("multi_condition_isoform_counts.csv", row.names = 1, check.names = FALSE)
        IsoMultiMat <- as.matrix(counts_df)
        
        # Read isoform annotations (isoform names and parent gene names)
        anno_df <- read.csv("isoform_annotations.csv", stringsAsFactors = FALSE)
        IsoNames.Multi <- as.character(anno_df[[1]])
        IsosGeneNames.Multi <- as.character(anno_df[[2]])
        
        # Read experimental conditions
        cond_df <- read.csv("multi_conditions.csv", stringsAsFactors = FALSE)
        Conditions <- as.character(cond_df[[1]])
        
        # ==========================================
        # --- Run EBSeq Multi-Condition Workflow ---
        # ==========================================
        
        # Calculate sample normalization factors
        IsoMultiSize=MedianNorm(IsoMultiMat)
        
        # Assign isoforms to uncertainty groups (Ig groups)
        NgList.Multi=GetNg(IsoNames.Multi, IsosGeneNames.Multi)
        IsoNgTrun.Multi=NgList.Multi\$IsoformNgTrun
        
        # Generate all possible expression patterns across conditions
        PosParti=GetPatterns(Conditions)
        
        # Run the multi-condition empirical Bayes test for isoforms
        IsoMultiOut=EBMultiTest(IsoMultiMat, NgVector=IsoNgTrun.Multi,Conditions=Conditions, AllParti=PosParti, sizeFactors=IsoMultiSize, maxround=5)
        
        # Extract posterior probabilities for each pattern and the MAP pattern
        IsoMultiPP=GetMultiPP(IsoMultiOut)
        
        # Calculate fold changes across conditions
        IsoMultiFC=GetMultiFC(IsoMultiOut)
        
        # ==========================================
        # --- Diagnostics and Visualization ---
        # ==========================================
        
        # Save diagnostic plots to PDF
        pdf("ebseq_diagnostics.pdf", width = 12, height = 8)
        par(mfrow=c(3,4))
        QQP(IsoMultiOut)
        DenNHist(IsoMultiOut)
        dev.off()
        
        # ==========================================
        # --- Write Output Files ---
        # ==========================================
        
        # Save posterior probabilities matrix
        write.csv(IsoMultiPP\$PP, "isoform_posterior_probabilities.csv", row.names = TRUE)
        
        # Save MAP (Maximum A Posteriori) pattern assignments
        map_df <- data.frame(
          Isoform = names(IsoMultiPP\$MAP),
          MAP_Pattern = IsoMultiPP\$MAP,
          stringsAsFactors = FALSE
        )
        write.csv(map_df, "isoform_map_patterns.csv", row.names = FALSE)
        
        # Save fold change results and full model output as RDS objects
        saveRDS(IsoMultiFC, "isoform_fold_changes.rds")
        saveRDS(IsoMultiOut, "ebseq_multi_out.rds")

    writeLines(c(
        '"BIOC_EBSEQ_ISOFORM_DE_MULTI_CONDITIONS":',
        paste0('    EBSeq: ', as.character(packageVersion('EBSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_isoform_de_multi_conditions.csv versions.yml
    """
}

workflow BIOC_EBSEQ_ISOFORM_DE_MULTI_CONDITIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ multi_condition_isoform_counts.csv, isoform_annotations.csv, multi_conditions.csv ] ]

    main:
    BIOC_EBSEQ_ISOFORM_DE_MULTI_CONDITIONS(ch_input)

    emit:
    tables   = BIOC_EBSEQ_ISOFORM_DE_MULTI_CONDITIONS.out.tables
    plots    = BIOC_EBSEQ_ISOFORM_DE_MULTI_CONDITIONS.out.plots
    objects  = BIOC_EBSEQ_ISOFORM_DE_MULTI_CONDITIONS.out.objects
    versions = BIOC_EBSEQ_ISOFORM_DE_MULTI_CONDITIONS.out.versions
}
