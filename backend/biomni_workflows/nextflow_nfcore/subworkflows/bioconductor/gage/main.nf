#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gage — gage_pathway_analysis
// Perform a comprehensive gene set and pathway enrichment analysis on RNA-Seq count data using GAGE, identifying significant GO/KEGG pathways, extracting non-redu
// Input: counts.csv, coldata.csv
// Container: 2.60.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: gage
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GAGE_GAGE_PATHWAY_ANALYSIS {
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
    .bm_deps <- c("gage")
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
    
    # --- Load required libraries ---
    library(gage)
    
    # Define parameters
    species <- "human"
    kegg_code <- "hsa"
    q_cutoff <- 0.1
    
    # --- Load and preprocess user input data ---
    message("Loading input data...")
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Ensure counts is a matrix
    cnts <- as.matrix(counts)
    
    # Filter out genes with zero counts across all samples
    sel.rn <- rowSums(cnts) != 0
    cnts <- cnts[sel.rn, ]
    
    # Normalize counts using the size factor method documented in the GAGE RNA-Seq workflow
    libsizes <- colSums(cnts)
    size.factor <- libsizes / exp(mean(log(libsizes)))
    cnts.norm <- t(t(cnts) / size.factor)
    cnts.norm <- log2(cnts.norm + 8)
    
    # Align coldata with count matrix columns
    sample_order <- match(coldata\$sample, colnames(cnts.norm))
    if (any(is.na(sample_order))) {
        stop("Sample names in coldata.csv do not match column names in counts.csv")
    }
    cnts.norm <- cnts.norm[, sample_order, drop = FALSE]
    
    # Identify reference (control) and sample (treatment) indices
    conditions <- unique(coldata\$condition)
    if (length(conditions) < 2) {
        stop("At least two distinct conditions are required in coldata.csv for comparison")
    }
    ref_cond <- conditions[1]
    samp_cond <- conditions[2]
    
    ref.idx <- which(coldata\$condition == ref_cond)
    samp.idx <- which(coldata\$condition == samp_cond)
    
    message(paste("Reference condition:", ref_cond, "(Samples:", paste(ref.idx, collapse=","), ")"))
    message(paste("Comparison condition:", samp_cond, "(Samples:", paste(samp.idx, collapse=","), ")"))
    
    # --- Fetch Gene Sets (GO and KEGG) ---
    message("Fetching gene sets...")
    # Fetch GO Molecular Function gene sets (offline-capable via annotation packages)
    go.hs <- go.gsets(species = species)
    go.gs <- go.hs\$go.sets[go.hs\$go.subs\$MF]
    
    # Fetch KEGG gene sets (wrapped in tryCatch to handle potential network/API limits gracefully)
    kegg.gs <- NULL
    tryCatch({
        kg.hsa <- kegg.gsets(kegg_code)
        kegg.gs <- kg.hsa\$kg.sets[kg.hsa\$sigmet.idx]
    }, error = function(e) {
        warning("Failed to fetch KEGG gene sets online: ", e\$message, ". Proceeding with GO analysis only.")
    })
    
    # --- Run GAGE Pathway Enrichment Analysis ---
    message("Running GAGE analysis...")
    # Run GAGE on GO Molecular Function
    go.p <- gage(cnts.norm, gsets = go.gs, ref = ref.idx, samp = samp.idx, compare = "unpaired")
    
    # Run GAGE on KEGG if available
    kegg.p <- NULL
    if (!is.null(kegg.gs)) {
        kegg.p <- gage(cnts.norm, gsets = kegg.gs, ref = ref.idx, samp = samp.idx, compare = "unpaired")
    }
    
    # --- Identify and Output Significant Gene Sets ---
    message("Filtering significant gene sets...")
    go.sig <- sigGeneSet(go.p, outname = "go_gage", cutoff = q_cutoff)
    write.table(rbind(go.p\$greater, go.p\$less), file = "go_gage_results.txt", sep = "\t", col.names = NA)
    write.table(rbind(go.sig\$greater, go.sig\$less), file = "significant_go_pathways.txt", sep = "\t", col.names = NA)
    
    if (!is.null(kegg.p)) {
        kegg.sig <- sigGeneSet(kegg.p, outname = "kegg_gage", cutoff = q_cutoff)
        write.table(rbind(kegg.p\$greater, kegg.p\$less), file = "kegg_gage_results.txt", sep = "\t", col.names = NA)
    } else {
        writeLines("KEGG analysis was bypassed due to API unavailability.", "kegg_gage_results.txt")
    }
    
    # --- Extract Non-Redundant Essential Gene Sets ---
    message("Extracting non-redundant essential gene sets...")
    # For GO Up-regulated
    go_up_sig <- go.p\$greater[!is.na(go.p\$greater[, "q.val"]) & go.p\$greater[, "q.val"] < q_cutoff, , drop = FALSE]
    if (nrow(go_up_sig) > 0) {
        esset.grp(go.p\$greater, cnts.norm, gsets = go.gs, ref = ref.idx, samp = samp.idx,
                  test4up = TRUE, output = TRUE, outname = "essential_go_sets_up", make.plot = FALSE)
    } else {
        writeLines("No significantly up-regulated GO terms found.", "essential_go_sets_up.txt")
    }
    
    # For GO Down-regulated
    go_dn_sig <- go.p\$less[!is.na(go.p\$less[, "q.val"]) & go.p\$less[, "q.val"] < q_cutoff, , drop = FALSE]
    if (nrow(go_dn_sig) > 0) {
        esset.grp(go.p\$less, cnts.norm, gsets = go.gs, ref = ref.idx, samp = samp.idx,
                  test4up = FALSE, output = TRUE, outname = "essential_go_sets_down", make.plot = FALSE)
    } else {
        writeLines("No significantly down-regulated GO terms found.", "essential_go_sets_down.txt")
    }
    
    # --- Visualization of Top Enriched Pathways ---
    message("Generating visualizations...")
    pdf("top_pathway_expression.pdf", width = 10, height = 8)
    
    # Identify top 3 enriched GO terms (either up or down)
    top_go_terms <- c(rownames(go.p\$greater)[1:min(3, nrow(go.p\$greater))],
                      rownames(go.p\$less)[1:min(3, nrow(go.p\$less))])
    top_go_terms <- unique(top_go_terms[!is.na(top_go_terms)])
    
    if (length(top_go_terms) > 0) {
        # Extract unique genes belonging to these top pathways
        top_genes <- unique(unlist(go.gs[top_go_terms]))
        top_genes <- intersect(top_genes, rownames(cnts.norm))
        
        if (length(top_genes) > 1) {
            # Extract essential gene expression data
            essData <- essGene(top_genes, cnts.norm, ref = ref.idx, samp = samp.idx)
            
            # Plot a global heatmap of essential genes across top pathways
            heatmap(essData, 
                    Colv = NA, 
                    col = colorRampPalette(c("blue", "white", "red"))(50),
                    main = "Essential Genes in Top Enriched GO Terms",
                    xlab = "Samples", 
                    ylab = "Genes",
                    margins = c(8, 8))
            
            # Generate individual geneData plots for the top pathways
            for (gs in top_go_terms[1:min(3, length(top_go_terms))]) {
                clean_name <- gsub(" |:|/", "_", substr(gs, 1, 40))
                tryCatch({
                    geneData(genes = go.gs[[gs]], exprs = essData, 
                             ref = seq_along(ref.idx), 
                             samp = (length(ref.idx) + 1):(length(ref.idx) + length(samp.idx)),
                             outname = paste0("geneData_", clean_name), txt = TRUE, heatmap = TRUE,
                             Colv = FALSE, Rowv = FALSE, dendrogram = "none", limit = 3, scatterplot = TRUE)
                }, error = function(e) {
                    warning("Could not run geneData for: ", gs, " - ", e\$message)
                })
            }
        } else {
            plot.new()
            text(0.5, 0.5, "Insufficient overlapping genes for heatmap visualization")
        }
    } else {
        plot.new()
        text(0.5, 0.5, "No enriched pathways found to visualize")
    }
    
    dev.off()
    message("GAGE analysis pipeline completed successfully.")

    writeLines(c(
        '"BIOC_GAGE_GAGE_PATHWAY_ANALYSIS":',
        paste0('    gage: ', as.character(packageVersion('gage')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gage_pathway_analysis.csv versions.yml
    """
}

workflow BIOC_GAGE_GAGE_PATHWAY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_GAGE_GAGE_PATHWAY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GAGE_GAGE_PATHWAY_ANALYSIS.out.tables
    plots    = BIOC_GAGE_GAGE_PATHWAY_ANALYSIS.out.plots
    objects  = BIOC_GAGE_GAGE_PATHWAY_ANALYSIS.out.objects
    versions = BIOC_GAGE_GAGE_PATHWAY_ANALYSIS.out.versions
}
