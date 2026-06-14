#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: regioner — overlap_permutation_test
// Statistically evaluate whether two genomic region sets overlap more (or less) than expected by chance using a permutation test.
// Input: cpgHMM.txt, UCSC.promoters.hg19.bed
// Container: quay.io/biocontainers/bioconductor-regioner:1.42.0--r45hdfd78af_0
// R packages: knitr, regioneR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_REGIONER_OVERLAP_PERMUTATION_TEST {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-regioner:1.42.0--r45hdfd78af_0"

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
    .bm_deps <- c("knitr", "regioneR")
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
    library(regioneR)
    
    # Set seed for reproducibility
    set.seed(12345)
    
    # --- Load region sets using toGRanges from local files ---
    cpgHMM <- toGRanges("cpgHMM.txt")
    promoters <- toGRanges("UCSC.promoters.hg19.bed")
    
    # --- Filter out non-canonical chromosomes using ---
    cpgHMM <- filterChromosomes(cpgHMM, organism="hg", chr.type="canonical")
    promoters <- filterChromosomes(promoters, organism="hg", chr.type="canonical")
    
    # --- Subset regions to speed up analysis ---
    cpgHMM_2K <- sample(cpgHMM, 2000)
    
    # --- Run the permutation test using overlapPermTest ---
    pt <- overlapPermTest(cpgHMM_2K, promoters, ntimes=1000, genome="hg19", count.once=TRUE)
    
    # --- Plot the permutation test results and save to PDF ---
    pdf("overlap_permutation_test_plot.pdf", width = 8, height = 6)
    plot(pt)
    dev.off()
    
    # Save the permutation test object as RDS
    saveRDS(pt, file = "permutation_test_results.rds")
    
    # Extract and save meaningful results to a CSV table
    results_df <- data.frame(
      p_value = pt\$numOverlaps\$pval,
      z_score = pt\$numOverlaps\$zscore,
      ntimes = pt\$numOverlaps\$ntimes,
      observed = pt\$numOverlaps\$observed,
      alternative = pt\$numOverlaps\$alternative,
      mean_permuted = mean(pt\$numOverlaps\$permuted)
    )
    write.csv(results_df, file = "permutation_test_summary.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_REGIONER_OVERLAP_PERMUTATION_TEST":',
        paste0('        regioner: ', as.character(packageVersion("regioner")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_overlap_permutation_test.csv versions.yml
    """
}

workflow BIOC_REGIONER_OVERLAP_PERMUTATION_TEST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cpgHMM.txt, UCSC.promoters.hg19.bed ] ]

    main:
    BIOC_REGIONER_OVERLAP_PERMUTATION_TEST(ch_input)

    emit:
    tables   = BIOC_REGIONER_OVERLAP_PERMUTATION_TEST.out.tables
    plots    = BIOC_REGIONER_OVERLAP_PERMUTATION_TEST.out.plots
    objects  = BIOC_REGIONER_OVERLAP_PERMUTATION_TEST.out.objects
    versions = BIOC_REGIONER_OVERLAP_PERMUTATION_TEST.out.versions
}
