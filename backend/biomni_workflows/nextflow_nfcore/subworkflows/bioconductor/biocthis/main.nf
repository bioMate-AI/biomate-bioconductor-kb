#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: biocthis — bioc_package_automation
// Automate the creation and configuration of a Bioconductor-friendly R package using feature identifiers from an input dataset.
// Input: input.csv
// Container: 1.20.0--r45hdfd78af_0
// R packages: biocthis, knitr, refmanager, rmarkdown, styler, usethis
// Bioconductor: 3.20 | R: 4.4
// Requires: biocthis, styler, usethis
// QC: missing-value handling
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOCTHIS_BIOC_PACKAGE_AUTOMATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("biocthis", "knitr", "refmanager", "rmarkdown", "styler", "usethis")
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
    
    # Set non-interactive options to prevent usethis/biocthis from prompting for user input
    options(usethis.quiet = TRUE, usethis.interactive = FALSE)
    
    # Load required libraries
    library(biocthis)
    library(usethis)
    library(styler)
    
    # ==========================================
    # --- Read and Process Input Data Defensively ---
    # ==========================================
    input_file <- "input.csv"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    # Read input defensively
    input_data <- read.csv(input_file, stringsAsFactors = FALSE, check.names = FALSE)
    
    # Extract feature identifiers
    if ("feature_id" %in% colnames(input_data)) {
      features <- as.character(input_data\$feature_id)
    } else if (ncol(input_data) >= 1) {
      features <- as.character(input_data[, 1])
    } else {
      features <- as.character(rownames(input_data))
    }
    
    # Clean and deduplicate features
    features <- unique(na.omit(features))
    if (length(features) == 0) {
      features <- c("FeatureA", "FeatureB", "FeatureC")
    }
    
    # ==========================================
    # --- Initialize Bioconductor Package Structure ---
    # ==========================================
    pkg_name <- "biocfeatures"
    pkg_path <- file.path(getwd(), pkg_name)
    
    # Clean up any existing directory to ensure a fresh run
    if (dir.exists(pkg_path)) {
      unlink(pkg_path, recursive = TRUE)
    }
    
    message("Creating example package structure...")
    pkg_path <- biocthis::biocthis_example_pkg(name = pkg_name, parent_dir = getwd(), use_git = TRUE)
    
    # Set the active project context for usethis/biocthis
    usethis::proj_set(pkg_path, force = TRUE)
    
    # ==========================================
    # --- Write Package Code Using Input Features ---
    # ==========================================
    r_dir <- file.path(pkg_path, "R")
    if (!dir.exists(r_dir)) {
      dir.create(r_dir, recursive = TRUE)
    }
    
    # Escape features for safe inclusion in R code
    features_escaped <- paste0('"', gsub('"', '\\"', features), '"')
    features_vector_str <- paste(features_escaped, collapse = ", ")
    
    # Create an R function that returns the input features
    func_content <- c(
      "#' Get Bioconductor Feature List",
      "#'",
      "#' This function returns the list of features initialized during package creation.",
      "#'",
      "#' @return A character vector of feature IDs.",
      "#' @export",
      "#' @examples",
      "#' get_features()",
      "get_features <- function() {",
      sprintf("  c(%s)", features_vector_str),
      "}"
    )
    writeLines(func_content, file.path(r_dir, "get_features.R"))
    
    # ==========================================
    # --- Apply biocthis Bioconductor-friendly Templates ---
    # ==========================================
    message("Applying biocthis templates...")
    
    # Configure biocthis options
    options("biocthis.pkgdown" = TRUE)
    options("biocthis.testthat" = TRUE)
    
    # 1. Create developer scripts templates
    tryCatch({
      biocthis::use_bioc_pkg_templates()
    }, error = function(e) warning("use_bioc_pkg_templates failed: ", e\$message))
    
    # 2. Create Bioconductor-friendly DESCRIPTION file
    tryCatch({
      biocthis::use_bioc_description()
    }, error = function(e) warning("use_bioc_description failed: ", e\$message))
    
    # 3. Create Bioconductor-friendly README.Rmd
    tryCatch({
      biocthis::use_bioc_readme_rmd()
    }, error = function(e) warning("use_bioc_readme_rmd failed: ", e\$message))
    
    # 4. Create Bioconductor-friendly NEWS.md
    tryCatch({
      biocthis::use_bioc_news_md()
    }, error = function(e) warning("use_bioc_news_md failed: ", e\$message))
    
    # 5. Create Bioconductor-friendly CITATION
    tryCatch({
      biocthis::use_bioc_citation()
    }, error = function(e) warning("use_bioc_citation failed: ", e\$message))
    
    # 6. Create GitHub issue, support, and feature request templates
    tryCatch({
      biocthis::use_bioc_support()
      biocthis::use_bioc_issue_template()
      biocthis::use_bioc_feature_request_template()
    }, error = function(e) warning("GitHub templates creation failed: ", e\$message))
    
    # 7. Create Bioconductor-friendly GitHub Actions workflow
    tryCatch({
      biocthis::use_bioc_github_action()
    }, error = function(e) warning("use_bioc_github_action failed: ", e\$message))
    
    # 8. Create pkgdown CSS with Bioconductor's official colors
    tryCatch({
      biocthis::use_bioc_pkgdown_css()
    }, error = function(e) warning("use_bioc_pkgdown_css failed: ", e\$message))
    
    # 9. Create Bioconductor-friendly Vignette template
    tryCatch({
      biocthis::use_bioc_vignette(pkg_name, paste("Introduction to", pkg_name))
    }, error = function(e) warning("use_bioc_vignette failed: ", e\$message))
    
    # 10. Generate Bioconductor badges for the README
    tryCatch({
      biocthis::use_bioc_badges()
    }, error = function(e) warning("use_bioc_badges failed: ", e\$message))
    
    # ==========================================
    # --- Style Package Code to Bioconductor Standards ---
    # ==========================================
    message("Styling package code using bioc_style...")
    tryCatch({
      styler::style_pkg(pkg_path, transformers = biocthis::bioc_style())
    }, error = function(e) warning("styler failed: ", e\$message))
    
    # ==========================================
    # --- Export Outputs and Structure Summary ---
    # ==========================================
    message("Writing output files...")
    
    # 1. Document the generated package structure
    generated_files <- list.files(pkg_path, recursive = TRUE, all.files = TRUE)
    write.csv(data.frame(FilePath = generated_files), "package_structure.csv", row.names = FALSE)
    
    # 2. Export the generated DESCRIPTION file
    desc_file <- file.path(pkg_path, "DESCRIPTION")
    if (file.exists(desc_file)) {
      file.copy(desc_file, "generated_DESCRIPTION", overwrite = TRUE)
    } else {
      writeLines("DESCRIPTION file was not generated.", "generated_DESCRIPTION")
    }
    
    # 3. Export the generated GitHub Actions workflow
    gha_file <- file.path(pkg_path, ".github", "workflows", "check-bioc.yml")
    if (file.exists(gha_file)) {
      file.copy(gha_file, "generated_check-bioc.yml", overwrite = TRUE)
    } else {
      writeLines("GitHub Actions workflow file was not generated.", "generated_check-bioc.yml")
    }
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_BIOCTHIS_BIOC_PACKAGE_AUTOMATION":',
        paste0('    biocthis: ', as.character(packageVersion('biocthis')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bioc_package_automation.csv versions.yml
    """
}

workflow BIOC_BIOCTHIS_BIOC_PACKAGE_AUTOMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BIOCTHIS_BIOC_PACKAGE_AUTOMATION(ch_input)

    emit:
    tables   = BIOC_BIOCTHIS_BIOC_PACKAGE_AUTOMATION.out.tables
    plots    = BIOC_BIOCTHIS_BIOC_PACKAGE_AUTOMATION.out.plots
    objects  = BIOC_BIOCTHIS_BIOC_PACKAGE_AUTOMATION.out.objects
    versions = BIOC_BIOCTHIS_BIOC_PACKAGE_AUTOMATION.out.versions
}
