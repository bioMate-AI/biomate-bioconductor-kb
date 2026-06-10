#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: hilda — mutational_signature_burden_testing
// Read mutation position data, perform global and local Bayesian tests to compare signature burdens between two groups, assess MCMC convergence, and visualize the
// Input: inputFile
// Container: quay.io/biocontainers/bioconductor-hilda:1.24.0--r45ha27e39d_0
// R packages: BiocStyle, cowplot, ggplot2, HiLDA
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HILDA_MUTATIONAL_SIGNATURE_BURDEN_TESTING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-hilda:1.24.0--r45ha27e39d_0"

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
    .bm_deps <- c("BiocStyle", "cowplot", "ggplot2", "HiLDA")
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
    library(HiLDA)
    library(cowplot)
    library(ggplot2)
    
    # Define the input file path (exactly as specified in the working directory)
    inputFile <- "inputFile"
    
    # 1. Read mutation position data
    G <- hildaReadMPFile(inputFile, numBases=5, trDir=TRUE)
    
    # 2. Perform global and local Bayesian tests (without initial values)
    set.seed(123)
    hildaGlobal_initial <- hildaTest(inputG=G, numSig=3, localTest=FALSE, refGroup=1:4, nIter=1000)
    hildaLocal_initial <- hildaTest(inputG=G, numSig=3, localTest=TRUE, refGroup=1:4, nIter=1000)
    
    # 3. Estimate initial signature parameters using pmgetSignature
    Param <- pmgetSignature(G, K = 3)
    
    # 4. Perform global and local Bayesian tests with initial values to accelerate MCMC
    set.seed(123)
    hildaGlobal <- hildaTest(inputG=G, numSig=3, useInits = Param, localTest=TRUE, refGroup=1:4, nIter=1000)
    hildaLocal <- hildaTest(inputG=G, numSig=3, useInits = Param, localTest=TRUE, refGroup=1:4, nIter=1000)
    
    # 5. Assess MCMC convergence using hildaRhat
    rhat_global <- hildaRhat(hildaGlobal)
    rhat_local <- hildaRhat(hildaLocal)
    
    # Save convergence statistics to a CSV file
    rhat_df <- data.frame(
      Model = c("Global", "Local"),
      Rhat = c(rhat_global, rhat_local)
    )
    write.csv(rhat_df, "hilda_mcmc_convergence_rhat.csv", row.names = FALSE)
    
    # 6. Visualize the signatures and exposure differences
    
    # Plot 1: Standard signature estimation and visualization from pmsignature
    pmPlots <- pmBarplot(G, Param, refGroup=1:4, sigOrder=c(1,3,2))
    pdf("pmsignature_barplot.pdf", width = 10, height = 6)
    print(cowplot::plot_grid(pmPlots\$sigPlot, pmPlots\$propPlot, rel_widths = c(1,3)))
    dev.off()
    
    # Plot 2: Signature visualization from HiLDA
    hildaPlots <- hildaBarplot(G, hildaLocal, refGroup=1:4, sigOrder=c(1,3,2))
    pdf("hilda_barplot.pdf", width = 10, height = 6)
    print(cowplot::plot_grid(pmPlots\$sigPlot, pmPlots\$propPlot, rel_widths = c(1,3)))
    dev.off()
    
    # Plot 3: Posterior distribution of the mean difference in exposures
    hildaDiffPlots <- hildaDiffPlot(G, hildaLocal, sigOrder=c(1,3,2))
    pdf("hilda_diff_plot.pdf", width = 10, height = 6)
    print(cowplot::plot_grid(hildaDiffPlots\$sigPlot, hildaDiffPlots\$diffPlot, rel_widths = c(1,3)))
    dev.off()
    
    # Save key R objects for downstream analysis
    saveRDS(G, "mutation_feature_data.rds")
    saveRDS(Param, "estimated_signatures_param.rds")
    saveRDS(hildaGlobal, "hilda_global_test_results.rds")
    saveRDS(hildaLocal, "hilda_local_test_results.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_HILDA_MUTATIONAL_SIGNATURE_BURDEN_TESTING":
        hilda: \$(Rscript -e 'cat(as.character(packageVersion("hilda")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mutational_signature_burden_testing.csv versions.yml
    """
}

workflow BIOC_HILDA_MUTATIONAL_SIGNATURE_BURDEN_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ inputFile ] ]

    main:
    BIOC_HILDA_MUTATIONAL_SIGNATURE_BURDEN_TESTING(ch_input)

    emit:
    tables   = BIOC_HILDA_MUTATIONAL_SIGNATURE_BURDEN_TESTING.out.tables
    plots    = BIOC_HILDA_MUTATIONAL_SIGNATURE_BURDEN_TESTING.out.plots
    objects  = BIOC_HILDA_MUTATIONAL_SIGNATURE_BURDEN_TESTING.out.objects
    versions = BIOC_HILDA_MUTATIONAL_SIGNATURE_BURDEN_TESTING.out.versions
}
