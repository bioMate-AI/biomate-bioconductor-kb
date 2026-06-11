#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: methimpute — enrichment_analysis
// Perform enrichment analysis of methylation levels and recalibrated methylation levels around genomic annotations (e.g., genes, transposable elements).
// Input: model, annotations.RData
// Container: quay.io/biocontainers/bioconductor-methimpute:1.32.0--r45ha27e39d_0
// R packages: GenomicRanges, ggplot2, methimpute
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, ggplot2, methimpute
// Visualizations: enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define categories to distinguish missing from covered cytosines in the model data
//  * 2. [Core Analysis] Set sequence lengths on the model data to match the annotation
//  * 3. [Visualization & Output] Plot enrichment around annotations

nextflow.enable.dsl = 2

process BIOC_METHIMPUTE_ENRICHMENT_ANALYSIS {
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
    .bm_deps <- c("GenomicRanges", "ggplot2", "methimpute")
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
    library(methimpute)
    library(GenomicRanges)
    library(ggplot2)
    
    # 1. Read User Inputs
    # Read the fitted methimpute model object
    if (file.exists("model")) {
      model <- readRDS("model")
    } else if (file.exists("model.rds")) {
      model <- readRDS("model.rds")
    } else {
      # Fallback to loading as RData if saved using save()
      env_model <- new.env()
      load("model", envir = env_model)
      model <- env_model[[ls(env_model)[1]]]
    }
    
    # Read the genomic annotations
    annot_env <- new.env()
    load("annotations.RData", envir = annot_env)
    
    # Find GRanges objects inside annotations.RData
    annot_names <- ls(annot_env)
    is_gr <- sapply(annot_names, function(x) inherits(annot_env[[x]], "GRanges"))
    gr_names <- annot_names[is_gr]
    
    if (length(gr_names) == 0) {
      stop("No GRanges objects found in annotations.RData")
    }
    
    # 2. Define categories to distinguish missing from covered cytosines in the model data
    model\$data\$category <- factor('covered', levels=c('missing', 'covered'))
    model\$data\$category[model\$data\$counts[,'total']>=1] <- 'covered'
    model\$data\$category[model\$data\$counts[,'total']==0] <- 'missing'
    
    # 3. Process each annotation found in the input file
    for (annot_name in gr_names) {
      annot_obj <- annot_env[[annot_name]]
      
      # Set sequence lengths on the model data to match the annotation
      seqlengths(model\$data) <- seqlengths(annot_obj)[seqlevels(model\$data)]
      
      # Plot enrichment around annotations
      plots <- plotEnrichment(model\$data, annotation=annot_obj, range = 2000,
                              category.column = 'category')
      
      # Save the resulting plots to a PDF file
      pdf_file <- paste0("enrichment_", annot_name, ".pdf")
      pdf(pdf_file, width = 10, height = 8)
      print(plots + ggtitle(paste("Enrichment around", annot_name)))
      dev.off()
      
      # Save the plot objects as an RDS file for downstream customization
      rds_file <- paste0("enrichment_", annot_name, "_plots.rds")
      saveRDS(plots, file = rds_file)
    }

    writeLines(c(
        '"BIOC_METHIMPUTE_ENRICHMENT_ANALYSIS":',
        paste0('    methimpute: ', as.character(packageVersion('methimpute')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_enrichment_analysis.csv versions.yml
    """
}

workflow BIOC_METHIMPUTE_ENRICHMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ model, annotations.RData ] ]

    main:
    BIOC_METHIMPUTE_ENRICHMENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METHIMPUTE_ENRICHMENT_ANALYSIS.out.tables
    plots    = BIOC_METHIMPUTE_ENRICHMENT_ANALYSIS.out.plots
    objects  = BIOC_METHIMPUTE_ENRICHMENT_ANALYSIS.out.objects
    versions = BIOC_METHIMPUTE_ENRICHMENT_ANALYSIS.out.versions
}
