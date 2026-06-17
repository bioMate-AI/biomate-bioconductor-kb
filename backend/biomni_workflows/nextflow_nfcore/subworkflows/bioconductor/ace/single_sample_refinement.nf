#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ACE — single_sample_refinement
// Perform detailed model fitting, standard adjustment, and visualization for a single sample to find the optimal cellularity and ploidy.
// Input: Segmented QDNAseq object.
// Container: quay.io/biocontainers/bioconductor-ace:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ACE, Biobase, QDNAseq, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] READ USER INPUT
//  * 2. [Visualization & Output] FIT SINGLE MODELS & PLOT COPY NUMBER PROFILES
//  * 3. [Visualization & Output] CONVERT OBJECT TO TEMPLATE
//  * 4. [Visualization & Output] PERFORM 2D GRID SEARCH USING SQUAREMODEL

nextflow.enable.dsl = 2

process BIOC_ACE_SINGLE_SAMPLE_REFINEMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("ACE", "Biobase", "QDNAseq", "ggplot2")
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
        library(ACE)
        library(Biobase)
        library(QDNAseq)
        library(ggplot2)
        
        # ==========================================
        # --- READ USER INPUT ---
        # ==========================================
        # Read the segmented QDNAseq object from the working directory
        object <- readRDS("copyNumbersSegmented.rds")
        
        # ==========================================
        # --- FIT SINGLE MODELS & PLOT COPY NUMBER PROFILES ---
        # ==========================================
        # Open PDF device to capture all plots
        pdf("single_sample_refinement_plots.pdf", width = 10, height = 7)
        
        # Fit single model for sample 1
        model1 <- singlemodel(object, QDNAseqobjectsample = 1)
        saveRDS(model1, "model1.rds")
        
        bestfit1 <- model1\$minima[tail(which(model1\$rerror==min(model1\$rerror)), 1)]
        besterror1 <- min(model1\$rerror)
        lastfit1 <- tail(model1\$minima, 1)
        lasterror1 <- tail(model1\$rerror, 1)
        
        # Plot copy number profiles for sample 1
        print(singleplot(object, QDNAseqobjectsample = 1, cellularity = bestfit1, 
                   error = besterror1, standard = model1\$standard, 
                   title = "sample1 - 2N fit 1"))
        
        print(singleplot(object, QDNAseqobjectsample = 1, cellularity = lastfit1, 
                   error = lasterror1, standard = model1\$standard, 
                   title = "sample1 - 2N fit 7"))
        
        # Plot error list for sample 1
        p1 <- model1\$errorplot + ggtitle("sample1 - errorlist") + 
          theme(plot.title = element_text(hjust = 0.5))
        print(p1)
        
        # Fit single model for sample 2 (changed to 1 to support single-sample objects)
        model2 <- singlemodel(object, QDNAseqobjectsample = 1)
        saveRDS(model2, "model2.rds")
        
        bestfit2 <- model2\$minima[tail(which(model2\$rerror==min(model2\$rerror)), 1)]
        besterror2 <- min(model2\$rerror)
        lastfit2 <- tail(model2\$minima, 1)
        lasterror2 <- tail(model2\$rerror, 1)
        
        # Plot copy number profiles for sample 2 (changed to 1)
        print(singleplot(object, QDNAseqobjectsample = 1, cellularity = bestfit2, error = besterror2, 
                   title = "sample1 - 2N fit 3"))
        
        print(singleplot(object, QDNAseqobjectsample = 1, cellularity = lastfit2, error = lasterror2, 
                   title = "sample1 - 2N fit 6"))
        
        # Plot error list for sample 2 (changed to 1)
        p2 <- model2\$errorplot + ggtitle("sample1 - errorlist (model 2)") + 
          theme(plot.title = element_text(hjust = 0.5))
        print(p2)
        
        # Fit single model for sample 2 (changed to 1) with ploidy = 3
        model <- singlemodel(object, QDNAseqobjectsample = 1, ploidy = 3)
        saveRDS(model, "model_ploidy3.rds")
        
        # Print model details to console/log
        print(ls(model))
        print(model\$minima)
        print(model\$rerror)
        print(model\$errorplot)
        
        bestfit_ploidy3 <- model\$minima[tail(which(model\$rerror==min(model\$rerror)), 1)]
        
        # Plot copy number profile for sample 2 (changed to 1) with ploidy = 3
        print(singleplot(object, QDNAseqobjectsample = 1, cellularity = bestfit_ploidy3, ploidy = 3))
        
        # ==========================================
        # --- CONVERT OBJECT TO TEMPLATE ---
        # ==========================================
        template <- objectsampletotemplate(object, index = 1)
        write.csv(template, "template_sample1.csv", row.names = FALSE)
        
        print(head(template))
        print(head(na.exclude(template)))
        print(median(na.exclude(template\$segments)))
        print(unique(na.exclude(template\$segments)))
        
        segmentdata <- rle(as.vector(na.exclude(template\$segments)))
        plot(rep(segmentdata\$values, segmentdata\$lengths))
        
        # Fit single model on template with custom standard
        custom_standard <- unique(na.exclude(template\$segments))[1]
        model_template <- singlemodel(template, ploidy = 2, standard = custom_standard)
        saveRDS(model_template, "model_template_custom_standard.rds")
        
        df_minima_error <- data.frame(model_template\$minima, model_template\$rerror)
        write.csv(df_minima_error, "template_minima_error.csv", row.names = FALSE)
        
        bestfit_template <- model_template\$minima[tail(which(model_template\$rerror==min(model_template\$rerror)), 1)]
        print(singleplot(template, cellularity = bestfit_template, ploidy = 2, standard = custom_standard))
        
        # ==========================================
        # --- PERFORM 2D GRID SEARCH USING SQUAREMODEL ---
        # ==========================================
        sqmodel <- squaremodel(template)
        saveRDS(sqmodel, "sqmodel_default.rds")
        
        print(ls(sqmodel))
        p_sky <- sqmodel\$matrixplot + ggtitle("Sky on fire")
        print(p_sky)
        
        write.csv(head(sqmodel\$minimadf, 10), "sqmodel_default_top10_minima.csv", row.names = FALSE)
        
        # Squaremodel with penalty
        sqmodel_penalized <- squaremodel(template, penalty = 0.5, penploidy = 0.5)
        print(sqmodel_penalized\$matrixplot)
        
        # Squaremodel with custom range and resolution
        sqmodel_custom <- squaremodel(template, prows = 150, ptop = 3.3, pbottom = 1.8, 
                                      penalty = 0.5, penploidy = 0.5)
        saveRDS(sqmodel_custom, "sqmodel_custom.rds")
        print(sqmodel_custom\$matrixplot)
        
        write.csv(head(sqmodel_custom\$minimadf, 10), "sqmodel_custom_top10_minima.csv", row.names = FALSE)
        
        # Plot final selected fit from squaremodel
        best_sq_cellularity <- sqmodel_custom\$minimadf\$cellularity[1]
        best_sq_ploidy <- sqmodel_custom\$minimadf\$ploidy[1]
        print(singleplot(template, cellularity = best_sq_cellularity, ploidy = best_sq_ploidy))
        
        # Close PDF device
        dev.off()

    writeLines(c(
        '"BIOC_ACE_SINGLE_SAMPLE_REFINEMENT":',
        paste0('    ACE: ', as.character(packageVersion('ACE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_sample_refinement.csv versions.yml
    """
}

workflow BIOC_ACE_SINGLE_SAMPLE_REFINEMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Segmented QDNAseq object. ] ]

    main:
    BIOC_ACE_SINGLE_SAMPLE_REFINEMENT(ch_input)

    emit:
    tables   = BIOC_ACE_SINGLE_SAMPLE_REFINEMENT.out.tables
    plots    = BIOC_ACE_SINGLE_SAMPLE_REFINEMENT.out.plots
    objects  = BIOC_ACE_SINGLE_SAMPLE_REFINEMENT.out.objects
    versions = BIOC_ACE_SINGLE_SAMPLE_REFINEMENT.out.versions
}
