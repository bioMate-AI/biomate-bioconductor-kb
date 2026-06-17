#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mastR — multi_dataset_signature_aggregation
// Identify and aggregate robust gene signatures across multiple independent transcriptomics datasets using union, intersection, or Robust Rank Aggregation (RRA).
// Input: user_dataset_list.RData, user_markers_pool.RData
// Container: quay.io/biocontainers/bioconductor-mastr:1.10.2--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GSEABase, edgeR, mastR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load User Inputs
//  * 2. [Input & Preparation] Dynamically Determine Parameters from the First Dataset
//  * 3. [Input & Preparation] Run the Documented Workflow Call
//  * 4. [Input & Preparation] Save Outputs

nextflow.enable.dsl = 2

process BIOC_MASTR_MULTI_DATASET_SIGNATURE_AGGREGATION {
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
    .bm_deps <- c("mastR", "edgeR", "GSEABase", "Biobase")
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
    library(mastR)
    library(edgeR)
    library(GSEABase)
    library(Biobase)
    
    # --- Load User Inputs ---
    # Load the dataset list
    env_datasets <- new.env()
    load("user_dataset_list.RData", envir = env_datasets)
    dataset_list <- as.list(env_datasets)[[1]]
    
    # Load the markers pool
    env_markers <- new.env()
    load("user_markers_pool.RData", envir = env_markers)
    markers_obj <- as.list(env_markers)[[1]]
    
    # Extract gene IDs from the markers pool object
    if (inherits(markers_obj, "GeneSet")) {
      markers_vec <- GSEABase::geneIds(markers_obj)
    } else if (inherits(markers_obj, "GeneSetCollection")) {
      markers_vec <- unique(unlist(GSEABase::geneIds(markers_obj)))
    } else {
      markers_vec <- as.character(markers_obj)
    }
    
    # --- Dynamically Determine Parameters from the First Dataset ---
    obj1 <- dataset_list[[1]]
    if (inherits(obj1, "ExpressionSet")) {
      pdata <- Biobase::pData(obj1)
      feature_names <- rownames(obj1)
    } else if (inherits(obj1, "DGEList")) {
      pdata <- obj1\$samples
      feature_names <- rownames(obj1\$counts)
    }
    
    # Determine the appropriate group column
    cols <- colnames(pdata)
    candidate <- grep("celltype|group|class", cols, ignore.case = TRUE, value = TRUE)
    if (length(candidate) > 0) {
      group_col <- candidate[1]
    } else {
      group_col <- cols[1]
    }
    
    # Determine the target group dynamically
    target_group <- as.character(unique(pdata[[group_col]])[1])
    
    # Determine the gene ID type dynamically
    if (any(grepl("^ENSG", head(feature_names)))) {
      gene_id_type <- "ENSEMBL"
    } else {
      gene_id_type <- "SYMBOL"
    }
    
    # --- Run the Documented Workflow Call ---
    set.seed(123)
    m_ct_m <- filter_subset_sig(
      data = dataset_list,
      markers = markers_vec,
      group_col = group_col,
      target_group = target_group,
      feature_selection = "auto",
      dir = "UP",
      gene_id = gene_id_type,
      comb = "RRA",
      s_thres = 0.5,
      summary = FALSE
    )
    
    # --- Save Outputs ---
    # Save the aggregated signature as an RDS object
    saveRDS(m_ct_m, file = "aggregated_signature.rds")
    
    # Save the aggregated signature as a CSV table
    write.csv(
      data.frame(Signature_Gene = m_ct_m, stringsAsFactors = FALSE),
      file = "aggregated_signature.csv",
      row.names = FALSE
    )
    
    cat("Workflow completed successfully. Outputs saved to 'aggregated_signature.rds' and 'aggregated_signature.csv'.\n")

    writeLines(c(
        '"BIOC_MASTR_MULTI_DATASET_SIGNATURE_AGGREGATION":',
        paste0('    mastR: ', as.character(packageVersion('mastR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_dataset_signature_aggregation.csv versions.yml
    """
}

workflow BIOC_MASTR_MULTI_DATASET_SIGNATURE_AGGREGATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_dataset_list.RData, user_markers_pool.RData ] ]

    main:
    BIOC_MASTR_MULTI_DATASET_SIGNATURE_AGGREGATION(ch_input)

    emit:
    tables   = BIOC_MASTR_MULTI_DATASET_SIGNATURE_AGGREGATION.out.tables
    plots    = BIOC_MASTR_MULTI_DATASET_SIGNATURE_AGGREGATION.out.plots
    objects  = BIOC_MASTR_MULTI_DATASET_SIGNATURE_AGGREGATION.out.objects
    versions = BIOC_MASTR_MULTI_DATASET_SIGNATURE_AGGREGATION.out.versions
}
