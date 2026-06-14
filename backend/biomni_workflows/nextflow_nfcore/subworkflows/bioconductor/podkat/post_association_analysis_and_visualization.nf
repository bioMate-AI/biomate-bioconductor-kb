#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: podkat — post_association_analysis_and_visualization
// Filter significant association results, compute and plot the contributions of individual variants, and visualize genotypes for the most significant region.
// Input: res.c, geno, model.c, vcfFile, pheno.c
// Container: quay.io/biocontainers/bioconductor-podkat:1.42.0--r45ha27e39d_1
// R packages: podkat
// Bioconductor: 3.20 | R: 4.4
// Requires: podkat
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Adjust p-values using the Benjamini-Hochberg method
//  * 2. [Visualization & Output] Filter association results by adjusted p-value
//  * 3. [Visualization & Output] Compute variant weights and contributions for the
//  * 4. [Visualization & Output] Plot raw variant weights along the genome for the most
//  * 5. [Visualization & Output] Sort association results, read the genotype matrix for

nextflow.enable.dsl = 2

process BIOC_PODKAT_POST_ASSOCIATION_ANALYSIS_AND_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("podkat")
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
    library(podkat)
    
    # Define input file paths in the working directory
    res_c_file <- "res.c.rds"
    geno_file <- "geno.rds"
    model_c_file <- "model.c.rds"
    pheno_c_file <- "pheno.c.csv"
    vcf_file <- "vcfFile.vcf.gz"
    
    # Fallback for VCF file if unzipped version is provided
    if (!file.exists(vcf_file) && file.exists("vcfFile.vcf")) {
      vcf_file <- "vcfFile.vcf"
    }
    
    # Verify existence of required input files
    required_files <- c(res_c_file, geno_file, model_c_file, pheno_c_file, vcf_file)
    missing_files <- required_files[!file.exists(required_files)]
    if (length(missing_files) > 0) {
      stop(paste("Missing required input file(s):", paste(missing_files, collapse=", ")))
    }
    
    # Read user input files
    res.c <- readRDS(res_c_file)
    geno <- readRDS(geno_file)
    model.c <- readRDS(model_c_file)
    pheno.c <- read.csv(pheno_c_file, header=TRUE)
    vcfFile <- vcf_file
    
    # --- Adjust p-values using the Benjamini-Hochberg method ---
    res.c.adj <- p.adjust(res.c, method="BH")
    saveRDS(res.c.adj, "res.c.adj.rds")
    
    # --- Filter association results by adjusted p-value ---
    res.c.adj.f <- filterResult(res.c.adj, filterBy="p.value.adj")
    saveRDS(res.c.adj.f, "res.c.adj.f.rds")
    
    # Export filtered results to CSV if possible
    tryCatch({
      write.csv(as.data.frame(res.c.adj.f), "res.c.adj.f.csv", row.names=FALSE)
    }, error=function(e) {
      warning("Could not export res.c.adj.f to CSV: ", e\$message)
    })
    
    # --- Compute variant weights and contributions for the ---
    w.res.c.adj <- weights(res.c.adj.f, geno, model.c)
    saveRDS(w.res.c.adj, "w.res.c.adj.rds")
    
    # --- Plot raw variant weights along the genome for the most ---
    pdf("weight_raw_plot.pdf", width=8, height=6)
    plot(w.res.c.adj[[1]], "weight.raw", alongGenome=TRUE, type="b")
    dev.off()
    
    # --- Sort association results, read the genotype matrix for ---
    res.c.adj.sorted <- sort(res.c.adj, sortBy="p.value.adj")
    saveRDS(res.c.adj.sorted, "res.c.adj.sorted.rds")
    
    tryCatch({
      write.csv(as.data.frame(res.c.adj.sorted), "res.c.adj.sorted.csv", row.names=FALSE)
    }, error=function(e) {
      warning("Could not export res.c.adj.sorted to CSV: ", e\$message)
    })
    
    Zi <- readGenotypeMatrix(vcfFile, regions=res.c.adj.sorted[1])
    saveRDS(Zi, "Zi.rds")
    
    pdf("genotype_phenotype_plot.pdf", width=8, height=8)
    plot(Zi, y=pheno.c\$y, labRow=NA)
    dev.off()

    writeLines(c(
        '"BIOC_PODKAT_POST_ASSOCIATION_ANALYSIS_AND_VISUALIZATION":',
        paste0('    podkat: ', as.character(packageVersion('podkat')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_post_association_analysis_and_visualization.csv versions.yml
    """
}

workflow BIOC_PODKAT_POST_ASSOCIATION_ANALYSIS_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ res.c, geno, model.c, vcfFile, pheno.c ] ]

    main:
    BIOC_PODKAT_POST_ASSOCIATION_ANALYSIS_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_PODKAT_POST_ASSOCIATION_ANALYSIS_AND_VISUALIZATION.out.tables
    plots    = BIOC_PODKAT_POST_ASSOCIATION_ANALYSIS_AND_VISUALIZATION.out.plots
    objects  = BIOC_PODKAT_POST_ASSOCIATION_ANALYSIS_AND_VISUALIZATION.out.objects
    versions = BIOC_PODKAT_POST_ASSOCIATION_ANALYSIS_AND_VISUALIZATION.out.versions
}
