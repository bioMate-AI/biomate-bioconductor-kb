#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tigre — affymetrix_time_series_analysis
// Analyze Affymetrix time series data to learn GP models, rank targets, and export results.
// Input: embryo_tc_array_data
// Container: quay.io/biocontainers/bioconductor-tigre:1.64.0--r45h01b2380_0
// R packages: affy, annotate, puma, tigre
// Bioconductor: 3.20 | R: 4.4
// Requires: affy, annotate, puma, tigre
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and preprocess CEL files using ReadAffy and mmgmos
//  * 2. [Core Analysis] Format data for GP modeling using processData
//  * 3. [Core Analysis] Learn single-target, joint multi-target, or translation-free models using GPLearn
//  * 4. [Visualization & Output] Plot models using GPPlot
//  * 5. [Core Analysis] Rank candidate targets using GPRankTargets
//  * 6. [Core Analysis] Recreate top models using generateModels
//  * 7. [Visualization & Output] Export scores and models to an SQLite database using export.scores

nextflow.enable.dsl = 2

process BIOC_TIGRE_AFFYMETRIX_TIME_SERIES_ANALYSIS {
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
    .bm_deps <- c("affy", "annotate", "puma", "tigre")
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
    library(affy)
    library(puma)
    library(tigre)
    library(annotate)
    
    # 1. Load and preprocess CEL files using ReadAffy and mmgmos
    expfiles <- c(paste("embryo_tc_4_", 1:12, ".CEL", sep=""),
                  paste("embryo_tc_6_", 1:12, ".CEL", sep=""),
                  paste("embryo_tc_8_", 1:12, ".CEL", sep=""))
    
    n_experiments <- 3
    n_timepoints <- 12
    
    # Ensure the files exist; if not, list whatever CEL files are in the directory
    if (!all(file.exists(file.path("embryo_tc_array_data", expfiles)))) {
      expfiles <- list.files("embryo_tc_array_data", pattern="\\\\.CEL\$", ignore.case=TRUE)
      
      if (length(expfiles) > 0) {
        # Extract numeric identifiers to properly sort and group files
        extract_nums <- function(f) {
          nums <- as.numeric(regmatches(f, gregexpr("[0-9]+", f))[[1]])
          if (length(nums) >= 2) tail(nums, 2) else c(0, if (length(nums)) nums[1] else 0)
        }
        nums_mat <- do.call(rbind, lapply(expfiles, extract_nums))
        
        # Sort files by experiment, then by time
        ord <- order(nums_mat[, 1], nums_mat[, 2])
        expfiles <- expfiles[ord]
        nums_mat <- nums_mat[ord, , drop=FALSE]
        
        n_exp_unique <- length(unique(nums_mat[, 1]))
        n_time_unique <- length(unique(nums_mat[, 2]))
        
        # Dynamically determine the number of experiments and time points
        if (n_exp_unique * n_time_unique == length(expfiles)) {
          n_experiments <- n_exp_unique
          n_timepoints <- n_time_unique
        } else {
          # Fallback if not a perfect grid
          if (length(expfiles) %% 3 == 0) {
            n_experiments <- 3
            n_timepoints <- length(expfiles) / 3
          } else {
            n_experiments <- 1
            n_timepoints <- length(expfiles)
          }
        }
      }
    }
    
    expdata <- ReadAffy(filenames=expfiles,
                        celfile.path="embryo_tc_array_data")
    
    pData(expdata) <- data.frame("time.h" = rep(seq_len(n_timepoints), n_experiments),
                                 row.names=rownames(pData(expdata)))
    
    drosophila_mmgmos_exprs <- mmgmos(expdata)
    drosophila_mmgmos_fragment <- drosophila_mmgmos_exprs
    
    # 2. Format data for GP modeling using processData
    drosophila_gpsim_fragment <-
      processData(drosophila_mmgmos_fragment,
                  experiments=rep(seq_len(n_experiments), each=n_timepoints))
    
    # Define targets
    targets <- c('FBgn0003486', 'FBgn0033188', 'FBgn0035257')
    
    # Load gene annotations
    aliasMapping <- getAnnMap("ALIAS2PROBE",
                      annotation(drosophila_gpsim_fragment))
    twi <- get('twi', env=aliasMapping)
    
    fbgnMapping <- getAnnMap("FLYBASE2PROBE",
                     annotation(drosophila_gpsim_fragment))
    targetProbes <- mget(targets, env=fbgnMapping)
    
    # 3. Learn single-target, joint multi-target, or translation-free models using GPLearn
    st_models <- list()
    for (i in seq(along=targetProbes)) {
      st_models[[i]] <- GPLearn(drosophila_gpsim_fragment,
                                TF=twi, targets=targetProbes[i],
                                quiet=TRUE)
    }
    
    mt_model <- GPLearn(drosophila_gpsim_fragment, TF=twi,
                        targets=targetProbes,
                        quiet=TRUE)
    show(mt_model)
    
    nt_model <- GPLearn(drosophila_gpsim_fragment,
                        targets=c(twi, targetProbes[1:2]), quiet=TRUE)
    
    # Save learned models to RDS
    saveRDS(st_models, "single_target_models.rds")
    saveRDS(mt_model, "multi_target_model.rds")
    saveRDS(nt_model, "translation_free_model.rds")
    
    # 4. Plot models using GPPlot (saving to a PDF file)
    pdf("gp_models_plots.pdf", width=10, height=8)
    GPPlot(st_models[[1]], nameMapping=getAnnMap("FLYBASE",
                             annotation(drosophila_gpsim_fragment)))
    GPPlot(mt_model, nameMapping=getAnnMap("FLYBASE",
                       annotation(drosophila_gpsim_fragment)))
    GPPlot(nt_model, nameMapping=getAnnMap("FLYBASE",
                       annotation(drosophila_gpsim_fragment)))
    dev.off()
    
    # 5. Rank candidate targets using GPRankTargets (without known targets)
    scores <- GPRankTargets(drosophila_gpsim_fragment, TF=twi,
                            testTargets=targetProbes,
                            options=list(quiet=TRUE),
                            filterLimit=1.8)
    scores <- sort(scores, decreasing=TRUE)
    scores_mat <- write.scores(scores)
    
    # Save first ranking results to CSV safely
    if (!is.null(scores_mat)) {
      write.csv(as.data.frame(scores_mat), "ranking_scores_basic.csv")
    } else {
      captured <- capture.output(write.scores(scores))
      writeLines(captured, "ranking_scores_basic.csv")
    }
    
    # 6. Recreate top models using generateModels
    topmodel <- generateModels(drosophila_gpsim_fragment,
                               scores[1])
    show(topmodel)
    saveRDS(topmodel, "top_model.rds")
    
    # Rank candidate targets using GPRankTargets (with known targets)
    scores <- GPRankTargets(drosophila_gpsim_fragment, TF=twi,
                            knownTargets=targetProbes[1],
                            testTargets=targetProbes[2:3],
                            options=list(quiet=TRUE),
                            filterLimit=1.8)
    scores <- sort(scores, decreasing=TRUE)
    scores_mat2 <- write.scores(scores)
    
    # Save second ranking results to CSV safely
    if (!is.null(scores_mat2)) {
      write.csv(as.data.frame(scores_mat2), "ranking_scores_with_known.csv")
    } else {
      captured <- capture.output(write.scores(scores))
      writeLines(captured, "ranking_scores_with_known.csv")
    }
    
    # Generate models for the final scores to pass to export.scores
    models <- generateModels(drosophila_gpsim_fragment, scores)
    
    # 7. Export scores and models to an SQLite database using export.scores
    export.scores(scores, datasetName='Drosophila',
                  experimentSet='GPSIM/GPDISIM',
                  database='database.sqlite',
                  preprocData=drosophila_gpsim_fragment,
                  models=models,
                  aliasTypes=c('SYMBOL', 'GENENAME', 'FLYBASE', 'ENTREZID'))

    writeLines(c(
        '"BIOC_TIGRE_AFFYMETRIX_TIME_SERIES_ANALYSIS":',
        paste0('    tigre: ', as.character(packageVersion('tigre')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_affymetrix_time_series_analysis.csv versions.yml
    """
}

workflow BIOC_TIGRE_AFFYMETRIX_TIME_SERIES_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ embryo_tc_array_data ] ]

    main:
    BIOC_TIGRE_AFFYMETRIX_TIME_SERIES_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TIGRE_AFFYMETRIX_TIME_SERIES_ANALYSIS.out.tables
    plots    = BIOC_TIGRE_AFFYMETRIX_TIME_SERIES_ANALYSIS.out.plots
    objects  = BIOC_TIGRE_AFFYMETRIX_TIME_SERIES_ANALYSIS.out.objects
    versions = BIOC_TIGRE_AFFYMETRIX_TIME_SERIES_ANALYSIS.out.versions
}
