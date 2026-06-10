#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iBMQ — eqtl_mapping_f2_cross
// Perform eQTL mapping, cis/trans classification, and hotspot detection for F2 crosses or populations where genotypes can be heterozygous (coded 1/2/3).
// Input: genotype.liver, phenotype.liver, map.liver, probe.liver
// Container: quay.io/biocontainers/bioconductor-ibmq:1.50.0--r45h57f0213_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, ggplot2, iBMQ
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load genotype and expression data
//  * 2. [Core Analysis] Run MCMC to calculate Posterior Probabilities of Association (PPA) with RIS=FALSE
//  * 3. [Core Analysis] Calculate FDR threshold
//  * 4. [Core Analysis] Identify significant eQTLs
//  * 5. [Input & Preparation] Load genomic positions and classify eQTLs as cis or trans
//  * 6. [Visualization & Output] Plot genome-wide eQTL distribution
//  * 7. [Core Analysis] Identify trans-eQTL hotspots

nextflow.enable.dsl = 2

process BIOC_IBMQ_EQTL_MAPPING_F2_CROSS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(iBMQ)
    library(Biobase)
    library(ggplot2)
    
    # Helper function to robustly load R objects from files (RDS or RData)
    load_object <- function(file_path) {
      if (!file.exists(file_path)) {
        stop(paste("Required input file missing:", file_path))
      }
      obj <- tryCatch({
        readRDS(file_path)
      }, error = function(e) {
        env <- new.env()
        tryCatch({
          load(file_path, envir = env)
          vars <- ls(env)
          if (length(vars) == 1) {
            env[[vars[1]]]
          } else if (length(vars) > 1) {
            base_name <- tools::file_path_sans_ext(basename(file_path))
            if (base_name %in% vars) {
              env[[base_name]]
            } else {
              env[[vars[1]]]
            }
          } else {
            stop("No objects found in the loaded file.")
          }
        }, error = function(e2) {
          stop(paste("Failed to read file", file_path, "as RDS or RData. Error:", e2\$message))
        })
      })
      return(obj)
    }
    
    # 1. Load genotype and expression data
    message("Loading input files...")
    genotype.liver  <- load_object("genotype.liver")
    phenotype.liver <- load_object("phenotype.liver")
    map.liver       <- load_object("map.liver")
    probe.liver     <- load_object("probe.liver")
    
    # Validate that the loaded objects are of correct types
    if (!inherits(genotype.liver, "SnpSet")) {
      stop("genotype.liver must be a SnpSet object.")
    }
    if (!inherits(phenotype.liver, "ExpressionSet")) {
      stop("phenotype.liver must be an ExpressionSet object.")
    }
    if (!is.data.frame(map.liver)) {
      stop("map.liver must be a data frame.")
    }
    if (!is.data.frame(probe.liver)) {
      stop("probe.liver must be a data frame.")
    }
    
    # 2. Run MCMC to calculate Posterior Probabilities of Association (PPA)
    # RIS=FALSE is used for F2 crosses (heterozygous data coded 1/2/3)
    # mc.cores is set to 1 for maximum cross-platform compatibility
    message("Running MCMC algorithm (eqtlMcmc)...")
    PPA.liver <- eqtlMcmc(
      genotype.liver, 
      phenotype.liver, 
      n.iter = 100, 
      burn.in = 100, 
      n.sweep = 20, 
      mc.cores = 1, 
      RIS = FALSE
    )
    
    # Save the raw PPA matrix
    saveRDS(PPA.liver, "PPA.liver.rds")
    message("PPA matrix saved to 'PPA.liver.rds'.")
    
    # 3. Calculate FDR threshold
    message("Calculating FDR threshold...")
    cutoff.liver <- calculateThreshold(PPA.liver, 0.2)
    message(paste("Calculated threshold cutoff:", cutoff.liver))
    
    # 4. Identify significant eQTLs
    message("Identifying significant eQTLs...")
    eqtl.liver <- eqtlFinder(PPA.liver, cutoff.liver)
    write.csv(eqtl.liver, "significant_eqtls.csv", row.names = FALSE)
    message("Significant eQTLs saved to 'significant_eqtls.csv'.")
    
    # 5. Classify eQTLs as cis or trans
    message("Classifying eQTLs as cis or trans...")
    eqtl.type.liver <- eqtlClassifier(eqtl.liver, map.liver, probe.liver, 5000000)
    write.csv(eqtl.type.liver, "classified_eqtls.csv", row.names = FALSE)
    message("Classified eQTLs saved to 'classified_eqtls.csv'.")
    
    # 6. Plot genome-wide eQTL distribution
    message("Generating genome-wide eQTL distribution plot...")
    p <- ggplot(eqtl.type.liver, aes(y = GeneStart, x = MarkerPosition)) +
      geom_point(aes(y = GeneStart, x = MarkerPosition, color = PPA), size = 1.5) +
      facet_grid(GeneChrm ~ MarkerChrm) +
      theme_bw(base_size = 12, base_family = "") +  
      theme(
        axis.ticks = element_blank(), 
        axis.text.x = element_blank(), 
        axis.text.y = element_blank()
      ) +
      scale_x_reverse()
    
    ggsave("eqtl_distribution.pdf", plot = p, width = 10, height = 8)
    message("Plot saved to 'eqtl_distribution.pdf'.")
    
    # 7. Identify trans-eQTL hotspots
    message("Identifying trans-eQTL hotspots...")
    hotspot.liver <- hotspotFinder(eqtl.type.liver, 20)
    saveRDS(hotspot.liver, "hotspots.rds")
    message("Hotspots saved to 'hotspots.rds'.")
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_IBMQ_EQTL_MAPPING_F2_CROSS":',
        paste0('    iBMQ: ', as.character(packageVersion('iBMQ')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_eqtl_mapping_f2_cross.csv versions.yml
    """
}

workflow BIOC_IBMQ_EQTL_MAPPING_F2_CROSS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genotype.liver, phenotype.liver, map.liver, probe.liver ] ]

    main:
    BIOC_IBMQ_EQTL_MAPPING_F2_CROSS(ch_input)

    emit:
    tables   = BIOC_IBMQ_EQTL_MAPPING_F2_CROSS.out.tables
    plots    = BIOC_IBMQ_EQTL_MAPPING_F2_CROSS.out.plots
    objects  = BIOC_IBMQ_EQTL_MAPPING_F2_CROSS.out.objects
    versions = BIOC_IBMQ_EQTL_MAPPING_F2_CROSS.out.versions
}
