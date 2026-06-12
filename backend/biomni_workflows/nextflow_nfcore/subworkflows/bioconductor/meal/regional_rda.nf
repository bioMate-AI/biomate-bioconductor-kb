#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MEAL — regional_rda
// Determine if a specific genomic region is differentially methylated using Redundancy Analysis.
// Input: meth
// Container: quay.io/biocontainers/bioconductor-meal:1.28.0--r42hdfd78af_0
// R packages: GenomicRanges, MEAL, minfi
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, MEAL, minfi
// Visualizations: RDA plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run RDA on a target genomic range using runRDA
//  * 2. [Visualization & Output] Extract RDA association summaries and top hits using getAssociation, getRDAresults, and topRDAhits
//  * 3. [Visualization & Output] Visualize RDA dimensions and sample groupings using plotRDA

nextflow.enable.dsl = 2

process BIOC_MEAL_REGIONAL_RDA {
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
    .bm_deps <- c("GenomicRanges", "MEAL", "minfi", "SummarizedExperiment")
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
        
    # Load required libr    library(SummarizedExperiment)
aries
    library(MEAL)
    library(GenomicRanges)
    library(minfi)
    
    # Read input file from the working directory
    if (file.exists("meth")) {
      meth <- readRDS("meth")
    } else if (file.exists("meth.rds")) {
      meth <- readRDS("meth.rds")
    } else {
      stop("Input file 'meth' or 'meth.rds' (GenomicRatioSet) not found in the working directory.")
    }
    
    # Dynamically determine the phenotype variable (use the first one available)
    pheno_vars <- colnames(colData(meth))
    if (length(pheno_vars) == 0) {
      stop("No phenotypic variables found in the input object.")
    }
    pheno_var <- pheno_vars[1]
    model_formula <- as.formula(paste("~", pheno_var))
    
    # 1. Run RDA on a target genomic range using runRDA
    targetRange <- GRanges("chrX:13000000-23000000")
    resRDA <- runRDA(set = meth, model = model_formula, range = targetRange)
    
    # Save the RDA ResultSet object
    saveRDS(resRDA, "resRDA.rds")
    
    # 2. Extract RDA association summaries and top hits
    # Extract association (returns vegan rda object)
    assoc_rda <- getAssociation(resRDA, rid = "RDA")
    saveRDS(assoc_rda, "rda_association_object.rds")
    
    # Extract RDA results summary
    rda_res <- getRDAresults(resRDA)
    write.csv(as.data.frame(rda_res), "rda_results.csv", row.names = TRUE)
    
    # Extract top RDA hits
    top_hits <- topRDAhits(resRDA)
    write.csv(as.data.frame(top_hits), "top_rda_hits.csv", row.names = TRUE)
    
    # 3. Visualize RDA dimensions and sample groupings using plotRDA
    pdf("rda_plots.pdf", width = 8, height = 8)
    plotRDA(object = resRDA, pheno = colData(meth)[, pheno_var, drop = FALSE])
    plotRDA(object = resRDA, pheno = colData(meth)[, pheno_var, drop = FALSE])
    abline(h = -1)
    dev.off()

    writeLines(c(
        '"BIOC_MEAL_REGIONAL_RDA":',
        paste0('    MEAL: ', as.character(packageVersion('MEAL')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_regional_rda.csv versions.yml
    """
}

workflow BIOC_MEAL_REGIONAL_RDA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ meth ] ]

    main:
    BIOC_MEAL_REGIONAL_RDA(ch_input)

    emit:
    tables   = BIOC_MEAL_REGIONAL_RDA.out.tables
    plots    = BIOC_MEAL_REGIONAL_RDA.out.plots
    objects  = BIOC_MEAL_REGIONAL_RDA.out.objects
    versions = BIOC_MEAL_REGIONAL_RDA.out.versions
}
