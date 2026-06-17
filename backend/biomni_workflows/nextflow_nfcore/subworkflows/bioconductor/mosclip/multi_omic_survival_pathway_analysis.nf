#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MOSClip — multi_omic_survival_pathway_analysis
// Test survival association of entire pathways using topology-guided data reduction and visualize results.
// Input: multiOmicsTopo_data.RData, pathways.RData
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MOSClip, MultiAssayExperiment, survival
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load multi-omic data with topological settings and pathway topologies
//  * 2. [Core Analysis] Run survival pathway test using multiOmicsSurvivalPathwayTest
//  * 3. [Visualization & Output] Plot multi-pathway report using plotMultiPathwayReport
//  * 4. [Visualization & Output] Plot heatmap of original omic profiles for pathway genes using plotPathwayHeat
//  * 5. [Visualization & Output] Plot Kaplan-Meier survival curves for pathways using plotPathwayKM

nextflow.enable.dsl = 2

process BIOC_MOSCLIP_MULTI_OMIC_SURVIVAL_PATHWAY_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("MOSClip", "MultiAssayExperiment", "survival", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
       library(MOSClip)
        library(MultiAssayExperiment)
        library(survival)
        
        # 1. Load multi-omic data with topological settings and pathway topologies
        # Read user input files from the working directory
        env_topo <- new.env()
        load("multiOmicsTopo_data.RData", envir = env_topo)
        topo_objs <- ls(env_topo)
        if ("multiOmicsTopo" %in% topo_objs) {
          multiOmicsTopo <- env_topo\$multiOmicsTopo
        } else {
          multiOmicsTopo <- env_topo[[topo_objs[1]]]
        }
        
        env_pathways <- new.env()
        load("pathways.RData", envir = env_pathways)
        pathway_objs <- ls(env_pathways)
        if ("reactSmall" %in% pathway_objs) {
          reactSmall <- env_pathways\$reactSmall
        } else {
          reactSmall <- env_pathways[[pathway_objs[1]]]
        }
        
        # Prepare genes to consider and additional annotations
        omic_names <- names(experiments(multiOmicsTopo))
        genesToConsider <- row.names(experiments(multiOmicsTopo)[[1]])
        
        additionalA <- colData(multiOmicsTopo)
        additionalA\$status[additionalA\$status == 1] <- "event"
        additionalA\$status[additionalA\$status == 0] <- "no_event"
        additionalA\$PFS <- as.factor(additionalA\$status)
        additionalA\$status <- NULL
        additionalA\$years <- round(additionalA\$days/365.24, 0)
        additionalA\$days <- NULL
        
        # 2. Run survival pathway test using multiOmicsSurvivalPathwayTest
        pathwaySurv <- lapply(reactSmall, function(g) {
          set.seed(1234)
          fcl = multiOmicsSurvivalPathwayTest(multiOmicsTopo, g, 
                                              useTheseGenes = genesToConsider)
          })
        
        # Save the raw pathway survival results
        saveRDS(pathwaySurv, file = "pathwaySurv_results.rds")
        
        # 3. Plot multi-pathway report using plotMultiPathwayReport
        pdf("multi_pathway_report.pdf", width = 8, height = 6)
        omic_colors <- setNames(rep(c("red", "blue", "yellow", "green", "purple", "orange", "cyan", "magenta"), length.out = length(omic_names)), omic_names)
        plotMultiPathwayReport(pathwaySurv, 
                               MOcolors = omic_colors)
        dev.off()
        
        # Dynamically select the first pathway and its covariates for plotting
        pathway_name <- if (!is.null(names(pathwaySurv))) names(pathwaySurv)[1] else 1
        pw_res <- pathwaySurv[[pathway_name]]
        
        covs <- character(0)
        if (isS4(pw_res)) {
          if ("cox" %in% slotNames(pw_res)) covs <- names(coef(slot(pw_res, "cox")))
          else if ("data" %in% slotNames(pw_res)) covs <- setdiff(colnames(slot(pw_res, "data")), c("days", "status"))
        } else if (is.list(pw_res)) {
          if ("cox" %in% names(pw_res)) covs <- names(coef(pw_res\$cox))
          else if ("coefficients" %in% names(pw_res)) covs <- names(coef(pw_res))
          else if ("data" %in% names(pw_res)) covs <- setdiff(colnames(pw_res\$data), c("days", "status"))
        }
        
        if (length(covs) > 0) {
          plot_covs <- covs[1:min(2, length(covs))]
          km_formula <- paste("Surv(days, status) ~", paste(plot_covs, collapse = " + "))
          heat_sort <- c(plot_covs, "PFS")
        } else {
          km_formula <- "Surv(days, status) ~ 1"
          heat_sort <- c("PFS")
        }
        
        # 4. Plot heatmap of original omic profiles for pathway genes using plotPathwayHeat
        pdf("pathway_heatmap.pdf", width = 10, height = 8)
        plotPathwayHeat(pathwaySurv[[pathway_name]], 
                        sortBy = heat_sort, 
                        paletteNames = omic_colors, 
                        additionalAnnotations = additionalA, 
                        additionalPaletteNames = list(PFS = "violet", years = "teal"), 
                        withSampleNames = FALSE)
        dev.off()
        
        # 5. Plot Kaplan-Meier survival curves for pathways using plotPathwayKM
        pdf("pathway_km.pdf", width = 8, height = 6)
        plotPathwayKM(pathwaySurv[[pathway_name]], 
                      formula = km_formula, 
                      paletteNames = "Paired")
        dev.off()

    writeLines(c(
        '"BIOC_MOSCLIP_MULTI_OMIC_SURVIVAL_PATHWAY_ANALYSIS":',
        paste0('    MOSClip: ', as.character(packageVersion('MOSClip')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_omic_survival_pathway_analysis.csv versions.yml
    """
}

workflow BIOC_MOSCLIP_MULTI_OMIC_SURVIVAL_PATHWAY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ multiOmicsTopo_data.RData, pathways.RData ] ]

    main:
    BIOC_MOSCLIP_MULTI_OMIC_SURVIVAL_PATHWAY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MOSCLIP_MULTI_OMIC_SURVIVAL_PATHWAY_ANALYSIS.out.tables
    plots    = BIOC_MOSCLIP_MULTI_OMIC_SURVIVAL_PATHWAY_ANALYSIS.out.plots
    objects  = BIOC_MOSCLIP_MULTI_OMIC_SURVIVAL_PATHWAY_ANALYSIS.out.objects
    versions = BIOC_MOSCLIP_MULTI_OMIC_SURVIVAL_PATHWAY_ANALYSIS.out.versions
}
