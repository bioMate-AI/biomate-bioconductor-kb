#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HiCcompare — genome_wide_parallel_comparison
// Perform genome-wide joint normalization and difference detection across multiple chromosomes using total sum scaling and parallel processing on a cluster.
// Input: dat1.1000000.pixels.tsv, dat2.1000000.pixels.tsv
// Container: quay.io/biocontainers/bioconductor-hiccompare:1.32.0--r45hdfd78af_0
// R packages: BiocParallel, HiCcompare
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, HiCcompare
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read and split the genome-wide interaction tables by chromosome. 2. Create a list of chromosome-specific hic.table objects with sc

nextflow.enable.dsl = 2

process BIOC_HICCOMPARE_GENOME_WIDE_PARALLEL_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("BiocParallel", "HiCcompare")
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
    
    library(HiCcompare)
    library(BiocParallel)
    
    # Define input and output file paths
    file1 <- "dat1.1000000.pixels.tsv"
    file2 <- "dat2.1000000.pixels.tsv"
    out_table <- "hiccompare_results.tsv"
    out_rds <- "hiccompare_results.rds"
    out_pdf <- "hiccompare_plots.pdf"
    
    # Read the genome-wide sparse interaction tables
    dat1 <- read.table(file1, header=FALSE, col.names=c("chr1", "start1", "end1", "chr2", "start2", "end2", "IF"))
    dat2 <- read.table(file2, header=FALSE, col.names=c("chr1", "start1", "end1", "chr2", "start2", "end2", "IF"))
    
    # Filter for intrachromosomal interactions
    dat1 <- dat1[dat1\$chr1==dat1\$chr2, ]
    dat2 <- dat2[dat2\$chr1==dat2\$chr2, ]
    
    # Split the datasets by chromosome
    dat1 <- split(dat1, dat1\$chr1)
    dat2 <- split(dat2, dat2\$chr1)
    
    # Create a list of chromosome-specific hic.table objects with scale = FALSE
    hic.list <- mapply(create.hic.table, dat1, dat2, SIMPLIFY = FALSE, scale=FALSE)
    
    # Perform total sum scaling across all chromosomes
    hic.list <- total_sum(hic.list)
    
    # Register a parallel backend using BiocParallel
    if (.Platform\$OS.type == "windows") {
      register(SnowParam(workers = 2), default = TRUE)
    } else {
      register(MulticoreParam(workers = 2), default = TRUE)
    }
    
    # Open PDF device to capture diagnostic plots from normalization and comparison
    pdf(out_pdf, width = 10, height = 8)
    
    # Jointly normalize all chromosomes in parallel using hic_loess
    hic.list <- hic_loess(hic.list, Plot=TRUE, parallel=TRUE)
    
    # Detect differential interactions in parallel using hic_compare
    hic.list <- hic_compare(hic.list, A.min = NA, adjust.dist = TRUE, p.method = 'fdr', Plot = TRUE, parallel=TRUE)
    
    # Close the plotting device
    dev.off()
    
    # Combine results across all chromosomes
    hic.list <- do.call(rbind, hic.list)
    
    # Save the complete merged results to an RDS object
    saveRDS(hic.list, file = out_rds)
    
    # Filter results by adjusted p-value
    hic.list <- hic.list[hic.list\$p.adj<0.05,]
    
    # Write the significant differential interactions to a file
    write.table(hic.list, out_table, sep="\t", quote=FALSE, row.names=FALSE)

    writeLines(c(
        '"BIOC_HICCOMPARE_GENOME_WIDE_PARALLEL_COMPARISON":',
        paste0('    HiCcompare: ', as.character(packageVersion('HiCcompare')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genome_wide_parallel_comparison.csv versions.yml
    """
}

workflow BIOC_HICCOMPARE_GENOME_WIDE_PARALLEL_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dat1.1000000.pixels.tsv, dat2.1000000.pixels.tsv ] ]

    main:
    BIOC_HICCOMPARE_GENOME_WIDE_PARALLEL_COMPARISON(ch_input)

    emit:
    tables   = BIOC_HICCOMPARE_GENOME_WIDE_PARALLEL_COMPARISON.out.tables
    plots    = BIOC_HICCOMPARE_GENOME_WIDE_PARALLEL_COMPARISON.out.plots
    objects  = BIOC_HICCOMPARE_GENOME_WIDE_PARALLEL_COMPARISON.out.objects
    versions = BIOC_HICCOMPARE_GENOME_WIDE_PARALLEL_COMPARISON.out.versions
}
