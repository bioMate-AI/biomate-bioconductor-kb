#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mosdef — report_beautification
// Enhance Rmarkdown reports by generating interactive tables with embedded links to external databases and color-coded fold changes.
// Input: res_macrophage_IFNg_vs_naive, res_enrich_macrophage_topGO
// Container: quay.io/biocontainers/bioconductor-mosdef:1.6.0--r45hdfd78af_0
// R packages: AnnotationDbi, DESeq2, DT, htmlwidgets, mosdef, org.Hs.eg.db
// Bioconductor: 3.20 | R: 4.4
// Requires: AnnotationDbi, DESeq2, formattable, htmlwidgets, mosdef, org.Hs.eg.db
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert DESeqResults to a data frame
//  * 2. [Visualization & Output] Apply buttonifier to automatically generate database links and render an interactive DT table
//  * 3. [Core Analysis] Apply de_table_painter to color-code fold changes
//  * 4. [Input & Preparation] Manually create individual database links for genes and GO terms
//  * 5. [Visualization & Output] Generate HTML summary blocks for individual genes or GO terms

nextflow.enable.dsl = 2

process BIOC_MOSDEF_REPORT_BEAUTIFICATION {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("AnnotationDbi", "DESeq2", "DT", "htmlwidgets", "mosdef", "org.Hs.eg.db")
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
    library(mosdef)
    library(DESeq2)
    library(DT)
    library(htmlwidgets)
    library(org.Hs.eg.db)
    library(AnnotationDbi)
    
    # 1. Read User Input Files
    if (file.exists("res_macrophage_IFNg_vs_naive.rds")) {
      res_macrophage_IFNg_vs_naive <- readRDS("res_macrophage_IFNg_vs_naive.rds")
    } else {
      res_macrophage_IFNg_vs_naive <- readRDS("res_macrophage_IFNg_vs_naive")
    }
    
    if (file.exists("res_enrich_macrophage_topGO.rds")) {
      res_enrich_macrophage_topGO <- readRDS("res_enrich_macrophage_topGO.rds")
    } else {
      res_enrich_macrophage_topGO <- readRDS("res_enrich_macrophage_topGO")
    }
    
    # Ensure the symbol column exists in the DESeqResults object
    if (!"symbol" %in% colnames(res_macrophage_IFNg_vs_naive)) {
      res_macrophage_IFNg_vs_naive\$symbol <- AnnotationDbi::mapIds(
        org.Hs.eg.db,
        keys = row.names(res_macrophage_IFNg_vs_naive),
        column = "SYMBOL",
        keytype = "ENSEMBL",
        multiVals = "first"
      )
    }
    
    # 2. Convert DESeqResults to a data frame and subset
    res_subset <- head(deresult_to_df(res_macrophage_IFNg_vs_naive, FDR = 0.05), 100)
    
    # 3. Apply buttonifier to automatically generate database links
    dt_buttons_all <- buttonifier(
      df = res_subset,
      col_to_use = "symbol",
      create_buttons_to = c("GC", "NCBI", "GTEX", "UNIPROT", "dbPTM", "HPA", "PUBMED"),
      ens_col = "id",
      ens_species = "Homo_sapiens"
    )
    htmlwidgets::saveWidget(dt_buttons_all, "buttonified_table_all.html", selfcontained = TRUE)
    
    # Generate buttonified data frame with subset of databases
    res_subset <- buttonifier(res_subset,
      col_to_use = "symbol",
      create_buttons_to = c("GC", "NCBI", "HPA"),
      output_format = "DF"
    )
    
    dt_buttons_subset <- DT::datatable(res_subset,
      escape = FALSE,
      rownames = FALSE,
      options = list(
        scrollX = TRUE
      )
    )
    htmlwidgets::saveWidget(dt_buttons_subset, "buttonified_table_subset.html", selfcontained = TRUE)
    
    # 4. Apply de_table_painter to color-code fold changes
    painted_table <- de_table_painter(res_subset,
                     rounding_digits = 3,
                     signif_digits = 5)
    
    # Save the painted table
    tryCatch({
      htmlwidgets::saveWidget(formattable::as.htmlwidget(painted_table), "painted_table.html", selfcontained = TRUE)
    }, error = function(e) {
      writeLines(as.character(painted_table), "painted_table.html")
    })
    
    # 5. Manually create individual database links for genes
    res_subset\$id <- create_link_ENSEMBL(res_subset\$id, species = "Homo_sapiens")
    res_subset\$symbol_GC <-  create_link_GeneCards(res_subset\$symbol)
    res_subset\$symbol_PubMed <- create_link_PubMed(res_subset\$symbol)
    res_subset\$symbol_NCBI <- create_link_NCBI(res_subset\$symbol)
    res_subset\$symbol_dbPTM <- create_link_dbPTM(res_subset\$symbol)
    res_subset\$symbol_GTEX <- create_link_GTEX(res_subset\$symbol)
    res_subset\$symbol_UniProt <- create_link_UniProt(res_subset\$symbol)
    res_subset\$symbol_HPA <- create_link_HPA(res_subset\$symbol)
    
    dt_manual_links <- DT::datatable(res_subset, escape = FALSE,
                  options = list(
                    scrollX = TRUE
                  )
    )
    htmlwidgets::saveWidget(dt_manual_links, "manual_links_table.html", selfcontained = TRUE)
    write.csv(res_subset, "res_subset_manual_links.csv", row.names = TRUE)
    
    # 6. Generate HTML summary blocks for individual genes
    gene_html <- geneinfo_to_html("IRF1",
      res_de = res_macrophage_IFNg_vs_naive,
      col_to_use = "symbol"
    )
    writeLines(as.character(gene_html), "gene_info_IRF1.html")
    
    # 7. Manually create individual database links for GO terms
    res_enrich_macrophage_topGO\$GO.ID <- create_link_GO(res_enrich_macrophage_topGO\$GO.ID)
    
    dt_go <- DT::datatable(head(res_enrich_macrophage_topGO, 100), 
                  escape = FALSE,
                  options = list(
                    scrollX = TRUE
                  )
    )
    htmlwidgets::saveWidget(dt_go, "go_enrichment_table.html", selfcontained = TRUE)
    write.csv(res_enrich_macrophage_topGO, "res_enrich_macrophage_topGO_links.csv", row.names = FALSE)
    
    # 8. Generate HTML summary blocks for individual GO terms
    go_html <- go_to_html("GO:0001525")
    writeLines(as.character(go_html), "go_info_0001525.html")

    writeLines(c(
        '"BIOC_MOSDEF_REPORT_BEAUTIFICATION":',
        paste0('    mosdef: ', as.character(packageVersion('mosdef')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_report_beautification.csv versions.yml
    """
}

workflow BIOC_MOSDEF_REPORT_BEAUTIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ res_macrophage_IFNg_vs_naive, res_enrich_macrophage_topGO ] ]

    main:
    BIOC_MOSDEF_REPORT_BEAUTIFICATION(ch_input)

    emit:
    tables   = BIOC_MOSDEF_REPORT_BEAUTIFICATION.out.tables
    plots    = BIOC_MOSDEF_REPORT_BEAUTIFICATION.out.plots
    objects  = BIOC_MOSDEF_REPORT_BEAUTIFICATION.out.objects
    versions = BIOC_MOSDEF_REPORT_BEAUTIFICATION.out.versions
}
