#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scrapper — multimodal_rna_adt_analysis
// Analyze single-cell datasets containing both RNA-seq and CITE-seq (ADT) modalities.
// Input: sce.s
// Container: quay.io/biocontainers/bioconductor-scrapper:1.4.0--r45ha27e39d_0
// R packages: SingleCellExperiment, scater, scrapper
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, scater, scrapper
// Visualizations: ordination plot, UMAP plot, cluster plot
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare alternative experiments
//  * 2. [Core Analysis] Identify mitochondrial and IgG control features
//  * 3. [Core Analysis] Run multi-modal analysis with analyze.se()
//  * 4. [Visualization & Output] Visualize joint clustering
//  * 5. [Core Analysis] Inspect modality-specific markers with previewMarkers()

nextflow.enable.dsl = 2

process BIOC_SCRAPPER_MULTIMODAL_RNA_ADT_ANALYSIS {
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
    .bm_deps <- c("SingleCellExperiment", "scater", "scrapper")
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
        library(scrapper)
        library(scater)
        
        # 1. Read the user input file
        if (file.exists("sce.s")) {
            sce.s <- readRDS("sce.s")
        } else if (file.exists("sce.s.rds")) {
            sce.s <- readRDS("sce.s.rds")
        } else {
            stop("Error: Input file 'sce.s' or 'sce.s.rds' not found in the working directory.")
        }
        
        # 2. Prepare alternative experiments
        adts <- altExps(sce.s)
        if (length(adts) > 0) {
            altExp(sce.s, "all.adts") <- do.call(rbind, as.list(adts))
            for (aname in names(adts)) {
                altExp(sce.s, aname) <- NULL
            }
        }
        
        # 3. Identify mitochondrial and IgG control features
        is.mito <- grepl("^MT-", rownames(sce.s))
        is.igg <- grepl("^IgG", rownames(altExp(sce.s, 'all.adts')))
        
        # 4. Run multi-modal analysis with analyze.se()
        multi_res <- analyze.se(
            sce.s,
            adt.altexp="all.adts",
            rna.qc.subsets=list(mito=is.mito),
            adt.qc.subsets=list(igg=is.igg),
            num.threads=2
        )
        
        # 5. Visualize joint clustering and save plot
        pdf("umap_joint_clustering.pdf", width=8, height=6)
        p <- plotReducedDim(multi_res\$x, "UMAP", colour_by="graph.cluster")
        print(p)
        dev.off()
        
        # 6. Inspect modality-specific markers with previewMarkers() and save tables
        # By default, markers are sorted by the mean Cohen's d.
        # We just replace the column name when printing the dataframe here.
        adt_markers <- previewMarkers(multi_res\$markers\$adt[[1]], c(effect="cohens.d.mean"))
        write.csv(as.data.frame(adt_markers), "adt_markers_cluster1.csv", row.names=TRUE)
        
        # Using the delta-detected to focus on silent-to-expressed genes.
        rna_markers <- previewMarkers(multi_res\$markers\$rna[[1]], order.by="delta.detected.mean")
        write.csv(as.data.frame(rna_markers), "rna_markers_cluster1.csv", row.names=TRUE)
        
        # Save the complete analysis results object
        saveRDS(multi_res, "multi_res.rds")

    writeLines(c(
        '"BIOC_SCRAPPER_MULTIMODAL_RNA_ADT_ANALYSIS":',
        paste0('    scrapper: ', as.character(packageVersion('scrapper')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multimodal_rna_adt_analysis.csv versions.yml
    """
}

workflow BIOC_SCRAPPER_MULTIMODAL_RNA_ADT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce.s ] ]

    main:
    BIOC_SCRAPPER_MULTIMODAL_RNA_ADT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCRAPPER_MULTIMODAL_RNA_ADT_ANALYSIS.out.tables
    plots    = BIOC_SCRAPPER_MULTIMODAL_RNA_ADT_ANALYSIS.out.plots
    objects  = BIOC_SCRAPPER_MULTIMODAL_RNA_ADT_ANALYSIS.out.objects
    versions = BIOC_SCRAPPER_MULTIMODAL_RNA_ADT_ANALYSIS.out.versions
}
