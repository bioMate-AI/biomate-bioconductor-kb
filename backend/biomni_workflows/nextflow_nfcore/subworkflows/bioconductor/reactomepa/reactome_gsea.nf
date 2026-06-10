#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ReactomePA — reactome_gsea
// Perform Reactome gene set enrichment analysis (GSEA) on a ranked list of genes.
// Input: ranked_genes.tsv
// Container: quay.io/biocontainers/bioconductor-reactomepa:1.54.0--r45hdfd78af_0
// R packages: ReactomePA, enrichplot
// Bioconductor: 3.20 | R: 4.4
// Requires: ReactomePA, enrichplot
// Visualizations: ridge plot, GSEA plot, enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read and prepare ranked gene list
//  * 2. [Core Analysis] Run GSEA using gsePathway
//  * 3. [Visualization & Output] Visualize GSEA results using gseaplot or ridgeplot

nextflow.enable.dsl = 2

process BIOC_REACTOMEPA_REACTOME_GSEA {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("ReactomePA", "enrichplot")
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
    library(ReactomePA)
    library(enrichplot)
    
    # 1. Read and prepare ranked gene list
    input_file <- "ranked_genes.tsv"
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    gene_data <- read.delim(input_file, header = TRUE, stringsAsFactors = FALSE)
    
    # Validate required columns
    if (!all(c("EntrezID", "logFC") %in% colnames(gene_data))) {
      stop("Error: Input file must contain 'EntrezID' and 'logFC' columns.")
    }
    
    # Prepare the named numeric vector sorted in decreasing order
    gene_list <- gene_data\$logFC
    names(gene_list) <- as.character(gene_data\$EntrezID)
    gene_list <- sort(gene_list, decreasing = TRUE)
    
    # Remove any NA values
    gene_list <- gene_list[!is.na(gene_list) & !is.na(names(gene_list))]
    
    # 2. Run GSEA using gsePathway
    res_gsea <- gsePathway(geneList = gene_list, organism = "human")
    
    # Save the raw GSEA result object
    saveRDS(res_gsea, file = "reactome_gsea_result.rds")
    
    # Convert results to data frame and write to CSV
    if (!is.null(res_gsea)) {
      res_df <- as.data.frame(res_gsea)
      write.csv(res_df, file = "reactome_gsea_results.csv", row.names = FALSE)
      
      # 3. Visualize GSEA results
      # Generate gseaplot for the top pathway if results exist
      if (nrow(res_df) > 0) {
        pdf("gseaplot.pdf", width = 8, height = 6)
        # Use tryCatch to handle potential plotting issues with specific datasets
        tryCatch({
          print(gseaplot(res_gsea, geneSetID = 1))
        }, error = function(e) {
          message("Could not generate gseaplot: ", e\$message)
        })
        dev.off()
        
        # Generate ridgeplot
        pdf("ridgeplot.pdf", width = 10, height = 8)
        tryCatch({
          print(ridgeplot(res_gsea))
        }, error = function(e) {
          message("Could not generate ridgeplot: ", e\$message)
        })
        dev.off()
      } else {
        message("No significantly enriched pathways found. Plots were not generated.")
      }
    } else {
      message("GSEA analysis returned NULL. No outputs generated.")
    }

    writeLines(c(
        '"BIOC_REACTOMEPA_REACTOME_GSEA":',
        paste0('    ReactomePA: ', as.character(packageVersion('ReactomePA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reactome_gsea.csv versions.yml
    """
}

workflow BIOC_REACTOMEPA_REACTOME_GSEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ranked_genes.tsv ] ]

    main:
    BIOC_REACTOMEPA_REACTOME_GSEA(ch_input)

    emit:
    tables   = BIOC_REACTOMEPA_REACTOME_GSEA.out.tables
    plots    = BIOC_REACTOMEPA_REACTOME_GSEA.out.plots
    objects  = BIOC_REACTOMEPA_REACTOME_GSEA.out.objects
    versions = BIOC_REACTOMEPA_REACTOME_GSEA.out.versions
}
