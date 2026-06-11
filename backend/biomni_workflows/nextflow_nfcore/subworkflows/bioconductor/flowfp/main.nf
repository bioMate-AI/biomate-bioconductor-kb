#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowFP — fingerprint_generation_and_plexing
// Create a probability binning model from flow cytometry data, generate fingerprints, and combine them into a plex for multi-model or multi-resolution analysis.
// Input: fs1, fs2
// Container: quay.io/biocontainers/bioconductor-flowfp:1.68.0--r45h01b2380_0
// R packages: flowCore, flowFP
// Bioconductor: 3.20 | R: 4.4
// Requires: flowCore, flowFP
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build a probability binning model using flowFPModel
//  * 2. [Core Analysis] Generate fingerprints for the dataset using flowFP
//  * 3. [Core Analysis] Combine multiple fingerprints into a flowFPPlex
//  * 4. [Core Analysis] Dynamically adjust resolution using nRecursions and append to the plex
//  * 5. [Visualization & Output] Visualize fingerprints using plot

nextflow.enable.dsl = 2

process BIOC_FLOWFP_FINGERPRINT_GENERATION_AND_PLEXING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20"

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
    .bm_deps <- c("flowCore", "flowFP")
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
        library(flowCore)
        library(flowFP)
        
        # Read user input files from the working directory
        fs1 <- readRDS("fs1.rds")
        fs2 <- readRDS("fs2.rds")
        
        # Stage 1: Build a probability binning model using flowFPModel
        pdf("01_model_plot.pdf")
        mod <- flowFPModel(fs1, name="Model_fs1", nRecursions=7)
        plot(mod)
        dev.off()
        
        # Save the model object
        saveRDS(mod, "flowFP_model.rds")
        
        # Stage 2: Generate fingerprints for the dataset using flowFP
        fp <- flowFP (fs1, mod)
        show(fp)
        
        pdf("02_fingerprint_stack_plot.pdf")
        plot (fp, type="stack")
        dev.off()
        
        # Save fingerprint counts
        write.csv(counts(fp), "fingerprint_counts.csv", row.names=TRUE)
        
        # Stage 3: Combine multiple fingerprints into a flowFPPlex
        mod1 <- flowFPModel(fs1, name="Model vs fs1", nRecursions=7)
        mod2 <- flowFPModel(fs2, name="Model vs fs2", nRecursions=7)
        fp1_1 <- flowFP (fs1, mod1)
        fp1_2 <- flowFP (fs1, mod2)
        plex <- flowFPPlex(c(fp1_1, fp1_2))
        
        pdf("03_plex_grid_plot.pdf")
        plot (plex, type='grid', vert_scale=10)
        dev.off()
        
        # Save plex counts
        write.csv(counts(plex), "plex_grid_counts.csv", row.names=TRUE)
        
        # Stage 4: Dynamically adjust resolution using nRecursions and append to the plex
        fp <- flowFP (fs1, nRecursions=8)
        plex <- flowFPPlex()
        for (levels in 8:5) {
        	nRecursions(fp) <- levels
        	plex <- append (plex, fp)
        }
        
        # Stage 5: Visualize fingerprints using plot
        pdf("04_plex_tangle_plot.pdf")
        plot (plex, type="tangle", transformation="norm")
        dev.off()
        
        # Save final plex object and its counts
        saveRDS(plex, "final_plex.rds")
        write.csv(counts(plex, transformation="normalize"), "plex_tangle_normalized_counts.csv", row.names=TRUE)

    writeLines(c(
        '"BIOC_FLOWFP_FINGERPRINT_GENERATION_AND_PLEXING":',
        paste0('    flowFP: ', as.character(packageVersion('flowFP')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fingerprint_generation_and_plexing.csv versions.yml
    """
}

workflow BIOC_FLOWFP_FINGERPRINT_GENERATION_AND_PLEXING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fs1, fs2 ] ]

    main:
    BIOC_FLOWFP_FINGERPRINT_GENERATION_AND_PLEXING(ch_input)

    emit:
    tables   = BIOC_FLOWFP_FINGERPRINT_GENERATION_AND_PLEXING.out.tables
    plots    = BIOC_FLOWFP_FINGERPRINT_GENERATION_AND_PLEXING.out.plots
    objects  = BIOC_FLOWFP_FINGERPRINT_GENERATION_AND_PLEXING.out.objects
    versions = BIOC_FLOWFP_FINGERPRINT_GENERATION_AND_PLEXING.out.versions
}
