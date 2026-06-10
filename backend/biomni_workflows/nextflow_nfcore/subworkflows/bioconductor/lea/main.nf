#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: lea — population_structure_and_imputation
// Analyze population genetic structure, identify genetic clusters, perform population differentiation tests, and impute missing genotypes.
// Input: genotypes.lfmm, genotypes.geno, genoM.lfmm
// Container: quay.io/biocontainers/bioconductor-lea:3.22.0--r45h01b2380_0
// R packages: knitr, LEA
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LEA_POPULATION_STRUCTURE_AND_IMPUTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-lea:3.22.0--r45h01b2380_0"

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
    .bm_deps <- c("knitr", "LEA")
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
    
    # Load required library
    library(LEA)
    
    # Verify that the required input files exist in the working directory
    required_files <- c("genotypes.lfmm", "genotypes.geno", "genoM.lfmm")
    for (f in required_files) {
      if (!file.exists(f)) {
        stop(paste("Required input file missing in the working directory:", f))
      }
    }
    
    # Define colors for ancestry plotting
    my.colors <- c("tomato", "lightblue", "olivedrab", "gold")
    
    # ==========================================
    # Stage 1: Principal Component Analysis (PCA)
    # ==========================================
    message("Running PCA...")
    pc = pca("genotypes.lfmm", scale = TRUE)
    tw = tracy.widom(pc)
    
    # Save PCA results
    saveRDS(pc, "pca_object.rds")
    saveRDS(tw, "tracy_widom_results.rds")
    
    # Plot the percentage of variance explained
    pdf("pca_screeplot.pdf", width = 6, height = 6)
    plot(tw\$percentage, pch = 19, col = "darkblue", cex = .8)
    dev.off()
    
    # ==========================================
    # Stage 2 & 3: sNMF and Cross-Entropy Evaluation
    # ==========================================
    message("Running sNMF for K = 1 to 10...")
    project = snmf("genotypes.geno", K = 1:10, entropy = TRUE, repetitions = 10, project = "new")
    
    # Save sNMF project object
    saveRDS(project, "snmf_project.rds")
    
    # Plot cross-entropy criterion
    pdf("snmf_cross_entropy.pdf", width = 6, height = 6)
    plot(project, col = "blue", pch = 19, cex = 1.2)
    dev.off()
    
    # ==========================================
    # Stage 4: Visualize Ancestry Proportions (Q-matrix)
    # ==========================================
    message("Visualizing ancestry proportions for K = 4...")
    best = which.min(cross.entropy(project, K = 4))
    
    pdf("ancestry_barchart.pdf", width = 10, height = 6)
    barchart(project, K = 4, run = best, border = NA, space = 0, col = my.colors, xlab = "Individuals", ylab = "Ancestry proportions", main = "Ancestry matrix") -> bp
    axis(1, at = 1:length(bp\$order), labels = bp\$order, las=1, cex.axis = .4)
    dev.off()
    
    # Export Q-matrix to CSV
    q_matrix <- Q(project, K = 4, run = best)
    write.csv(q_matrix, "ancestry_proportions_K4.csv", row.names = FALSE)
    
    # ==========================================
    # Stage 5: Population Differentiation Tests
    # ==========================================
    message("Conducting population differentiation tests...")
    p = snmf.pvalues(project, entropy = TRUE, ploidy = 2, K = 4)
    pvalues = p\$pvalues
    
    # Save p-values to CSV
    write.csv(data.frame(Locus = 1:length(pvalues), Pvalue = pvalues), "snmf_pvalues.csv", row.names = FALSE)
    
    # Plot p-values histogram and Manhattan-style plot
    pdf("pvalues_plots.pdf", width = 8, height = 8)
    par(mfrow = c(2,1))
    hist(pvalues, col = "orange")
    plot(-log10(pvalues), pch = 19, col = "blue", cex = .5)
    dev.off()
    
    # ==========================================
    # Stage 6: Missing Genotype Imputation
    # ==========================================
    message("Running sNMF on dataset with missing values...")
    project.missing = snmf("genoM.lfmm", K = 4, entropy = TRUE, repetitions = 10, project = "new")
    
    # Save missing project object
    saveRDS(project.missing, "snmf_project_missing.rds")
    
    # Select the best run and impute missing genotypes
    best = which.min(cross.entropy(project.missing, K = 4))
    impute(project.missing, "genoM.lfmm", method = 'mode', K = 4, run = best)
    
    # Read and save the imputed genotype matrix
    dat.imp = read.lfmm("genoM.lfmm_imputed.lfmm")
    saveRDS(dat.imp, "imputed_genotypes_matrix.rds")
    
    message("Pipeline completed successfully. All outputs saved to the working directory.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_LEA_POPULATION_STRUCTURE_AND_IMPUTATION":
        lea: \$(Rscript -e 'cat(as.character(packageVersion("lea")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_population_structure_and_imputation.csv versions.yml
    """
}

workflow BIOC_LEA_POPULATION_STRUCTURE_AND_IMPUTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genotypes.lfmm, genotypes.geno, genoM.lfmm ] ]

    main:
    BIOC_LEA_POPULATION_STRUCTURE_AND_IMPUTATION(ch_input)

    emit:
    tables   = BIOC_LEA_POPULATION_STRUCTURE_AND_IMPUTATION.out.tables
    plots    = BIOC_LEA_POPULATION_STRUCTURE_AND_IMPUTATION.out.plots
    objects  = BIOC_LEA_POPULATION_STRUCTURE_AND_IMPUTATION.out.objects
    versions = BIOC_LEA_POPULATION_STRUCTURE_AND_IMPUTATION.out.versions
}
