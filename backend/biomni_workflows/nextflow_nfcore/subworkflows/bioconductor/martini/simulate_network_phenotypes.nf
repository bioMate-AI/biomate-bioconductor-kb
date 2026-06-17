#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: martini — simulate_network_phenotypes
// Simulate quantitative or qualitative phenotypes based on causal SNPs interconnected in a network.
// Input: minigwas, minisnpMapping, minippi
// Container: quay.io/biocontainers/bioconductor-martini:1.30.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: martini, snpStats
// Visualizations: network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and construct the SNP network
//  * 2. [Core Analysis] Simulate causal SNPs within the network
//  * 3. [Core Analysis] Recreate or modify the genotype matrix if the original is too homogeneous
//  * 4. [Core Analysis] Simulate a quantitative phenotype
//  * 5. [Core Analysis] Simulate a qualitative (case-control) phenotype

nextflow.enable.dsl = 2

process BIOC_MARTINI_SIMULATE_NETWORK_PHENOTYPES {
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
    .bm_deps <- c("martini", "snpStats")
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
    library(martini)
    library(methods)
    library(snpStats)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Read minigwas (expected as an RDS file to preserve SnpMatrix structure)
    if (file.exists("minigwas.rds")) {
      minigwas <- readRDS("minigwas.rds")
    } else {
      stop("Error: 'minigwas.rds' not found in the working directory.")
    }
    
    # Read minisnpMapping (can be CSV or RDS)
    if (file.exists("minisnpMapping.csv")) {
      minisnpMapping <- read.csv("minisnpMapping.csv", stringsAsFactors = FALSE)
    } else if (file.exists("minisnpMapping.rds")) {
      minisnpMapping <- readRDS("minisnpMapping.rds")
    } else {
      stop("Error: 'minisnpMapping.csv' or 'minisnpMapping.rds' not found in the working directory.")
    }
    
    # Read minippi (can be CSV or RDS)
    if (file.exists("minippi.csv")) {
      minippi <- read.csv("minippi.csv", stringsAsFactors = FALSE)
    } else if (file.exists("minippi.rds")) {
      minippi <- readRDS("minippi.rds")
    } else {
      stop("Error: 'minippi.csv' or 'minippi.rds' not found in the working directory.")
    }
    
    # ==========================================
    # 2. Execute Documented Workflow
    # ==========================================
    
    # Construct the SNP network
    gi <- get_GI_network(minigwas, snpMapping = minisnpMapping, ppi = minippi)
    
    # Simulate causal SNPs within the network
    causal <- simulate_causal_snps(gi, ngenes = 2, pcausal = 0.3)
    
    # Recreate/modify the genotype matrix to avoid homogeneity issues
    num_samples <- nrow(minigwas\$fam)
    num_snps <- nrow(minigwas\$map)
    
    cs <- col.summary(minigwas\$genotypes)
    if (any(cs\$MAF == 0, na.rm = TRUE)) {
      X <- lapply(seq_len(num_samples), function(i) { sample(c(0,1,2), num_snps, replace = TRUE) })
      X <- do.call(rbind, X)
      colnames(X) <- minigwas\$map\$snp.name
      rownames(X) <- rownames(minigwas\$genotypes)
      if (is.null(rownames(X))) rownames(X) <- minigwas\$fam\$member
      if (is.null(rownames(X))) rownames(X) <- 1:nrow(X)
      X <- X + 1
      mode(X) <- "raw"
      minigwas\$genotypes <- new("SnpMatrix", X)
    }
    
    # Simulate quantitative phenotype
    simulated <- simulate_phenotype(minigwas, snps = causal, h2 = 0.9)
    
    # Save quantitative simulation results
    saveRDS(simulated, "simulated_quantitative.rds")
    write.csv(simulated\$fam, "simulated_quantitative_fam.csv", row.names = FALSE)
    
    # Simulate qualitative (case-control) phenotype
    # simulate_phenotype only uses original controls (affected == 1) for simulation
    num_available_controls <- sum(minigwas\$fam\$affected == 1, na.rm = TRUE)
    if (num_available_controls == 0) {
      num_available_controls <- num_samples
    }
    
    num_cases <- floor(num_available_controls * 0.2)
    num_controls <- num_available_controls - num_cases
    
    simulated <- simulate_phenotype(minigwas, snps = causal, h2 = 0.9, qualitative = TRUE,
                                    ncases = num_cases, ncontrols = num_controls, prevalence = 0.2)
    
    # Save qualitative simulation results
    saveRDS(simulated, "simulated_qualitative.rds")
    write.csv(simulated\$fam, "simulated_qualitative_fam.csv", row.names = FALSE)
    
    # ==========================================
    # 3. Save Additional Outputs
    # ==========================================
    
    # Save the network and causal SNPs list
    saveRDS(gi, "gi_network.rds")
    write.csv(data.frame(causal_snp = unlist(causal, use.names = FALSE)), "causal_snps.csv", row.names = FALSE)
    
    # Plot the network highlighting causal SNPs
    pdf("gi_network_causal_plot.pdf", width = 8, height = 8)
    par(mar = c(0, 0, 0, 0) + 0.1)
    plot(gi, mark.groups = names(causal))
    dev.off()

    writeLines(c(
        '"BIOC_MARTINI_SIMULATE_NETWORK_PHENOTYPES":',
        paste0('    martini: ', as.character(packageVersion('martini')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_simulate_network_phenotypes.csv versions.yml
    """
}

workflow BIOC_MARTINI_SIMULATE_NETWORK_PHENOTYPES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ minigwas, minisnpMapping, minippi ] ]

    main:
    BIOC_MARTINI_SIMULATE_NETWORK_PHENOTYPES(ch_input)

    emit:
    tables   = BIOC_MARTINI_SIMULATE_NETWORK_PHENOTYPES.out.tables
    plots    = BIOC_MARTINI_SIMULATE_NETWORK_PHENOTYPES.out.plots
    objects  = BIOC_MARTINI_SIMULATE_NETWORK_PHENOTYPES.out.objects
    versions = BIOC_MARTINI_SIMULATE_NETWORK_PHENOTYPES.out.versions
}
