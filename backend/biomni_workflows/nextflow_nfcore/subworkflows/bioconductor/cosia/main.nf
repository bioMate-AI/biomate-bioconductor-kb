#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CoSIA — cross_species_expression_and_variability
// Convert gene identifiers, retrieve Bgee expression data, and calculate/visualize the Coefficient of Variation (CV) across species or tissues.
// Input: gene_set, map_tissues
// Container: quay.io/biocontainers/bioconductor-cosia:1.10.1--r45hdfd78af_0
// R packages: CoSIA
// Bioconductor: 3.20 | R: 4.4
// Requires: CoSIA
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Retrieve shared tissues using getTissues
//  * 2. [Core Analysis] Initialize the CoSIAn object with the gene set, species, tissues, and CV metric type
//  * 3. [Core Analysis] Convert gene identifiers using getConversion
//  * 4. [Core Analysis] Retrieve gene expression data using getGEx
//  * 5. [Visualization & Output] Plot gene expression across species using plotSpeciesGEx
//  * 6. [Core Analysis] Calculate CV metrics using getGExMetrics
//  * 7. [Visualization & Output] Plot CV metrics using plotCVGEx

nextflow.enable.dsl = 2

process BIOC_COSIA_CROSS_SPECIES_EXPRESSION_AND_VARIABILITY {
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
    .bm_deps <- c("CoSIA")
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
    library(CoSIA)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Read gene_set (character vector of gene symbols or IDs)
    if (file.exists("gene_set.txt")) {
        gene_set <- readLines("gene_set.txt")
    } else if (file.exists("gene_set.csv")) {
        gene_set_df <- read.csv("gene_set.csv", header = FALSE, stringsAsFactors = FALSE)
        gene_set <- as.character(gene_set_df[[1]])
    } else {
        stop("Error: Required input file 'gene_set.txt' or 'gene_set.csv' not found in the working directory.")
    }
    gene_set <- unique(gene_set)
    
    # Read map_tissues (character vector of shared tissues)
    if (file.exists("map_tissues.txt")) {
        map_tissues <- readLines("map_tissues.txt")
    } else if (file.exists("map_tissues.csv")) {
        map_tissues_df <- read.csv("map_tissues.csv", header = FALSE, stringsAsFactors = FALSE)
        map_tissues <- as.character(map_tissues_df[[1]])
    } else {
        stop("Error: Required input file 'map_tissues.txt' or 'map_tissues.csv' not found in the working directory.")
    }
    map_tissues <- unique(map_tissues)
    
    # ==========================================
    # 2. Retrieve Shared Tissues (Documented Step)
    # ==========================================
    shared_tissues <- CoSIA::getTissues(c("m_musculus", "r_norvegicus"))
    write.csv(shared_tissues, "shared_tissues_reference.csv", row.names = FALSE)
    
    # ==========================================
    # 3. Initialize CoSIAn Object
    # ==========================================
    CoSIAn_Obj <- CoSIA::CoSIAn(
        gene_set = gene_set,
        i_species = "h_sapiens",
        o_species = c(
            "h_sapiens",
            "r_norvegicus"
        ),
        input_id = "Symbol",
        output_ids = "Ensembl_id",
        map_species = c(
            "h_sapiens",
            "r_norvegicus"
        ),
        map_tissues = map_tissues,
        mapping_tool = "annotationDBI",
        ortholog_database = "HomoloGene",
        metric_type = "CV_Species"
    )
    
    # Save initial object structure summary
    sink("cosian_obj_structure.txt")
    str(CoSIAn_Obj)
    sink()
    
    # ==========================================
    # 4. Convert Gene Identifiers
    # ==========================================
    CoSIAn_Obj_convert <- CoSIA::getConversion(CoSIAn_Obj)
    
    # View and save converted IDs
    converted_ids <- CoSIA::viewCoSIAn(CoSIAn_Obj_convert, "converted_id")
    if (is.data.frame(converted_ids)) {
        write.csv(converted_ids, "converted_ids.csv", row.names = FALSE)
    } else {
        # If it's a list, convert to a data frame or save as RDS
        saveRDS(converted_ids, "converted_ids.rds")
    }
    
    # ==========================================
    # 5. Retrieve Gene Expression Data
    # ==========================================
    CoSIAn_Obj_gex <- CoSIA::getGEx(CoSIAn_Obj_convert)
    
    # View and save gene expression data
    gex_data <- CoSIA::viewCoSIAn(CoSIAn_Obj_gex, "gex")
    if (is.data.frame(gex_data)) {
        write.csv(gex_data, "gex_data.csv", row.names = FALSE)
    } else {
        saveRDS(gex_data, "gex_data.rds")
    }
    
    # ==========================================
    # 6. Plot Gene Expression Across Species
    # ==========================================
    # Dynamically select a tissue and a converted Ensembl ID for plotting
    plot_tissue <- map_tissues[1]
    plot_gene <- NULL
    
    tryCatch({
        if (is.list(converted_ids)) {
            # Extract first available Ensembl ID from the list structure
            for (item in converted_ids) {
                if (is.character(item) && length(item) > 0) {
                    ensembl_ids <- item[grep("^ENSG", item)]
                    if (length(ensembl_ids) > 0) {
                        plot_gene <- ensembl_ids[1]
                        break
                    }
                }
            }
        } else if (is.data.frame(converted_ids)) {
            # Extract from data frame
            ens_cols <- grep("Ensembl", colnames(converted_ids), ignore.case = TRUE)
            if (length(ens_cols) > 0) {
                plot_gene <- as.character(converted_ids[1, ens_cols[1]])
            }
        }
    }, error = function(e) {
        message("Warning: Could not dynamically extract Ensembl ID. Using fallback.")
    })
    
    if (is.null(plot_gene) || is.na(plot_gene) || plot_gene == "") {
        plot_gene <- "ENSG00000136463" # Fallback default
    }
    
    CoSIAn_Obj_gexplot <- CoSIA::plotSpeciesGEx(CoSIAn_Obj_gex, plot_tissue, plot_gene)
    
    # Save the GEx plot
    if (!is.null(CoSIAn_Obj_gexplot)) {
        pdf("species_gex_plot.pdf", width = 8, height = 6)
        print(CoSIAn_Obj_gexplot)
        dev.off()
    }
    
    # ==========================================
    # 7. Calculate CV Metrics
    # ==========================================
    CoSIAn_Obj_CV <- CoSIA::getGExMetrics(CoSIAn_Obj_convert)
    
    # View and save CV metrics
    cv_metrics <- CoSIA::viewCoSIAn(CoSIAn_Obj_CV, "metric")
    if (is.data.frame(cv_metrics)) {
        write.csv(cv_metrics, "cv_metrics.csv", row.names = FALSE)
    } else {
        saveRDS(cv_metrics, "cv_metrics.rds")
    }
    
    # ==========================================
    # 8. Plot CV Metrics
    # ==========================================
    CoSIAn_Obj_CVplot <- CoSIA::plotCVGEx(CoSIAn_Obj_CV)
    
    # Save the CV plot
    if (!is.null(CoSIAn_Obj_CVplot)) {
        pdf("cv_gex_plot.pdf", width = 8, height = 10)
        print(CoSIAn_Obj_CVplot)
        dev.off()
    }
    
    # Save final processed CoSIAn object
    saveRDS(CoSIAn_Obj_CV, "CoSIAn_Obj_final.rds")
    
    message("Pipeline completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_COSIA_CROSS_SPECIES_EXPRESSION_AND_VARIABILITY":',
        paste0('    CoSIA: ', as.character(packageVersion('CoSIA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cross_species_expression_and_variability.csv versions.yml
    """
}

workflow BIOC_COSIA_CROSS_SPECIES_EXPRESSION_AND_VARIABILITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_set, map_tissues ] ]

    main:
    BIOC_COSIA_CROSS_SPECIES_EXPRESSION_AND_VARIABILITY(ch_input)

    emit:
    tables   = BIOC_COSIA_CROSS_SPECIES_EXPRESSION_AND_VARIABILITY.out.tables
    plots    = BIOC_COSIA_CROSS_SPECIES_EXPRESSION_AND_VARIABILITY.out.plots
    objects  = BIOC_COSIA_CROSS_SPECIES_EXPRESSION_AND_VARIABILITY.out.objects
    versions = BIOC_COSIA_CROSS_SPECIES_EXPRESSION_AND_VARIABILITY.out.versions
}
