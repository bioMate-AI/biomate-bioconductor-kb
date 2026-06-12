#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sitepath — fixed_and_parallel_mutations_analysis
// Identify fixed substitutions and parallel mutations from a phylogenetic tree and multiple sequence alignment.
// Input: tree_file, alignment_file
// Container: quay.io/biocontainers/bioconductor-sitepath:1.26.0--r45ha27e39d_0
// R packages: ape, sitePath
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SITEPATH_FIXED_AND_PARALLEL_MUTATIONS_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-sitepath:1.26.0--r45ha27e39d_0"

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
    .bm_deps <- c("ape", "sitePath")
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
    library(sitePath)
    library(ape)
    
    # Define input files in the working directory as specified by the user
    tree_file <- "tree_file"
    alignment_file <- "alignment_file"
    
    # --- Import phylogenetic tree using read.tree ---
    tree <- read.tree(tree_file)
    
    # Set multiprocessing options
    options(list("cl.cores" = 1))
    
    # --- Import and align sequence data with the tree using addMSA ---
    paths <- addMSA(tree, msaPath = alignment_file, msaFormat = "fasta")
    
    # --- Pre-assess lineage thresholds using sneakPeek ---
    pdf("preassessment_plot.pdf")
    preassessment <- sneakPeek(paths, makePlot = TRUE)
    dev.off()
    
    # --- Resolve phylogenetic pathways using lineagePath ---
    paths <- lineagePath(preassessment, 18)
    saveRDS(paths, "lineage_paths.rds")
    
    pdf("lineage_paths_plot.pdf")
    plot(paths)
    dev.off()
    
    # --- Perform entropy minimization using sitesMinEntropy ---
    minEntropy <- sitesMinEntropy(paths)
    saveRDS(minEntropy, "min_entropy.rds")
    
    # --- Detect fixation sites using fixationSites ---
    fixations <- fixationSites(minEntropy)
    saveRDS(fixations, "fixation_sites.rds")
    
    allSites <- allSitesName(fixations)
    write.csv(data.frame(Fixation_Site = allSites), "fixation_sites.csv", row.names = FALSE)
    
    # --- Extract and visualize specific sites using extractSite, ---
    # Wrap site-specific extractions in tryCatch to handle cases where user data lacks these specific sites
    tryCatch({
      sp <- extractSite(fixations, 139)
      saveRDS(sp, "extracted_site_139.rds")
      
      pdf("extracted_site_139_plot.pdf")
      plot(sp)
      dev.off()
    }, error = function(e) {
      message("Skipping site 139 extraction/plot: ", e\$message)
    })
    
    tryCatch({
      tips_139 <- extractTips(fixations, 139)
      saveRDS(tips_139, "extracted_tips_139.rds")
    }, error = function(e) {
      message("Skipping site 139 tips extraction: ", e\$message)
    })
    
    tryCatch({
      pdf("fixation_site_139_single_plot.pdf")
      plotSingleSite(fixations, 139)
      dev.off()
    }, error = function(e) {
      message("Skipping site 139 single plot: ", e\$message)
    })
    
    pdf("fixation_sites_overall_plot.pdf")
    plot(fixations)
    dev.off()
    
    # --- Detect parallel mutation sites using parallelSites ---
    paraSites <- parallelSites(minEntropy, minSNP = 1, mutMode = "exact")
    saveRDS(paraSites, "parallel_sites.rds")
    
    paraSites_names <- allSitesName(paraSites)
    write.csv(data.frame(Parallel_Site = paraSites_names), "parallel_sites.csv", row.names = FALSE)
    
    tryCatch({
      pdf("parallel_site_105_plot.pdf")
      plotSingleSite(paraSites, 105)
      dev.off()
    }, error = function(e) {
      message("Skipping parallel site 105 plot: ", e\$message)
    })
    
    pdf("parallel_sites_overall_plot.pdf")
    plot(paraSites)
    dev.off()
    
    tryCatch({
      pdf("paths_site_139_plot.pdf")
      plotSingleSite(paths, 139)
      dev.off()
    }, error = function(e) {
      message("Skipping paths site 139 plot: ", e\$message)
    })
    
    tryCatch({
      pdf("paths_site_763_plot.pdf")
      plotSingleSite(paths, 763)
      dev.off()
    }, error = function(e) {
      message("Skipping paths site 763 plot: ", e\$message)
    })
    
    # Miscellaneous / SNPsites
    snps <- SNPsites(paths)
    write.csv(data.frame(SNP_Site = snps), "snp_sites.csv", row.names = FALSE)
    
    pdf("mut_sites_plot.pdf")
    plotMutSites(snps)
    dev.off()
    
    tryCatch({
      if (length(snps) >= 4) {
        pdf("paths_snp_4_plot.pdf")
        plotSingleSite(paths, snps[4])
        dev.off()
      }
    }, error = function(e) {
      message("Skipping SNP 4 plot: ", e\$message)
    })
    
    tryCatch({
      if (length(snps) >= 5) {
        pdf("paths_snp_5_plot.pdf")
        plotSingleSite(paths, snps[5])
        dev.off()
      }
    }, error = function(e) {
      message("Skipping SNP 5 plot: ", e\$message)
    })

    writeLines(c(
        '"BIOC_SITEPATH_FIXED_AND_PARALLEL_MUTATIONS_ANALYSIS":',
        paste0('        sitepath: ', as.character(packageVersion("sitepath")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fixed_and_parallel_mutations_analysis.csv versions.yml
    """
}

workflow BIOC_SITEPATH_FIXED_AND_PARALLEL_MUTATIONS_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tree_file, alignment_file ] ]

    main:
    BIOC_SITEPATH_FIXED_AND_PARALLEL_MUTATIONS_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SITEPATH_FIXED_AND_PARALLEL_MUTATIONS_ANALYSIS.out.tables
    plots    = BIOC_SITEPATH_FIXED_AND_PARALLEL_MUTATIONS_ANALYSIS.out.plots
    objects  = BIOC_SITEPATH_FIXED_AND_PARALLEL_MUTATIONS_ANALYSIS.out.objects
    versions = BIOC_SITEPATH_FIXED_AND_PARALLEL_MUTATIONS_ANALYSIS.out.versions
}
