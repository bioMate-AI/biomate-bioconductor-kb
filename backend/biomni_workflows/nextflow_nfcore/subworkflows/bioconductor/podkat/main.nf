#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: podkat — continuous_trait_association_testing
// Perform association testing between a continuous trait (with covariates) and genotype data across partitioned genomic windows.
// Input: phenoFileLin.csv, example1.vcf.gz
// Container: quay.io/biocontainers/bioconductor-podkat:1.42.0--r45ha27e39d_1
// R packages: GenomicRanges, GWASTools, podkat
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, podkat
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load phenotype data and train a linear null model
//  * 2. [Visualization & Output] Load genomic regions and partition them into overlapping
//  * 3. [Visualization & Output] Load the genotype matrix from the VCF file
//  * 4. [Visualization & Output] Perform the association test
//  * 5. [Visualization & Output] Adjust p-values for multiple testing
//  * 6. [Visualization & Output] Visualize adjusted p-values using a Manhattan plot and

nextflow.enable.dsl = 2

process BIOC_PODKAT_CONTINUOUS_TRAIT_ASSOCIATION_TESTING {
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
    .bm_deps <- c("GenomicRanges", "GWASTools", "podkat")
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
    library(podkat)
    library(GenomicRanges)
    
    # Define input file paths as specified by the user
    phenoFileLin <- "phenoFileLin.csv"
    vcfFile <- "example1.vcf.gz"
    
    # --- Load phenotype data and train a linear null model ---
    pheno.c <- read.table(phenoFileLin, header=TRUE, sep=",")
    model.c <- nullModel(y ~ ., pheno.c)
    
    # --- Load genomic regions and partition them into overlapping ---
    # Extract the bounding genomic regions directly from the VCF file to generalize to any user data
    vInfo <- readVariantInfo(vcfFile)
    windows <- partitionRegions(range(vInfo))
    
    # --- Load the genotype matrix from the VCF file ---
    geno <- readGenotypeMatrix(vcfFile)
    
    # --- Perform the association test ---
    res.c <- assocTest(geno, model.c, windows)
    
    # --- Adjust p-values for multiple testing ---
    res.c <- p.adjust(res.c)
    
    # --- Visualize adjusted p-values using a Manhattan plot and ---
    pdf("manhattan_plot.pdf", width=9, height=4.5)
    plot(res.c, which="p.value.adj")
    dev.off()
    
    # Save meaningful results to output files
    write.csv(as.data.frame(res.c), "association_results.csv", row.names=FALSE)
    saveRDS(res.c, "association_results.rds")

    writeLines(c(
        '"BIOC_PODKAT_CONTINUOUS_TRAIT_ASSOCIATION_TESTING":',
        paste0('    podkat: ', as.character(packageVersion('podkat')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_continuous_trait_association_testing.csv versions.yml
    """
}

workflow BIOC_PODKAT_CONTINUOUS_TRAIT_ASSOCIATION_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ phenoFileLin.csv, example1.vcf.gz ] ]

    main:
    BIOC_PODKAT_CONTINUOUS_TRAIT_ASSOCIATION_TESTING(ch_input)

    emit:
    tables   = BIOC_PODKAT_CONTINUOUS_TRAIT_ASSOCIATION_TESTING.out.tables
    plots    = BIOC_PODKAT_CONTINUOUS_TRAIT_ASSOCIATION_TESTING.out.plots
    objects  = BIOC_PODKAT_CONTINUOUS_TRAIT_ASSOCIATION_TESTING.out.objects
    versions = BIOC_PODKAT_CONTINUOUS_TRAIT_ASSOCIATION_TESTING.out.versions
}
