#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cogena — drug_repositioning
// Identify candidate drugs that can reverse disease-associated gene expression changes using Connectivity Map (CMap) gene sets.
// Input: genecl_result, sampleLabel, annofile
// Container: quay.io/biocontainers/bioconductor-cogena:1.44.0--r45hdfd78af_0
// R packages: cogena
// Bioconductor: 3.20 | R: 4.4
// Requires: cogena
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run enrichment analysis for drug repositioning using clEnrich_one for a specific clustering method and cluster number
//  * 2. [Visualization & Output] Visualize drug enrichment results using heatmapPEI ordered by a specific cluster
//  * 3. [Visualization & Output] Merge multi-instance drug results and visualize using heatmapCmap

nextflow.enable.dsl = 2

process BIOC_COGENA_DRUG_REPOSITIONING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("cogena")
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
    library(cogena)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Read genecl_result (coExp clustering result object)
    genecl_result_path <- "genecl_result"
    if (!file.exists(genecl_result_path) && file.exists("genecl_result.rds")) {
      genecl_result_path <- "genecl_result.rds"
    }
    if (!file.exists(genecl_result_path)) {
      stop("Error: genecl_result file not found in the working directory.")
    }
    genecl_result <- readRDS(genecl_result_path)
    
    # Read sampleLabel (vector of sample names/labels)
    sampleLabel_path <- "sampleLabel"
    if (!file.exists(sampleLabel_path) && file.exists("sampleLabel.rds")) {
      sampleLabel_path <- "sampleLabel.rds"
    }
    if (!file.exists(sampleLabel_path)) {
      stop("Error: sampleLabel file not found in the working directory.")
    }
    
    sampleLabel <- tryCatch({
      readRDS(sampleLabel_path)
    }, error = function(e) {
      # Fallback to reading as a text file if it's not an RDS object
      labels <- readLines(sampleLabel_path)
      factor(labels)
    })
    
    # Read annofile (path to a CMap GMT gene set file)
    annofile <- "annofile"
    if (file.exists("annofile")) {
      # Check if 'annofile' is a text file containing the path, or the GMT file itself
      first_line <- readLines("annofile", n = 1)
      if (file.exists(first_line)) {
        annofile <- first_line
      }
    } else if (file.exists("CmapDn100.gmt.xz")) {
      annofile <- "CmapDn100.gmt.xz"
    } else if (file.exists("CmapUp100.gmt.xz")) {
      annofile <- "CmapUp100.gmt.xz"
    } else {
      stop("Error: annofile (CMap GMT gene set file) not found in the working directory.")
    }
    
    # ==========================================
    # 2. Run Enrichment Analysis (Drug Repositioning)
    # ==========================================
    
    cmapDn100_cogena_result <- clEnrich_one(
      genecl_result, 
      "pam", 
      "10", 
      annofile = annofile, 
      sampleLabel = sampleLabel
    )
    
    # Save the enrichment result object
    saveRDS(cmapDn100_cogena_result, file = "cmapDn100_cogena_result.rds")
    
    # Extract and save the enrichment table
    enrich_table <- enrichment(cmapDn100_cogena_result, "pam", "10")
    write.csv(enrich_table, file = "enrichment_table_drug_repositioning.csv", row.names = TRUE)
    
    # ==========================================
    # 3. Visualize Drug Enrichment Results
    # ==========================================
    
    pdf("heatmapPEI_drug_repositioning.pdf", width = 11, height = 8)
    heatmapPEI(
      cmapDn100_cogena_result, 
      "pam", 
      "10", 
      printGS = FALSE, 
      orderMethod = "7", 
      maintitle = "Drug repositioning for Psoriasis"
    )
    dev.off()
    
    # ==========================================
    # 4. Merge Multi-Instance Drug Results & Visualize
    # ==========================================
    
    pdf("heatmapCmap_drug_repositioning.pdf", width = 11, height = 8)
    heatmapCmap(
      cmapDn100_cogena_result, 
      "pam", 
      "10", 
      printGS = FALSE, 
      orderMethod = "7", 
      maintitle = "Drug repositioning for Psoriasis"
    )
    dev.off()

    writeLines(c(
        '"BIOC_COGENA_DRUG_REPOSITIONING":',
        paste0('    cogena: ', as.character(packageVersion('cogena')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_drug_repositioning.csv versions.yml
    """
}

workflow BIOC_COGENA_DRUG_REPOSITIONING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genecl_result, sampleLabel, annofile ] ]

    main:
    BIOC_COGENA_DRUG_REPOSITIONING(ch_input)

    emit:
    tables   = BIOC_COGENA_DRUG_REPOSITIONING.out.tables
    plots    = BIOC_COGENA_DRUG_REPOSITIONING.out.plots
    objects  = BIOC_COGENA_DRUG_REPOSITIONING.out.objects
    versions = BIOC_COGENA_DRUG_REPOSITIONING.out.versions
}
