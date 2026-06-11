#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: snpstats — data_input
// Load SNP genotype data from PED/INFO, PLINK, or long-format text files into SnpMatrix objects.
// Input: sample.ped.gz, sample.info, sample.bed, sample.bim, sample.fam, sample-long.gz, sample-long-alleles.gz
// Container: quay.io/biocontainers/bioconductor-snpstats:1.60.0--r45h01b2380_0
// R packages: hexbin, snpStats
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SNPSTATS_DATA_INPUT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-snpstats:1.60.0--r45h01b2380_0"

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
    .bm_deps <- c("hexbin", "snpStats")
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
    
    # Load the required Bioconductor package
    library(snpStats)
    
    # -----------------------------------------------------------------------------
    # Stage 1: Read PED/INFO files using read.pedfile
    # -----------------------------------------------------------------------------
    
    # Define paths to the user-provided input files in the working directory
    pedfile <- "sample.ped.gz"
    infofile <- "sample.info"
    
    # Load the PED genotype data and SNP info
    sample <- read.pedfile(pedfile, snps=infofile)
    
    # Save meaningful results from the PED import stage
    saveRDS(sample, "ped_sample.rds")
    write.csv(col.summary(sample\$genotypes), "ped_col_summary.csv", row.names=TRUE)
    write.csv(sample\$fam, "ped_fam.csv", row.names=TRUE)
    write.csv(sample\$map, "ped_map.csv", row.names=TRUE)
    
    # -----------------------------------------------------------------------------
    # Stage 2: Read PLINK files using read.plink
    # -----------------------------------------------------------------------------
    
    # Define paths to the user-provided PLINK files in the working directory
    fam <- "sample.fam"
    bim <- "sample.bim"
    bed <- "sample.bed"
    
    # Load the complete PLINK dataset
    sample <- read.plink(bed, bim, fam)
    
    # Save meaningful results from the PLINK import stage
    saveRDS(sample, "plink_sample.rds")
    write.csv(col.summary(sample\$genotypes), "plink_col_summary.csv", row.names=TRUE)
    write.csv(sample\$fam, "plink_fam.csv", row.names=TRUE)
    write.csv(sample\$map, "plink_map.csv", row.names=TRUE)
    
    # Load a subset of SNPs (columns 6 to 10) from the PLINK dataset
    subset <- read.plink(bed, bim, fam, select.snps=6:10)
    
    # Save the subset results
    saveRDS(subset, "plink_subset.rds")
    write.csv(col.summary(subset\$genotypes), "plink_subset_col_summary.csv", row.names=TRUE)
    write.csv(subset\$map, "plink_subset_map.csv", row.names=TRUE)
    
    # -----------------------------------------------------------------------------
    # Stage 3: Read long-format files using read.long
    # -----------------------------------------------------------------------------
    
    # Define path to the user-provided long-format genotype file
    longfile <- "sample-long.gz"
    
    # Load long-format genotype data with specified fields, codes, and confidence threshold
    gdata <- read.long(longfile, fields=c(snp=1, sample=2, genotype=3, confidence=4), gcodes=c("1", "2", "3"), threshold=0.95)
    
    # Save the long-format genotype results
    saveRDS(gdata, "long_genotypes.rds")
    sink("long_genotypes_summary.txt")
    print(summary(gdata))
    sink()
    
    # Define path to the user-provided long-format allele file
    allelesfile <- "sample-long-alleles.gz"
    
    # Load long-format allele data with specified fields and confidence threshold
    gdata <- read.long(allelesfile, fields=c(snp=1, sample=2, allele.A=3, allele.B=4, confidence=5), threshold=0.95)
    
    # Save the long-format allele results
    saveRDS(gdata, "long_alleles.rds")
    sink("long_alleles_summary.txt")
    print(summary(gdata))
    sink()

    writeLines(c(
        '"BIOC_SNPSTATS_DATA_INPUT":',
        paste0('        snpstats: ', as.character(packageVersion("snpstats")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_data_input.csv versions.yml
    """
}

workflow BIOC_SNPSTATS_DATA_INPUT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample.ped.gz, sample.info, sample.bed, sample.bim, sample.fam, sample-long.gz, sample-long-alleles.gz ] ]

    main:
    BIOC_SNPSTATS_DATA_INPUT(ch_input)

    emit:
    tables   = BIOC_SNPSTATS_DATA_INPUT.out.tables
    plots    = BIOC_SNPSTATS_DATA_INPUT.out.plots
    objects  = BIOC_SNPSTATS_DATA_INPUT.out.objects
    versions = BIOC_SNPSTATS_DATA_INPUT.out.versions
}
