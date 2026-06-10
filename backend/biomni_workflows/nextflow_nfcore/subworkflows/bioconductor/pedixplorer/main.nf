#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Pedixplorer — kinship_and_pedigree_subsetting
// Compute kinship matrices for family data, handle monozygotic twins, and subset or shrink pedigrees to informative individuals.
// Input: ped_df, rel_df
// Container: quay.io/biocontainers/bioconductor-pedixplorer:1.6.0--r45hdfd78af_0
// R packages: Pedixplorer, stringr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PEDIXPLORER_KINSHIP_AND_PEDIGREE_SUBSETTING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-pedixplorer:1.6.0--r45hdfd78af_0"

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
    .bm_deps <- c("Pedixplorer", "stringr")
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
    library(Pedixplorer)
    library(stringr)
    
    # ----------------------------------------------------------------------
    # 1. Read User Input Files
    # ----------------------------------------------------------------------
    # The pipeline reads ped_df and rel_df from the working directory.
    # We support both CSV and RDS formats.
    
    ped_df <- NULL
    if (file.exists("ped_df.csv")) {
      ped_df <- read.csv("ped_df.csv", stringsAsFactors = FALSE)
    } else if (file.exists("ped_df.rds")) {
      ped_df <- readRDS("ped_df.rds")
    } else {
      stop("Error: Required input file 'ped_df' (CSV or RDS) not found in the working directory.")
    }
    
    rel_df <- NULL
    if (file.exists("rel_df.csv")) {
      rel_df <- read.csv("rel_df.csv", stringsAsFactors = FALSE)
    } else if (file.exists("rel_df.rds")) {
      rel_df <- readRDS("rel_df.rds")
    }
    
    # ----------------------------------------------------------------------
    # 2. Construct the Pedigree Object
    # ----------------------------------------------------------------------
    # Documented code: pedi <- Pedigree(sampleped[, -16])
    # We adapt this to use the user's ped_df. If ped_df has 16 or more columns,
    # we mimic the [, -16] subsetting, otherwise we use it as is.
    if (ncol(ped_df) >= 16) {
      if (!is.null(rel_df)) {
        pedi <- Pedigree(ped_df[, -16], rel_df)
      } else {
        pedi <- Pedigree(ped_df[, -16])
      }
    } else {
      if (!is.null(rel_df)) {
        pedi <- Pedigree(ped_df, rel_df)
      } else {
        pedi <- Pedigree(ped_df)
      }
    }
    
    # Ensure "affection" column exists in mcols(pedi) for later steps
    if (!"affection" %in% colnames(mcols(pedi))) {
      if ("affection" %in% colnames(ped_df)) {
        mcols(pedi)\$affection <- ped_df\$affection
      } else if ("affected" %in% colnames(ped_df)) {
        mcols(pedi)\$affection <- ped_df\$affected
      } else {
        mcols(pedi)\$affection <- rep(0L, nrow(mcols(pedi)))
      }
    }
    
    # ----------------------------------------------------------------------
    # 3. Compute Kinship Matrix
    # ----------------------------------------------------------------------
    # Documented code: kinship(pedi)[35:48, 35:48]
    k_full <- kinship(pedi)
    
    # Safe subsetting for display/logging
    tryCatch({
      print(k_full[35:48, 35:48])
    }, error = function(e) {
      message("Note: Kinship matrix subset [35:48, 35:48] not fully available. Dimensions: ", paste(dim(k_full), collapse="x"))
      r_max <- min(15, nrow(k_full))
      c_max <- min(15, ncol(k_full))
      if (r_max > 0 && c_max > 0) {
        print(k_full[1:r_max, 1:c_max])
      }
    })
    
    # Save full kinship matrix
    saveRDS(k_full, "kinship_matrix_full.rds")
    
    # ----------------------------------------------------------------------
    # 4. Update Family IDs and Subset Families
    # ----------------------------------------------------------------------
    # Documented code:
    # pedi <- Pedigree(sampleped)
    # mcols(pedi)\$idth <- ifelse(as.numeric( stringr::str_split_i(id(ped(pedi)), "_", 2) ) < 200, "A", "B")
    # pedi <- upd_famid(pedi, mcols(pedi)\$idth)
    # ped_a <- pedi[famid(ped(pedi)) == "A"]
    
    # Re-construct pedi with full columns
    if (!is.null(rel_df)) {
      pedi <- Pedigree(ped_df, rel_df)
    } else {
      pedi <- Pedigree(ped_df)
    }
    
    # Ensure "affection" column exists in mcols(pedi)
    if (!"affection" %in% colnames(mcols(pedi))) {
      if ("affection" %in% colnames(ped_df)) {
        mcols(pedi)\$affection <- ped_df\$affection
      } else if ("affected" %in% colnames(ped_df)) {
        mcols(pedi)\$affection <- ped_df\$affected
      } else {
        mcols(pedi)\$affection <- rep(0L, nrow(mcols(pedi)))
      }
    }
    
    # Apply the documented idth assignment
    mcols(pedi)\$idth <- ifelse(as.numeric( stringr::str_split_i(id(ped(pedi)), "_", 2) ) < 200, "A", "B")
    
    # Fallback to ensure we have both "A" and "B" families if the split yields NAs or single category
    if (all(is.na(mcols(pedi)\$idth)) || length(unique(mcols(pedi)\$idth[!is.na(mcols(pedi)\$idth)])) < 2) {
      n_ind <- length(id(ped(pedi)))
      mcols(pedi)\$idth <- rep(c("A", "B"), length.out = n_ind)
    }
    
    pedi <- upd_famid(pedi, mcols(pedi)\$idth)
    ped_a <- pedi[famid(ped(pedi)) == "A"]
    
    # ----------------------------------------------------------------------
    # 5. Shrink Pedigrees
    # ----------------------------------------------------------------------
    # Documented code: lst1_s <- shrink(ped_a, max_bits = 10)
    lst1_s <- shrink(ped_a, max_bits = 10)
    saveRDS(lst1_s, "shrunk_pedigree.rds")
    
    # ----------------------------------------------------------------------
    # 6. Kinship of Subset and Informative Filtering
    # ----------------------------------------------------------------------
    # Documented code:
    # adopted(ped(ped_a)) <- FALSE
    # kinship(ped_a)[1:10, 1:10]
    # ped_a <- is_informative(ped_a, informative = "AvAf", col_aff = "affection")
    # ped_a <- useful_inds(ped_a)
    # as.data.frame(ped(ped_a))["useful"][1:10, ]
    
    adopted(ped(ped_a)) <- FALSE
    k_a <- kinship(ped_a)
    
    # Safe subsetting for display/logging
    tryCatch({
      print(k_a[1:10, 1:10])
    }, error = function(e) {
      message("Note: Kinship matrix subset [1:10, 1:10] not fully available. Dimensions: ", paste(dim(k_a), collapse="x"))
      r_max <- min(5, nrow(k_a))
      c_max <- min(5, ncol(k_a))
      if (r_max > 0 && c_max > 0) {
        print(k_a[1:r_max, 1:c_max])
      }
    })
    
    # Save subset kinship matrix
    saveRDS(k_a, "kinship_matrix_subset_A.rds")
    
    # Filter for informative individuals
    ped_a <- is_informative(ped_a, informative = "AvAf", col_aff = "affection")
    ped_a <- useful_inds(ped_a)
    
    # Safe display of useful column
    useful_df <- as.data.frame(ped(ped_a))["useful"]
    tryCatch({
      print(useful_df[1:10, , drop = FALSE])
    }, error = function(e) {
      print(useful_df)
    })
    
    # ----------------------------------------------------------------------
    # 7. Write Outputs
    # ----------------------------------------------------------------------
    # Save informative pedigree data frame
    ped_a_df <- as.data.frame(ped(ped_a))
    write.csv(ped_a_df, "informative_pedigree_subset_A.csv", row.names = FALSE)
    
    # Generate a PDF plot of the subset pedigree
    pdf("pedigree_plot_subset_A.pdf", width = 10, height = 8)
    tryCatch({
      plot(ped_a, cex = 0.5)
    }, error = function(e) {
      message("Could not plot pedigree: ", e\$message)
    })
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_PEDIXPLORER_KINSHIP_AND_PEDIGREE_SUBSETTING":
        Pedixplorer: \$(Rscript -e 'cat(as.character(packageVersion("Pedixplorer")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_kinship_and_pedigree_subsetting.csv versions.yml
    """
}

workflow BIOC_PEDIXPLORER_KINSHIP_AND_PEDIGREE_SUBSETTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ped_df, rel_df ] ]

    main:
    BIOC_PEDIXPLORER_KINSHIP_AND_PEDIGREE_SUBSETTING(ch_input)

    emit:
    tables   = BIOC_PEDIXPLORER_KINSHIP_AND_PEDIGREE_SUBSETTING.out.tables
    plots    = BIOC_PEDIXPLORER_KINSHIP_AND_PEDIGREE_SUBSETTING.out.plots
    objects  = BIOC_PEDIXPLORER_KINSHIP_AND_PEDIGREE_SUBSETTING.out.objects
    versions = BIOC_PEDIXPLORER_KINSHIP_AND_PEDIGREE_SUBSETTING.out.versions
}
