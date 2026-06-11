#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RCM — constrained_rcm
// Perform constrained ordination to find variability explained by linear combinations of covariates, using linear or non-parametric response functions.
// Input: Zeller
// Container: quay.io/biocontainers/bioconductor-rcm:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RCM, phyloseq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit constrained RCM model (linear or nonparametric response functions)
//  * 2. [Visualization & Output] Plot samples, variables, species-sample biplots, species-variable biplots, or triplots
//  * 3. [Visualization & Output] Assess response function fit using residual plots (deviance or Pearson residuals, runs test)
//  * 4. [Core Analysis] Identify influential observations on the environmental gradient

nextflow.enable.dsl = 2

process BIOC_RCM_CONSTRAINED_RCM {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20"

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
    .bm_deps <- c("RCM", "phyloseq")
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
    library(RCM)
    library(phyloseq)
    
    # Read the input 'Zeller' phyloseq object from the working directory
    Zeller <- NULL
    if (file.exists("Zeller.rds")) {
      Zeller <- readRDS("Zeller.rds")
    } else if (file.exists("Zeller")) {
      Zeller <- tryCatch({
        readRDS("Zeller")
      }, error = function(e) {
        env <- new.env()
        load("Zeller", envir = env)
        env[[names(env)[1]]]
      })
    } else if (file.exists("Zeller.RData")) {
      env <- new.env()
      load("Zeller.RData", envir = env)
      Zeller <- env[[names(env)[1]]]
    } else {
      stop("Error: Input file 'Zeller' (phyloseq object) not found in the working directory.")
    }
    
    # Extract dynamic covariates to avoid hardcoding
    all_covs <- phyloseq::sample_variables(Zeller)
    if (length(all_covs) == 0) stop("No covariates found in phyloseq object.")
    use_covs <- head(all_covs, 5)
    cov1 <- use_covs[1]
    
    # Find categorical variables for shape mapping
    sample_df <- as(phyloseq::sample_data(Zeller), "data.frame")
    is_cat <- sapply(sample_df, function(x) is.factor(x) || is.character(x) || is.logical(x))
    cat_covs <- names(is_cat)[is_cat]
    shape_cov1 <- if (length(cat_covs) > 0) cat_covs[1] else NULL
    
    # Fit unconstrained RCM model (required for one of the downstream plotting calls)
    ZellerRCM2 = RCM(Zeller, k = 2, round = TRUE)
    
    # Fitting the constrained RCM models
    ZellerRCM2constr = RCM(Zeller, k = 2, round = TRUE, covariates = use_covs, responseFun = "linear")
    ZellerRCM2constrNonParam = RCM(Zeller, round = TRUE, k = 2, covariates = use_covs, responseFun = "nonparametric")
    
    # Save the fitted models to RDS files
    saveRDS(ZellerRCM2constr, "ZellerRCM2constr.rds")
    saveRDS(ZellerRCM2constrNonParam, "ZellerRCM2constrNonParam.rds")
    
    # Open PDF device to save all plots
    pdf("constrained_rcm_plots.pdf", width = 10, height = 8)
    
    # Plotting the constrained RCM model
    print(plot(ZellerRCM2constr, plotType = c("samples")))
    print(plot(ZellerRCM2constr, plotType = c("samples"), samColour = cov1, samShape = shape_cov1))
    print(plot(ZellerRCM2constr, plotType = "variables"))
    print(plot(ZellerRCM2constrNonParam, plotType = "variables"))
    
    # Extract coordinates and taxa dynamically for downstream plots
    zellerCoords <- extractCoord(ZellerRCM2constr)
    taxaSignals <- rowSums(zellerCoords\$species[, c("end1","end2")]^2)
    sortedTaxa <- taxa_names(ZellerRCM2constr\$physeq)[order(taxaSignals, decreasing = TRUE)]
    species1 <- sortedTaxa[1]
    sample_coord <- as.numeric(zellerCoords\$samples[1, c("Dim1", "Dim2")])
    var1 <- rownames(zellerCoords\$variables)[1]
    
    # Sample-taxon biplot
    print(plot(ZellerRCM2constr, plotType = c("species", "samples")))
    tmpPlot2 = plot(ZellerRCM2constr, plotType = c("species", "samples"), returnCoords = TRUE)
    print(addOrthProjection(tmpPlot2, species = species1, sample = sample_coord))
    
    # Variable-taxon biplot
    print(plot(ZellerRCM2constr, plotType = c("species", "variables")))
    tmpPlot3 = plot(ZellerRCM2constr, plotType = c("species", "variables"), returnCoords = TRUE)
    print(addOrthProjection(tmpPlot3, species = species1, variable = var1))
    
    # Triplot
    print(plot(ZellerRCM2constr))
    
    # Non-parametric response function plotting
    print(plotRespFun(ZellerRCM2constrNonParam, taxa = NULL, subdivisions = 50L, Palette = "Set1", angle = 90, axisTitleSize = 16, axisLabSize = 11, legendTitleSize = 18, legendLabSize = 12, samShape = shape_cov1, labSize = 5))
    
    topSpecies <- head(sortedTaxa, 2)
    print(plotRespFun(ZellerRCM2constrNonParam, Dim = 1, taxa = topSpecies, samShape = shape_cov1))
    
    # Assessing goodness of fit
    print(residualPlot(ZellerRCM2constr, whichTaxa = "response", numTaxa = 6))
    print(residualPlot(ZellerRCM2constr, whichTaxa = "response", resid = "Pearson", numTaxa = 6))
    print(residualPlot(ZellerRCM2constr, whichTaxa = "runs", resid = "Deviance", numTaxa = 6))
    
    # Identifying influential observations
    print(plot(ZellerRCM2constr, plotType = c("variables", "samples"), inflVar = var1))
    print(plot(ZellerRCM2constr, plotType = c("variables", "samples"), samColour = cov1))
    print(plot(ZellerRCM2constr, plotType = c("variables", "samples"), inflVar = var1, Influence = TRUE, inflDim = 2))
    print(plot(ZellerRCM2constr, plotType = c("variables", "samples"), inflVar = var1, samShape = shape_cov1))
    print(plot(ZellerRCM2, plotType = "samples", samSize = 2.5, inflVar = "psi"))
    print(plot(ZellerRCM2constr, plotType = "samples", samSize = 2.5, inflVar = "psi"))
    
    # Constrained RCM with few variables
    use_covs_few <- head(use_covs, 2)
    ZellerRCM3constr = RCM(Zeller, k = 2, round = TRUE, covariates = use_covs_few, responseFun = "linear")
    print(plot(ZellerRCM3constr, plotType = "samples", samColour = cov1, samShape = shape_cov1))
    
    # Close PDF device
    dev.off()
    
    # Save the final constrained model with few variables
    saveRDS(ZellerRCM3constr, "ZellerRCM3constr.rds")

    writeLines(c(
        '"BIOC_RCM_CONSTRAINED_RCM":',
        paste0('    RCM: ', as.character(packageVersion('RCM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_constrained_rcm.csv versions.yml
    """
}

workflow BIOC_RCM_CONSTRAINED_RCM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Zeller ] ]

    main:
    BIOC_RCM_CONSTRAINED_RCM(ch_input)

    emit:
    tables   = BIOC_RCM_CONSTRAINED_RCM.out.tables
    plots    = BIOC_RCM_CONSTRAINED_RCM.out.plots
    objects  = BIOC_RCM_CONSTRAINED_RCM.out.objects
    versions = BIOC_RCM_CONSTRAINED_RCM.out.versions
}
