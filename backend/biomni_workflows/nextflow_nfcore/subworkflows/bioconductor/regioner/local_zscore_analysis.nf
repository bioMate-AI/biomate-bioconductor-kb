#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: regioner — local_zscore_analysis
// Evaluate whether a detected genomic association is highly dependent on the exact position of the regions (local effect) or is a broad regional effect.
// Input: Rad21.gz, Ctcf.gz
// Container: quay.io/biocontainers/bioconductor-regioner:1.42.0--r45hdfd78af_0
// R packages: regioneR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REGIONER_LOCAL_ZSCORE_ANALYSIS {
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
    .bm_deps <- c("regioneR")
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
    library(regioneR)
    
    # Set seed for reproducibility
    set.seed(12345)
    
    # --- Load region sets using toGRanges ---
    HepG2_Rad21 <- toGRanges(gzfile("Rad21.gz"), header=FALSE)
    HepG2_Ctcf <- toGRanges(gzfile("Ctcf.gz"), header=FALSE)
    promoters <- toGRanges("http://gattaca.imppc.org/regioner/data/UCSC.promoters.hg19.bed")
    
    # --- Filter chromosomes using filterChromosomes ---
    promoters <- filterChromosomes(promoters, organism="hg19")
    
    # --- Subset regions if necessary to speed up analysis ---
    HepG2_Rad21_5K <- sample(HepG2_Rad21, 5000)
    
    # --- Run the permutation test using permTest ---
    pt_Rad21_5k_vs_Ctcf <- permTest(A=HepG2_Rad21_5K, B=HepG2_Ctcf, ntimes=1000, randomize.function=circularRandomizeRegions, evaluate.function=numOverlaps, count.once=TRUE, genome="hg19", mc.set.seed=FALSE, mc.cores=4)
    
    # --- Calculate local Z-scores by shifting regions using ---
    lz_Rad21_vs_Ctcf_1 <- localZScore(A=HepG2_Rad21_5K, B=HepG2_Ctcf, pt=pt_Rad21_5k_vs_Ctcf, window=1000, step=50, count.once=TRUE)
    
    # --- Plot the local Z-score profile using plot and save to PDF ---
    pdf("local_zscore_plot.pdf", width=8, height=6)
    plot(lz_Rad21_vs_Ctcf_1, main="Rad21_5k vs CTCF (1Kbp)")
    dev.off()
    
    # Save meaningful results to RDS files
    saveRDS(pt_Rad21_5k_vs_Ctcf, "pt_Rad21_5k_vs_Ctcf.rds")
    saveRDS(lz_Rad21_vs_Ctcf_1, "lz_Rad21_vs_Ctcf_1.rds")
    
    # Export summary of permutation test to a text file
    sink("permutation_test_summary.txt")
    print(pt_Rad21_5k_vs_Ctcf)
    sink()

    writeLines(c(
        '"BIOC_REGIONER_LOCAL_ZSCORE_ANALYSIS":',
        paste0('        regioner: ', as.character(packageVersion("regioner")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_local_zscore_analysis.csv versions.yml
    """
}

workflow BIOC_REGIONER_LOCAL_ZSCORE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Rad21.gz, Ctcf.gz ] ]

    main:
    BIOC_REGIONER_LOCAL_ZSCORE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_REGIONER_LOCAL_ZSCORE_ANALYSIS.out.tables
    plots    = BIOC_REGIONER_LOCAL_ZSCORE_ANALYSIS.out.plots
    objects  = BIOC_REGIONER_LOCAL_ZSCORE_ANALYSIS.out.objects
    versions = BIOC_REGIONER_LOCAL_ZSCORE_ANALYSIS.out.versions
}
