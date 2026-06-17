#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PPInfer — species_specific_inference
// Infer functionally related proteins in Human or Mouse using pre-calculated STRING kernel matrices and perform functional enrichment.
// Input: K9606.rds, target_proteins.txt
// Container: quay.io/biocontainers/bioconductor-ppinfer:1.36.0--r45hdfd78af_0
// R packages: GOstats, PPInfer, org.Hs.eg.db, org.Mm.eg.db
// Bioconductor: 3.20 | R: 4.4
// Requires: GOstats, PPInfer, org.Hs.eg.db, org.Mm.eg.db
// Visualizations: bar plot, enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load kernel matrix
//  * 2. [Input & Preparation] Clean row names
//  * 3. [Input & Preparation] Infer related proteins
//  * 4. [Input & Preparation] Perform functional enrichment (GO)

nextflow.enable.dsl = 2

process BIOC_PPINFER_SPECIES_SPECIFIC_INFERENCE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("GOstats", "PPInfer", "org.Hs.eg.db", "org.Mm.eg.db")
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
    library(PPInfer)
    library(GOstats)
    
    # Check for target proteins file
    target_file <- "target_proteins.txt"
    if (!file.exists(target_file)) {
      stop("Error: 'target_proteins.txt' not found in the working directory.")
    }
    
    # Read target proteins
    target_proteins <- readLines(target_file)
    target_proteins <- target_proteins[target_proteins != ""]
    
    # Determine species based on available kernel matrix file
    if (file.exists("K9606.rds")) {
      message("Detected 'K9606.rds'. Running Human species-specific inference...")
      library(org.Hs.eg.db)
      
      # --- Load kernel matrix ---
      K.9606 <- readRDS("K9606.rds")
      
      # --- Clean row names ---
      rownames(K.9606) <- sub(".*\\\\.", "", rownames(K.9606))
      
      # --- Infer related proteins ---
      list.proteins <- target_proteins
      apoptosis.infer <- ppi.infer.human(list.proteins, K.9606, output="entrezgene", 100)
      gene.id <- apoptosis.infer\$top
      
      # Save inference results
      write.csv(as.data.frame(apoptosis.infer), "inferred_proteins_human.csv", row.names = FALSE)
      
      # --- Perform functional enrichment (GO) ---
      params <- new("GOHyperGParams", geneIds = gene.id, annotation = "org.Hs.eg.db",
                    ontology = "BP", pvalueCutoff = 0.001, conditional = FALSE,
                    testDirection = "over")
      hgOver <- hyperGTest(params)
      
      # Save enrichment results
      write.csv(summary(hgOver), "go_enrichment_human.csv", row.names = FALSE)
      
      # Plot and save barplot
      pdf("go_enrichment_barplot_human.pdf", width = 10, height = 8)
      p <- ORA.barplot(summary(hgOver), category = "Term", size = "Size",
                       count = "Count", pvalue = "Pvalue", p.adjust.methods = 'fdr')
      print(p)
      dev.off()
      
      message("Human workflow completed successfully. Outputs written to 'inferred_proteins_human.csv', 'go_enrichment_human.csv', and 'go_enrichment_barplot_human.pdf'.")
    
    } else if (file.exists("K10090.rds")) {
      message("Detected 'K10090.rds'. Running Mouse species-specific inference...")
      library(org.Mm.eg.db)
      
      # 1. Load kernel matrix
      K.10090 <- readRDS("K10090.rds")
      
      # 2. Clean row names
      rownames(K.10090) <- sub(".*\\\\.", "", rownames(K.10090))
      
      # 3. Infer related proteins
      path.05221 <- target_proteins
      path.05221.infer <- ppi.infer.mouse(path.05221, K.10090, input="entrezgene",
                                          output="entrezgene", nrow(K.10090))
      gene.id <- path.05221.infer\$top
      
      # Save inference results
      write.csv(as.data.frame(path.05221.infer), "inferred_proteins_mouse.csv", row.names = FALSE)
      
      # 4. Perform functional enrichment (GO)
      # Use top 100 inferred genes for ORA as documented in the vignette
      top_genes <- gene.id[1:min(100, length(gene.id))]
      params <- new("GOHyperGParams", geneIds = top_genes,
                    annotation = "org.Mm.eg.db",
                    ontology = "BP", pvalueCutoff = 0.001,
                    conditional = FALSE, testDirection = "over")
      hgOver <- hyperGTest(params)
      
      # Save enrichment results
      write.csv(summary(hgOver), "go_enrichment_mouse.csv", row.names = FALSE)
      
      # Plot and save barplot
      pdf("go_enrichment_barplot_mouse.pdf", width = 10, height = 8)
      p <- ORA.barplot(summary(hgOver), category = "Term", size = "Size",
                       count = "Count", pvalue = "Pvalue", p.adjust.methods = 'fdr')
      print(p)
      dev.off()
      
      message("Mouse workflow completed successfully. Outputs written to 'inferred_proteins_mouse.csv', 'go_enrichment_mouse.csv', and 'go_enrichment_barplot_mouse.pdf'.")
    
    } else {
      stop("Error: Neither 'K9606.rds' (Human) nor 'K10090.rds' (Mouse) was found in the working directory.")
    }

    writeLines(c(
        '"BIOC_PPINFER_SPECIES_SPECIFIC_INFERENCE":',
        paste0('    PPInfer: ', as.character(packageVersion('PPInfer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_species_specific_inference.csv versions.yml
    """
}

workflow BIOC_PPINFER_SPECIES_SPECIFIC_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ K9606.rds, target_proteins.txt ] ]

    main:
    BIOC_PPINFER_SPECIES_SPECIFIC_INFERENCE(ch_input)

    emit:
    tables   = BIOC_PPINFER_SPECIES_SPECIFIC_INFERENCE.out.tables
    plots    = BIOC_PPINFER_SPECIES_SPECIFIC_INFERENCE.out.plots
    objects  = BIOC_PPINFER_SPECIES_SPECIFIC_INFERENCE.out.objects
    versions = BIOC_PPINFER_SPECIES_SPECIFIC_INFERENCE.out.versions
}
