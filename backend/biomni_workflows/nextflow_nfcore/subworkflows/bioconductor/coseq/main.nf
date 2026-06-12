#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: coseq — standard_coexpression_analysis
// Perform co-expression clustering directly on a raw count matrix using K-means or Gaussian mixture models, followed by model selection, parameter extraction, and
// Input: counts
// Container: quay.io/biocontainers/bioconductor-coseq:1.34.0--r45hdfd78af_0
// R packages: Biobase, corrplot, coseq, DESeq2, edgeR, ggforce
// Bioconductor: 3.20 | R: 4.4
// Requires: coseq
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run coseq with K-means and logclr transformation (or Normal model with arcsin/logit transformation)
//  * 2. [Core Analysis] Compare models using compareICL or compareARI
//  * 3. [Visualization & Output] Summarize the selected model using summary
//  * 4. [Core Analysis] Extract cluster labels using clusters and conditional probabilities using assay
//  * 5. [Core Analysis] Access transformed profiles using tcounts and normalized profiles using profiles
//  * 6. [Visualization & Output] Plot results using plot

nextflow.enable.dsl = 2

process BIOC_COSEQ_STANDARD_COEXPRESSION_ANALYSIS {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Biobase", "corrplot", "coseq", "DESeq2", "edgeR", "ggforce", "SummarizedExperiment")
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
    library(coseq)
    
    # 1. Read user input
    # The pipeline reads the 'counts' file from the working directory.
    # It supports common formats (plain, CSV, or TSV).
    if (file.exists("counts")) {
      counts <- as.matrix(read.table("counts", header=TRUE, row.names=1))
    } else if (file.exists("counts.csv")) {
      counts <- as.matrix(read.csv("counts.csv", header=TRUE, row.names=1))
    } else if (file.exists("counts.tsv")) {
      counts <- as.matrix(read.table("counts.tsv", header=TRUE, row.names=1, sep="\t"))
    } else {
      stop("Required input file 'counts' (or counts.csv/tsv) not found in the working directory.")
    }
    
    # 2. Run coseq with K-means and logclr transformation
    runLogCLR <- coseq(counts, K=2:25, transformation="logclr",norm="TMM", 
                          meanFilterCutoff=50, model="kmeans",
                       nstart=1, iter.max=10)
    saveRDS(runLogCLR, file="runLogCLR.rds")
    
    # 3. Run coseq with Normal model and arcsin/logit transformations
    runArcsin <- coseq(counts, K=2:20, model="Normal", transformation="arcsin", 
                       meanFilterCutoff=200, iter=10)
    saveRDS(runArcsin, file="runArcsin.rds")
    
    runLogit <- coseq(counts, K=2:20, model="Normal", transformation="logit", 
                      meanFilterCutoff=200, verbose=FALSE, iter=10)
    saveRDS(runLogit, file="runLogit.rds")
    
    # 4. Compare models using compareICL or compareARI
    pdf("icl_comparison.pdf")
    icl_comp <- compareICL(list(runArcsin, runLogit))
    print(icl_comp)
    dev.off()
    
    ari_comp <- compareARI(runArcsin, K=8:12)
    write.csv(as.data.frame(ari_comp), file="ari_comparison.csv")
    
    # 5. Summarize the selected model using summary
    sink("summary_runArcsin.txt")
    summary(runArcsin)
    sink()
    
    # 6. Plot results using plot
    pdf("boxplots_runArcsin.pdf")
    p <- plot(runArcsin, graphs="boxplots")
    if (is.list(p)) {
      for (name in names(p)) {
        print(p[[name]])
      }
    } else {
      print(p)
    }
    dev.off()
    
    # 7. Extract cluster labels using clusters and conditional probabilities using assay
    labels <- clusters(runArcsin)
    write.csv(data.frame(Gene=names(labels), Cluster=labels), file="cluster_labels.csv", row.names=FALSE)
    
    probapost <- assay(runArcsin)
    write.csv(as.data.frame(probapost), file="probapost.csv")
    
    # 8. Access transformed profiles using tcounts and normalized profiles using profiles
    trans_prof <- tcounts(runArcsin)
    write.csv(as.data.frame(trans_prof), file="transformed_profiles.csv")
    
    norm_prof <- profiles(runArcsin)
    write.csv(as.data.frame(norm_prof), file="normalized_profiles.csv")
    
    # 9. Extract full results
    fullres <- coseqFullResults(runArcsin)
    saveRDS(fullres, file="full_results.rds")

    writeLines(c(
        '"BIOC_COSEQ_STANDARD_COEXPRESSION_ANALYSIS":',
        paste0('    coseq: ', as.character(packageVersion('coseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_coexpression_analysis.csv versions.yml
    """
}

workflow BIOC_COSEQ_STANDARD_COEXPRESSION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts ] ]

    main:
    BIOC_COSEQ_STANDARD_COEXPRESSION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_COSEQ_STANDARD_COEXPRESSION_ANALYSIS.out.tables
    plots    = BIOC_COSEQ_STANDARD_COEXPRESSION_ANALYSIS.out.plots
    objects  = BIOC_COSEQ_STANDARD_COEXPRESSION_ANALYSIS.out.objects
    versions = BIOC_COSEQ_STANDARD_COEXPRESSION_ANALYSIS.out.versions
}
