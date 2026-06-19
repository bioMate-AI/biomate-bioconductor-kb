#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CoSIA — cross_species_diversity_and_specificity
// Calculate and visualize Shannon entropy-based diversity and specificity (DS) across tissues or genes.
// Input: gene_set, map_tissues
// Container: quay.io/biocontainers/bioconductor-cosia:1.10.1--r45hdfd78af_0
// R packages: CoSIA
// Bioconductor: 3.20 | R: 4.4
// Requires: CoSIA, htmlwidgets
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize the CoSIAn object with the gene set, species, tissues, and DS metric type
//  * 2. [Core Analysis] Convert gene identifiers using getConversion
//  * 3. [Core Analysis] Calculate DS metrics using getGExMetrics
//  * 4. [Visualization & Output] Plot DS metrics using plotDSGEx

nextflow.enable.dsl = 2

process BIOC_COSIA_CROSS_SPECIES_DIVERSITY_AND_SPECIFICITY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("CoSIA")
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
        library(CoSIA)
        
        # -----------------------------------------------------------------------------
        # 1. READ USER INPUTS
        # -----------------------------------------------------------------------------
        
        # Read gene_set from working directory (supports CSV or TXT)
        if (file.exists("gene_set.csv")) {
          gene_set_data <- read.csv("gene_set.csv", stringsAsFactors = FALSE)
          if ("Gene" %in% colnames(gene_set_data)) {
            gene_set_input <- gene_set_data\$Gene
          } else if ("Symbol" %in% colnames(gene_set_data)) {
            gene_set_input <- gene_set_data\$Symbol
          } else {
            gene_set_input <- gene_set_data[[1]]
          }
        } else if (file.exists("gene_set.txt")) {
          gene_set_input <- readLines("gene_set.txt")
        } else {
          stop("Required input file 'gene_set.csv' or 'gene_set.txt' not found in the working directory.")
        }
        
        gene_set_input <- unique(na.omit(as.character(gene_set_input)))
        
        # Read map_tissues from working directory (supports CSV or TXT)
        if (file.exists("map_tissues.csv")) {
          map_tissues_data <- read.csv("map_tissues.csv", stringsAsFactors = FALSE)
          map_tissues_input <- map_tissues_data[[1]]
        } else if (file.exists("map_tissues.txt")) {
          map_tissues_input <- readLines("map_tissues.txt")
        } else {
          stop("Required input file 'map_tissues.csv' or 'map_tissues.txt' not found in the working directory.")
        }
        
        map_tissues_input <- unique(na.omit(as.character(map_tissues_input)))
        
        # -----------------------------------------------------------------------------
        # 2. RUN WORKFLOW (EXACTLY AS DOCUMENTED)
        # -----------------------------------------------------------------------------
        
        # Initialize the CoSIAn object
        CoSIAn_Obj_DS <- CoSIA::CoSIAn(
            gene_set = gene_set_input,
            i_species = "h_sapiens",
            o_species = c("h_sapiens", "r_norvegicus"),
            input_id = "Symbol",
            output_ids = "Ensembl_id",
            map_species = c("h_sapiens", "r_norvegicus"),
            map_tissues = map_tissues_input,
            mapping_tool = "annotationDBI",
            ortholog_database = "HomoloGene",
            metric_type = "DS_Tissue"
        )
        
        # Convert gene identifiers
        CoSIAn_Obj_DS <- CoSIA::getConversion(CoSIAn_Obj_DS)
        
        # Calculate DS metrics
        CoSIAn_Obj_DS <- CoSIA::getGExMetrics(CoSIAn_Obj_DS)
        
        # Plot DS metrics
        CoSIAn_Obj_DSplot <- CoSIA::plotDSGEx(CoSIAn_Obj_DS)
        
        # -----------------------------------------------------------------------------
        # 3. WRITE OUTPUTS
        # -----------------------------------------------------------------------------
        
        # Save the complete CoSIAn object
        saveRDS(CoSIAn_Obj_DS, "CoSIAn_Obj_DS.rds")
        
        # Extract and save the calculated metrics table
        metrics_df <- CoSIA::viewCoSIAn(CoSIAn_Obj_DS, "metric")
        write.csv(metrics_df, "CoSIA_DS_metrics.csv", row.names = FALSE)
        
        # Extract and save the converted IDs mapping table
        converted_raw <- CoSIA::viewCoSIAn(CoSIAn_Obj_DS, "converted_id")
        if (is.list(converted_raw) && !is.data.frame(converted_raw)) {
          list_names <- names(converted_raw)
          if (is.null(list_names)) list_names <- seq_along(converted_raw)
          converted_df <- data.frame(
            Group = rep(list_names, lengths(converted_raw)),
            Converted_ID = unlist(converted_raw, use.names = FALSE),
            stringsAsFactors = FALSE
          )
        } else {
          converted_df <- as.data.frame(converted_raw)
        }
        write.csv(converted_df, "CoSIA_converted_ids.csv", row.names = FALSE)
        
        # Save the plot (handles both static ggplot and interactive plotly/htmlwidget)
        if (inherits(CoSIAn_Obj_DSplot, "htmlwidget")) {
          if (requireNamespace("htmlwidgets", quietly = TRUE)) {
            htmlwidgets::saveWidget(CoSIAn_Obj_DSplot, "CoSIAn_Obj_DSplot.html")
          } else {
            warning("htmlwidgets package is not installed; saving plot as RDS instead.")
            saveRDS(CoSIAn_Obj_DSplot, "CoSIAn_Obj_DSplot.rds")
          }
        } else {
          pdf("CoSIAn_Obj_DSplot.pdf", width = 8, height = 6)
          print(CoSIAn_Obj_DSplot)
          dev.off()
        }
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .obj <- tryCatch(readRDS(.rds_file), error = function(e) NULL)
      .mat <- if (is.matrix(.obj) || is.data.frame(.obj)) .obj else NULL
      if (!is.null(.mat)) {
        .vals <- suppressWarnings(as.numeric(as.matrix(.mat)))
        if (length(.vals) > 0) {
          .na_fracs <- c(.na_fracs, mean(is.na(.vals)))
          .scanned_files <- c(.scanned_files, .rds_file)
        }
      }
    }
    .na_max <- if (length(.na_fracs) > 0) round(max(.na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .na_max,
      passes = isTRUE(is.finite(.na_max) && .na_max < 0.05),
      status = if (is.finite(.na_max)) paste0("computed (scanned ", length(.scanned_files), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )
    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_COSIA_CROSS_SPECIES_DIVERSITY_AND_SPECIFICITY",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_COSIA_CROSS_SPECIES_DIVERSITY_AND_SPECIFICITY":',
        paste0('    CoSIA: ', as.character(packageVersion('CoSIA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cross_species_diversity_and_specificity.csv versions.yml
    """
}

workflow BIOC_COSIA_CROSS_SPECIES_DIVERSITY_AND_SPECIFICITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_set, map_tissues ] ]

    main:
    BIOC_COSIA_CROSS_SPECIES_DIVERSITY_AND_SPECIFICITY(ch_input)

    emit:
    tables   = BIOC_COSIA_CROSS_SPECIES_DIVERSITY_AND_SPECIFICITY.out.tables
    plots    = BIOC_COSIA_CROSS_SPECIES_DIVERSITY_AND_SPECIFICITY.out.plots
    objects  = BIOC_COSIA_CROSS_SPECIES_DIVERSITY_AND_SPECIFICITY.out.objects
    versions = BIOC_COSIA_CROSS_SPECIES_DIVERSITY_AND_SPECIFICITY.out.versions
}
