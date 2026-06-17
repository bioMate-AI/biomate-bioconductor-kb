#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RVS — gene_based_partial_sharing
// Perform joint analysis of multiple rare variants within a gene, allowing for partial sharing among affected relatives.
// Input: family_variants.vcf, pedigree_structures.rds
// Container: quay.io/biocontainers/bioconductor-rvs:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RVS, VariantAnnotation, kinship2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load pedigree structures from RDS
//  * 2. [Input & Preparation] Precompute sharing probabilities, carrier subset sizes,
//  * 3. [Input & Preparation] Load VCF file and convert to SnpMatrix objects
//  * 4. [Input & Preparation] Align SnpMatrix objects and pedigree objects into named
//  * 5. [Input & Preparation] Run the gene-based joint analysis using RVgene
//  * 6. [Input & Preparation] Save outputs

nextflow.enable.dsl = 2

process BIOC_RVS_GENE_BASED_PARTIAL_SHARING {
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
    .bm_deps <- c("RVS", "kinship2", "VariantAnnotation")
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
    library(RVS)
    library(kinship2)
    library(VariantAnnotation)
    
    # --- Load pedigree structures from RDS ---
    if (!file.exists("pedigree_structures.rds")) {
      stop("Error: pedigree_structures.rds not found in the working directory.")
    }
    pedigrees <- readRDS("pedigree_structures.rds")
    
    # Use all pedigrees provided in the RDS
    samplePedigrees <- pedigrees
    
    # Extract family names dynamically
    fam_names <- names(samplePedigrees)
    if (is.null(fam_names)) {
      fam_names <- sapply(samplePedigrees, function(p) as.character(p\$famid[1]))
      if (any(is.null(fam_names)) || any(is.na(fam_names))) {
        fam_names <- paste0("fam", seq_along(samplePedigrees))
      }
      names(samplePedigrees) <- fam_names
    }
    
    # --- Precompute sharing probabilities, carrier subset sizes, ---
    ex.pattern.prob.list <- list()
    ex.N.list <- list()
    ex.nequiv.list <- list()
    
    for (fam_name in names(samplePedigrees)) {
      ped <- samplePedigrees[[fam_name]]
      
      # Dynamically determine carriers (affected final descendants)
      father_ids <- ped\$id[ped\$findex[!is.na(ped\$findex) & ped\$findex > 0]]
      mother_ids <- ped\$id[ped\$mindex[!is.na(ped\$mindex) & ped\$mindex > 0]]
      fd <- ped\$id[!(ped\$id %in% father_ids) & !(ped\$id %in% mother_ids)]
      
      if (!is.null(ped\$affected)) {
        aff <- if (is.matrix(ped\$affected)) ped\$affected[, 1] else ped\$affected
        if (any(aff == 2, na.rm = TRUE)) {
          fd <- intersect(fd, ped\$id[aff == 2])
        } else if (any(aff == 1, na.rm = TRUE)) {
          fd <- intersect(fd, ped\$id[aff == 1])
        }
      }
      carriers <- fd
      
      if (length(carriers) == 0) {
        warning(paste("No carriers found for family", fam_name))
        next
      }
      
      carrier.sets <- list()
      for (i in length(carriers):1) {
        carrier.sets <- c(carrier.sets, combn(carriers, i, simplify = FALSE))
      }
      
      pattern.prob <- sapply(carrier.sets, function(vec) RVsharing(ped, carriers = vec))
      N.vec <- sapply(carrier.sets, length)
      nequiv.vec <- rep(1, length(carrier.sets))
      
      ex.pattern.prob.list[[fam_name]] <- pattern.prob
      ex.N.list[[fam_name]] <- N.vec
      ex.nequiv.list[[fam_name]] <- nequiv.vec
    }
    
    # --- Load VCF file and convert to SnpMatrix objects ---
    if (!file.exists("family_variants.vcf")) {
      stop("Error: family_variants.vcf not found in the working directory.")
    }
    # Added the required 'genome' argument to prevent runtime errors
    vcf_all <- readVcf("family_variants.vcf", genome = "hg19")
    vcf_samples <- colnames(vcf_all)
    
    # --- Align SnpMatrix objects and pedigree objects into named ---
    ex.SnpMatrix.list <- list()
    ex.ped.obj <- list()
    
    for (fam_name in names(samplePedigrees)) {
      # Only process families that have precomputed probabilities
      if (!fam_name %in% names(ex.pattern.prob.list)) next
      
      ped <- samplePedigrees[[fam_name]]
      ped_ids <- as.character(ped\$id)
      
      samples_fam <- intersect(vcf_samples, ped_ids)
      
      if (length(samples_fam) > 0) {
        fam.vcf <- vcf_all[, samples_fam, drop = FALSE]
        fam.snp <- VariantAnnotation::genotypeToSnpMatrix(fam.vcf)
        ex.SnpMatrix.list[[fam_name]] <- fam.snp\$genotypes
        ex.ped.obj[[fam_name]] <- ped
      } else {
        warning(paste("No matching samples in VCF for family", fam_name))
      }
    }
    
    # Determine sites dynamically to avoid out-of-bounds errors
    if (length(ex.SnpMatrix.list) > 0) {
      num_snps <- min(sapply(ex.SnpMatrix.list, ncol))
    } else {
      num_snps <- 0
    }
    
    # Replaced arbitrary fallback logic with a robust selection of all available sites
    if (num_snps > 0) {
      sites <- seq_len(num_snps)
    } else {
      sites <- integer(0)
    }
    
    # --- Run the gene-based joint analysis using RVgene ---
    if (length(ex.SnpMatrix.list) > 0 && length(sites) > 0) {
      results <- RVgene(
        ex.SnpMatrix.list,
        ex.ped.obj,
        sites,
        pattern.prob.list = ex.pattern.prob.list[names(ex.SnpMatrix.list)],
        nequiv.list = ex.nequiv.list[names(ex.SnpMatrix.list)],
        N.list = ex.N.list[names(ex.SnpMatrix.list)],
        type = "count"
      )
      
      # --- Save outputs ---
      # Save results as RDS
      saveRDS(results, "rvgene_results.rds")
      
      # Save results as CSV
      results_df <- data.frame(
        p = results\$p,
        pall = results\$pall,
        potentialp = results\$potentialp
      )
      write.csv(results_df, "rvgene_results.csv", row.names = FALSE)
    } else {
      warning("Not enough data to run RVgene. Check VCF samples and variants.")
    }
    
    # Save pedigree plots as PDF
    n_ped <- length(samplePedigrees)
    if (n_ped > 0) {
      cols <- min(2, n_ped)
      rows <- ceiling(n_ped / cols)
      pdf("pedigree_structures.pdf", width = 5 * cols, height = 5 * rows)
      par(mfrow = c(rows, cols))
      for (fam_name in names(samplePedigrees)) {
        plot(samplePedigrees[[fam_name]], main = fam_name)
      }
      dev.off()
    }
    
    message("Pipeline completed successfully. Outputs saved to 'rvgene_results.rds', 'rvgene_results.csv', and 'pedigree_structures.pdf'.")

    writeLines(c(
        '"BIOC_RVS_GENE_BASED_PARTIAL_SHARING":',
        paste0('    RVS: ', as.character(packageVersion('RVS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_based_partial_sharing.csv versions.yml
    """
}

workflow BIOC_RVS_GENE_BASED_PARTIAL_SHARING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ family_variants.vcf, pedigree_structures.rds ] ]

    main:
    BIOC_RVS_GENE_BASED_PARTIAL_SHARING(ch_input)

    emit:
    tables   = BIOC_RVS_GENE_BASED_PARTIAL_SHARING.out.tables
    plots    = BIOC_RVS_GENE_BASED_PARTIAL_SHARING.out.plots
    objects  = BIOC_RVS_GENE_BASED_PARTIAL_SHARING.out.objects
    versions = BIOC_RVS_GENE_BASED_PARTIAL_SHARING.out.versions
}
