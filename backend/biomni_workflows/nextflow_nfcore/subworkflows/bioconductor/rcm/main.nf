#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RCM — unconstrained_rcm
// Perform exploratory unconstrained ordination of microbiome read count data, visualize samples and taxa, assess goodness of fit, and test cluster significance.
// Input: Zeller
// Container: quay.io/biocontainers/bioconductor-rcm:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RCM, phyloseq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit unconstrained RCM model (with optional conditioning on confounders)
//  * 2. [Visualization & Output] Plot samples, species, or biplots
//  * 3. [Core Analysis] Assess goodness of fit using deviance residuals
//  * 4. [Core Analysis] Test significance of sample clustering using PERMANOVA
//  * 5. [Core Analysis] Extract coordinates and identify top contributing taxa

nextflow.enable.dsl = 2

process BIOC_RCM_UNCONSTRAINED_RCM {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

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
    
    # Read the user input file 'Zeller' from the working directory
    # Supporting RDS, RData, or extensionless files robustly
    if (file.exists("Zeller")) {
      Zeller = tryCatch(readRDS("Zeller"), error = function(e) {
        env = new.env()
        load("Zeller", envir = env)
        env[[ls(env)[1]]]
      })
    } else if (file.exists("Zeller.rds")) {
      Zeller = readRDS("Zeller.rds")
    } else if (file.exists("Zeller.RData")) {
      env = new.env()
      load("Zeller.RData", envir = env)
      Zeller = env[[ls(env)[1]]]
    } else {
      stop("Required input file 'Zeller' (phyloseq object) not found in the working directory!")
    }
    
    # Extract dynamic variables to avoid hardcoding
    sample_vars <- phyloseq::sample_variables(Zeller)
    if (length(sample_vars) == 0) stop("Phyloseq object must have sample metadata.")
    var_diag <- sample_vars[1]
    var_country <- sample_vars[min(2, length(sample_vars))]
    var_gender <- sample_vars[min(3, length(sample_vars))]
    
    rank_names_all <- phyloseq::rank_names(Zeller)
    tax_col <- if (length(rank_names_all) > 0) rank_names_all[1] else NULL
    
    # Open PDF device to save all generated plots
    pdf("unconstrained_rcm_plots.pdf", width = 10, height = 8)
    
    # 1. Fitting the unconstrained RCM
    ZellerRCM2 = RCM(Zeller, k = 2, round = TRUE)
    ZellerRCM3 = RCM(Zeller, k = 3, round = TRUE)
    ZellerRCM2cond = RCM(Zeller, k = 2, round = TRUE, confounders = c(var_country))
    
    # Extracting coordinates early to dynamically determine top taxa for plotting
    zellerCoords = extractCoord(ZellerRCM2)
    taxaSignals = rowSums(zellerCoords\$species[, c("end1", "end2")]^2)
    sortedTaxa = taxa_names(ZellerRCM2\$physeq)[order(taxaSignals, decreasing = TRUE)]
    top_taxa1 = sortedTaxa[1]
    taxa_regexp = substr(top_taxa1, 1, 5)
    
    # 2. Plotting the unconstrained RCM
    print(plot(ZellerRCM2, plotType = "samples"))
    print(plot(ZellerRCM2, plotType = "samples", samColour = var_diag))
    print(plot(ZellerRCM2, plotType = "samples", samColour = "Shannon"))
    print(plot(ZellerRCM2, plotType = "species"))
    print(plot(ZellerRCM2, plotType = "species", taxRegExp = taxa_regexp, taxLabels = TRUE))
    if (!is.null(tax_col)) {
      print(plot(ZellerRCM2, plotType = "species", taxLabels = TRUE, taxCol = tax_col))
    } else {
      print(plot(ZellerRCM2, plotType = "species", taxLabels = TRUE))
    }
    print(plot(ZellerRCM2, taxNum = 10, samColour = var_diag))
    
    # Adding projections
    tmpPlot = plot(ZellerRCM2, taxNum = 10, samColour = var_diag, returnCoords = TRUE)
    print(addOrthProjection(tmpPlot, species = top_taxa1, sample = c(-1.2, 1.5)))
    print(plot(ZellerRCM3, Dim = c(1, 3), samColour = var_diag, taxNum = 6))
    
    # Assessing goodness of fit
    print(plot(ZellerRCM2, plotType = "samples", samColour = "Deviance", samSize = 2.5))
    print(plot(ZellerRCM3, plotType = "species", taxCol = "Deviance", samSize = 2.5, Dim = c(1, 2), arrowSize = 0.5))
    
    # Testing significance of clusters using PERMANOVA
    permanovaZeller = permanova(ZellerRCM2, var_diag)
    permanovaZellerGender = permanova(ZellerRCM2, var_gender, verbose = FALSE)
    
    # Importance of dimensions
    print(plot(ZellerRCM2cond, plotPsi = "psi"))
    print(plot(ZellerRCM2cond, plotPsi = "loglik"))
    print(plot(ZellerRCM2cond, plotPsi = "inertia"))
    
    # Extracting coordinates
    # (Coordinates and sorted taxa were extracted earlier for dynamic plotting)
    sortedTaxa[1:10]
    
    # Non-squared plots
    print(plot(ZellerRCM2, axesFixed = FALSE))
    
    # Close PDF device
    dev.off()
    
    # Save fitted models to RDS files
    saveRDS(ZellerRCM2, "ZellerRCM2.rds")
    saveRDS(ZellerRCM3, "ZellerRCM3.rds")
    saveRDS(ZellerRCM2cond, "ZellerRCM2cond.rds")
    
    # Save extracted coordinates to CSV files
    write.csv(zellerCoords\$samples, "zeller_coords_samples.csv", row.names = TRUE)
    write.csv(zellerCoords\$species, "zeller_coords_species.csv", row.names = TRUE)
    
    # Save PERMANOVA test results to a text file
    sink("permanova_results.txt")
    cat("=== PERMANOVA: ", var_diag, " ===\n", sep="")
    print(permanovaZeller)
    cat("\n=== PERMANOVA: ", var_gender, " ===\n", sep="")
    print(permanovaZellerGender)
    sink()
    
    # Save top 10 contributing taxa to a text file
    writeLines(sortedTaxa[1:10], "top_10_taxa.txt")

    writeLines(c(
        '"BIOC_RCM_UNCONSTRAINED_RCM":',
        paste0('    RCM: ', as.character(packageVersion('RCM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_unconstrained_rcm.csv versions.yml
    """
}

workflow BIOC_RCM_UNCONSTRAINED_RCM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Zeller ] ]

    main:
    BIOC_RCM_UNCONSTRAINED_RCM(ch_input)

    emit:
    tables   = BIOC_RCM_UNCONSTRAINED_RCM.out.tables
    plots    = BIOC_RCM_UNCONSTRAINED_RCM.out.plots
    objects  = BIOC_RCM_UNCONSTRAINED_RCM.out.objects
    versions = BIOC_RCM_UNCONSTRAINED_RCM.out.versions
}
