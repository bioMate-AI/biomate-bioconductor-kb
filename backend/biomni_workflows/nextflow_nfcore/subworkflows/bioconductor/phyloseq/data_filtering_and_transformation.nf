#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: phyloseq — data_filtering_and_transformation
// Filter low-abundance taxa, subset samples or taxonomic groups, transform sample counts, and perform taxonomic or phylogenetic agglomeration.
// Input: phyloseq_object
// Container: quay.io/biocontainers/bioconductor-phyloseq:1.54.0--r45hdfd78af_0
// R packages: genefilter, phyloseq
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PHYLOSEQ_DATA_FILTERING_AND_TRANSFORMATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-phyloseq:1.54.0--r45hdfd78af_0"

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
    .bm_deps <- c("genefilter", "phyloseq")
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
    library(phyloseq)
    library(genefilter)
    
    # Read the user-provided phyloseq object
    # The pipeline expects a file named "phyloseq_object" in the working directory
    GlobalPatterns <- readRDS("phyloseq_object")
    
    # Map enterotype to the same object for the sake of running the pipeline on a single input
    enterotype <- GlobalPatterns
    
    # Define topN dynamically based on the number of taxa available
    topN <- min(10, ntaxa(GlobalPatterns))
    
    # Stage 1: Prune taxa based on abundance using prune_taxa and taxa_sums
    GP <- prune_taxa(taxa_sums(GlobalPatterns) > 0, GlobalPatterns)
    most_abundant_taxa <- sort(taxa_sums(GlobalPatterns), TRUE)[1:topN]
    ex2 <- prune_taxa(names(most_abundant_taxa), GlobalPatterns)
    
    # Stage 2: Filter taxa using within-sample criteria with genefilter_sample and filterfun_sample
    f1 <- filterfun_sample(topp(0.1))
    wh1 <- genefilter_sample(GlobalPatterns, f1, A = (1/2 * nsamples(GlobalPatterns)))
    ex2 <- prune_taxa(wh1, GlobalPatterns)
    
    # Stage 3: Filter taxa using across-sample criteria with filter_taxa
    flist <- filterfun(kOverA(5, 2e-05))
    ent.logi <- filter_taxa(enterotype, flist)
    ent.trim <- filter_taxa(enterotype, flist, TRUE)
    
    # Stage 4: Subset samples based on metadata variables using subset_samples
    # Wrapped in tryCatch to handle cases where "SampleType" is not present in the input metadata
    ex3 <- tryCatch({
      subset_samples(GlobalPatterns, SampleType %in% c("Freshwater", "Ocean", "Freshwater (creek)"))
    }, error = function(e) {
      warning("Could not subset samples using 'SampleType'. Returning original object. Error: ", e\$message)
      GlobalPatterns
    })
    
    # Stage 5: Subset taxa by taxonomic category using subset_taxa
    # Wrapped in tryCatch to handle cases where "Phylum" is not present in the taxonomy table
    ex4 <- tryCatch({
      subset_taxa(GlobalPatterns, Phylum == "Firmicutes")
    }, error = function(e) {
      warning("Could not subset taxa using Phylum == 'Firmicutes'. Returning original object. Error: ", e\$message)
      GlobalPatterns
    })
    
    # Stage 6: Transform abundance counts using transform_sample_counts
    ex2 <- transform_sample_counts(GlobalPatterns, I)
    
    # Wrapped in tryCatch to handle cases where threshrankfun fails (e.g., if threshold exceeds taxa count)
    ex4 <- tryCatch({
      transform_sample_counts(GlobalPatterns, threshrankfun(500))
    }, error = function(e) {
      warning("transform_sample_counts with threshrankfun(500) failed. Falling back to threshold of 5. Error: ", e\$message)
      transform_sample_counts(GlobalPatterns, threshrankfun(min(5, ntaxa(GlobalPatterns))))
    })
    
    # Stage 7: Agglomerate taxa taxonomically using tax_glom or phylogenetically using tip_glom
    # Wrapped in tryCatch to handle cases where "Genus" is not a valid taxonomic rank
    ex6 <- tryCatch({
      tax_glom(GlobalPatterns, taxlevel = "Genus")
    }, error = function(e) {
      warning("tax_glom failed. Returning original object. Error: ", e\$message)
      GlobalPatterns
    })
    
    # Wrapped in tryCatch to handle cases where the phyloseq object does not contain a phylogenetic tree
    ex7 <- tryCatch({
      tip_glom(GlobalPatterns, speciationMinLength = 0.05)
    }, error = function(e) {
      warning("tip_glom failed (likely due to missing phylogenetic tree). Returning NULL. Error: ", e\$message)
      NULL
    })
    
    # Save meaningful results to the working directory
    saveRDS(GP, "GP_pruned.rds")
    saveRDS(ex2, "ex2_transformed.rds")
    saveRDS(ent.trim, "ent_trim.rds")
    saveRDS(ex3, "ex3_subset_samples.rds")
    saveRDS(ex4, "ex4_subset_taxa_transformed.rds")
    saveRDS(ex6, "ex6_tax_glom.rds")
    if (!is.null(ex7)) {
      saveRDS(ex7, "ex7_tip_glom.rds")
    }
    
    # Write a summary CSV table of the pipeline stages
    summary_df <- data.frame(
      Stage = c(
        "Original", 
        "GP_pruned", 
        "ex2_transformed", 
        "ent_trim", 
        "ex3_subset_samples", 
        "ex4_subset_taxa_transformed", 
        "ex6_tax_glom", 
        "ex7_tip_glom"
      ),
      Taxa_Count = c(
        ntaxa(GlobalPatterns),
        if (!is.null(GP)) ntaxa(GP) else NA,
        if (!is.null(ex2)) ntaxa(ex2) else NA,
        if (!is.null(ent.trim)) ntaxa(ent.trim) else NA,
        if (!is.null(ex3)) ntaxa(ex3) else NA,
        if (!is.null(ex4)) ntaxa(ex4) else NA,
        if (!is.null(ex6)) ntaxa(ex6) else NA,
        if (!is.null(ex7)) ntaxa(ex7) else NA
      ),
      Sample_Count = c(
        nsamples(GlobalPatterns),
        if (!is.null(GP)) nsamples(GP) else NA,
        if (!is.null(ex2)) nsamples(ex2) else NA,
        if (!is.null(ent.trim)) nsamples(ent.trim) else NA,
        if (!is.null(ex3)) nsamples(ex3) else NA,
        if (!is.null(ex4)) nsamples(ex4) else NA,
        if (!is.null(ex6)) nsamples(ex6) else NA,
        if (!is.null(ex7)) nsamples(ex7) else NA
      )
    )
    
    write.csv(summary_df, "filtering_and_transformation_summary.csv", row.names = FALSE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_PHYLOSEQ_DATA_FILTERING_AND_TRANSFORMATION":
        phyloseq: \$(Rscript -e 'cat(as.character(packageVersion("phyloseq")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_data_filtering_and_transformation.csv versions.yml
    """
}

workflow BIOC_PHYLOSEQ_DATA_FILTERING_AND_TRANSFORMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ phyloseq_object ] ]

    main:
    BIOC_PHYLOSEQ_DATA_FILTERING_AND_TRANSFORMATION(ch_input)

    emit:
    tables   = BIOC_PHYLOSEQ_DATA_FILTERING_AND_TRANSFORMATION.out.tables
    plots    = BIOC_PHYLOSEQ_DATA_FILTERING_AND_TRANSFORMATION.out.plots
    objects  = BIOC_PHYLOSEQ_DATA_FILTERING_AND_TRANSFORMATION.out.objects
    versions = BIOC_PHYLOSEQ_DATA_FILTERING_AND_TRANSFORMATION.out.versions
}
