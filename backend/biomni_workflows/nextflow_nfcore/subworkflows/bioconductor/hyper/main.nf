#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: hypeR — geneset_enrichment_workflow
// Perform geneset enrichment analysis (hypergeometric, kstest, or GSEA) on a gene signature against a set of genesets, followed by downstream visualization and re
// Input: signature.txt, genesets.gmt
// Container: quay.io/biocontainers/bioconductor-hyper:2.8.2--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, hypeR
// Visualizations: enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define or download genesets using msigdb_gsets()
//  * 2. [Input & Preparation] Define the gene signature (unranked, ranked, or weighted)
//  * 3. [Core Analysis] Perform enrichment analysis using hypeR()
//  * 4. [Core Analysis] Inspect the enrichment results using hyp_obj$info
//  * 5. [Visualization & Output] Visualize results using hyp_show(), hyp_dots(), hyp_emap(), hyp_hmap(), or hyp_to_graph()
//  * 6. [Visualization & Output] Export results using hyp_to_excel(), hyp_to_table(), or hyp_to_rmd()

nextflow.enable.dsl = 2

process BIOC_HYPER_GENESET_ENRICHMENT_WORKFLOW {
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
    .bm_deps <- c("hypeR")
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
    library(hypeR)
    
    # Helper function to parse GMT files into a list of gene vectors
    parse_gmt <- function(file_path) {
      if (!file.exists(file_path)) {
        stop(paste("Error: Genesets file not found at", file_path))
      }
      lines <- readLines(file_path, warn=FALSE)
      genesets <- list()
      for (line in lines) {
        if (nchar(trimws(line)) == 0) next
        parts <- strsplit(line, "\t")[[1]]
        if (length(parts) >= 3) {
          # parts[1] is geneset name, parts[2] is description, parts[3:end] are genes
          genesets[[parts[1]]] <- parts[3:length(parts)]
        } else if (length(parts) == 2) {
          genesets[[parts[1]]] <- character(0)
        }
      }
      return(genesets)
    }
    
    # Helper function to parse signature.txt (supports unranked, ranked, or weighted formats)
    parse_signature <- function(file_path) {
      if (!file.exists(file_path)) {
        stop(paste("Error: Signature file not found at", file_path))
      }
      lines <- readLines(file_path, warn=FALSE)
      lines <- trimws(lines)
      lines <- lines[lines != ""]
      
      # Determine separator
      first_line <- lines[1]
      sep <- "\t"
      if (grepl(",", first_line)) {
        sep <- ","
      } else if (grepl(" ", first_line) && !grepl("\t", first_line)) {
        sep <- " "
      }
      
      df <- read.table(text = lines, sep = sep, header = FALSE, stringsAsFactors = FALSE)
      
      if (ncol(df) >= 2) {
        val <- suppressWarnings(as.numeric(df[, 2]))
        if (!all(is.na(val))) {
          # Weighted signature (named numerical vector)
          sig <- val
          names(sig) <- as.character(df[, 1])
          sig <- sig[!is.na(sig)]
          return(sig)
        } else {
          # Ranked or unranked character vector
          return(as.character(df[, 1]))
        }
      } else {
        # Simple character vector
        return(as.character(df[, 1]))
      }
    }
    
    # ==========================================
    # STAGE 1: Define or download genesets
    # ==========================================
    # Documented API calls for downloading MSigDB genesets (commented out as we use user input):
    # BIOCARTA <- msigdb_gsets(species="Homo sapiens", collection="C2", subcollection="CP:BIOCARTA")
    # KEGG     <- msigdb_gsets(species="Homo sapiens", collection="C2", subcollection="CP:KEGG_LEGACY")
    # REACTOME <- msigdb_gsets(species="Homo sapiens", collection="C2", subcollection="CP:REACTOME")
    
    # Load custom genesets from user-provided GMT file
    genesets <- parse_gmt("genesets.gmt")
    
    # ==========================================
    # STAGE 2: Define the gene signature
    # ==========================================
    # Load signature from user-provided signature file
    signature <- parse_signature("signature.txt")
    
    # ==========================================
    # STAGE 3: Perform enrichment analysis
    # ==========================================
    hyp_obj <- hypeR(signature, genesets)
    
    # ==========================================
    # STAGE 4: Inspect the enrichment results
    # ==========================================
    print("--- Enrichment Info ---")
    print(hyp_obj\$info)
    
    # Save info to a text file
    writeLines(capture.output(print(hyp_obj\$info)), "hypeR_info.txt")
    
    # ==========================================
    # STAGE 5: Visualize results
    # ==========================================
    
    # Show interactive table (wrapped in tryCatch for non-interactive environments)
    tryCatch({
      hyp_show(hyp_obj)
    }, error = function(e) {
      message("Skipping interactive table display (hyp_show): ", e\$message)
    })
    
    # Plot dots plot
    tryCatch({
      p_dots <- hyp_dots(hyp_obj)
      if (inherits(p_dots, "ggplot")) {
        ggplot2::ggsave("hyp_dots.pdf", plot = p_dots, width = 8, height = 6)
      } else {
        pdf("hyp_dots.pdf", width = 8, height = 6)
        print(p_dots)
        dev.off()
      }
    }, error = function(e) {
      message("Could not generate dots plot (hyp_dots): ", e\$message)
    })
    
    # Plot enrichment map
    tryCatch({
      p_emap <- hyp_emap(hyp_obj)
      pdf("hyp_emap.pdf", width = 8, height = 8)
      print(p_emap)
      dev.off()
    }, error = function(e) {
      message("Could not generate enrichment map (hyp_emap): ", e\$message)
    })
    
    # Plot hierarchy map (relational genesets)
    tryCatch({
      p_hmap <- hyp_hmap(hyp_obj)
      pdf("hyp_hmap.pdf", width = 8, height = 8)
      print(p_hmap)
      dev.off()
    }, error = function(e) {
      message("Could not generate hierarchy map (hyp_hmap): ", e\$message)
    })
    
    # Map enrichment to an igraph object (relational genesets)
    tryCatch({
      g <- hyp_to_graph(hyp_obj)
      saveRDS(g, "hyp_graph.rds")
    }, error = function(e) {
      message("Could not map enrichment to igraph object (hyp_to_graph): ", e\$message)
    })
    
    # ==========================================
    # STAGE 6: Export results
    # ==========================================
    
    # Save to excel
    tryCatch({
      hyp_to_excel(hyp_obj, file_path="hypeR.xlsx")
    }, error = function(e) {
      message("Could not export to Excel (hyp_to_excel): ", e\$message)
    })
    
    # Save to table
    tryCatch({
      hyp_to_table(hyp_obj, file_path="hypeR.txt")
    }, error = function(e) {
      message("Could not export to table (hyp_to_table): ", e\$message)
    })
    
    # Generate markdown report
    tryCatch({
      hyp_to_rmd(hyp_obj,
                 file_path="hypeR.rmd",
                 title="Hyper Enrichment (hypeR)",
                 subtitle="YAP, TNF, and TAZ Knockout Experiments",
                 author="Anthony Federico, Stefano Monti")
    }, error = function(e) {
      message("Could not generate markdown report (hyp_to_rmd): ", e\$message)
    })
    
    message("Workflow complete. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_HYPER_GENESET_ENRICHMENT_WORKFLOW":',
        paste0('    hypeR: ', as.character(packageVersion('hypeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_geneset_enrichment_workflow.csv versions.yml
    """
}

workflow BIOC_HYPER_GENESET_ENRICHMENT_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ signature.txt, genesets.gmt ] ]

    main:
    BIOC_HYPER_GENESET_ENRICHMENT_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_HYPER_GENESET_ENRICHMENT_WORKFLOW.out.tables
    plots    = BIOC_HYPER_GENESET_ENRICHMENT_WORKFLOW.out.plots
    objects  = BIOC_HYPER_GENESET_ENRICHMENT_WORKFLOW.out.objects
    versions = BIOC_HYPER_GENESET_ENRICHMENT_WORKFLOW.out.versions
}
