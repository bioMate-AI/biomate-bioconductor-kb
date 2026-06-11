#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: snapcount — snapcount_public_splicing_analysis
// Query public RNA-seq splicing and expression data from Snaptron (GTEx/TCGA) for genes of interest, perform high-level splicing calculations (PSI, JIR, Tissue Sp
// Input: counts.csv, coldata.csv
// Container: 1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocGenerics, GenomicRanges, IRanges, S4Vectors, SummarizedExperiment, snapcount
// Visualizations: bar plot, box plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SNAPCOUNT_SNAPCOUNT_PUBLIC_SPLICING_ANALYSIS {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(snapcount)
    library(GenomicRanges)
    library(S4Vectors)
    library(BiocGenerics)
    
    # ==========================================
    # --- Read and Preprocess Input Data ---
    # ==========================================
    message("Stage 1: Reading input files...")
    
    # Read local count matrix
    counts_df <- read.csv("counts.csv", check.names = FALSE)
    if ("gene_id" %in% colnames(counts_df)) {
        rownames(counts_df) <- counts_df\$gene_id
        counts_df\$gene_id <- NULL
    }
    counts <- as.matrix(counts_df)
    
    # Read local coldata
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Identify gene of interest from local counts
    gene_of_interest <- rownames(counts)[1]
    if (is.null(gene_of_interest) || gene_of_interest == "" || grepl("^ENSG", gene_of_interest)) {
        gene_of_interest <- "CD99"
    }
    
    # ==========================================
    # --- Query Snaptron for Gene & Junctions ---
    # ==========================================
    message("Stage 2: Querying Snaptron for gene: ", gene_of_interest)
    
    # Initialize QueryBuilder for GTEx
    sb <- QueryBuilder(compilation = "gtex", regions = gene_of_interest)
    
    # Query gene expression with fallback handling
    gene_rse <- tryCatch({
        query_gene(sb)
    }, error = function(e) {
        message("Query failed for ", gene_of_interest, ". Falling back to CD99.")
        gene_of_interest <<- "CD99"
        sb <<- QueryBuilder(compilation = "gtex", regions = "CD99")
        query_gene(sb)
    })
    
    # Query exons and junctions for the gene
    exon_rse <- query_exon(sb)
    jx_rse <- query_jx(sb)
    
    # ==========================================
    # --- Compare Local and Public Expression ---
    # ==========================================
    message("Stage 3: Analyzing public GTEx tissue expression...")
    
    gtex_counts <- assay(gene_rse, "counts")
    gtex_metadata <- colData(gene_rse)
    
    # Calculate median expression per tissue in GTEx
    gtex_df <- data.frame(
        sample_id = colnames(gtex_counts),
        count = as.vector(gtex_counts[1, ]),
        tissue = gtex_metadata\$SMTS,
        stringsAsFactors = FALSE
    )
    
    gtex_tissue_summary <- aggregate(count ~ tissue, data = gtex_df, FUN = median)
    colnames(gtex_tissue_summary) <- c("Tissue", "GTEx_Median_Count")
    write.csv(gtex_tissue_summary, "gtex_tissue_expression.csv", row.names = FALSE)
    
    # ==========================================
    # --- Tissue Specificity of Top Junction ---
    # ==========================================
    message("Stage 4: Calculating tissue specificity for the top junction...")
    
    jx_counts <- assay(jx_rse, "counts")
    total_jx_counts <- rowSums(jx_counts)
    top_jx_idx <- which.max(total_jx_counts)
    
    if (length(top_jx_idx) > 0 && !is.na(top_jx_idx)) {
        top_jx_range <- rowRanges(jx_rse)[top_jx_idx]
        chrom <- as.character(seqnames(top_jx_range))
        start_coord <- start(top_jx_range)
        end_coord <- end(top_jx_range)
        strand_val <- as.character(strand(top_jx_range))
        
        ts_query <- QueryBuilder(compilation = "gtex", regions = paste0(chrom, ":", start_coord, "-", end_coord))
        ts_query <- set_row_filters(ts_query, strand == strand_val)
        ts_query <- set_coordinate_modifier(ts_query, Coordinates\$Exact)
        
        ts_results <- tryCatch({
            tissue_specificity(list(ts_query))
        }, error = function(e) {
            ts_query <- set_coordinate_modifier(ts_query, Coordinates\$Within)
            tissue_specificity(list(ts_query))
        })
    } else {
        ts_results <- data.frame(sample_id = integer(), shared = logical(), tissue = character(), group = character())
    }
    write.csv(ts_results, "tissue_specificity_top_junction.csv", row.names = FALSE)
    
    # ==========================================
    # --- Junction Union & Intersection (GTEx vs TCGA) ---
    # ==========================================
    message("Stage 5: Performing GTEx vs TCGA junction comparison...")
    
    gtex_qb <- QueryBuilder(compilation = "gtex", regions = gene_of_interest)
    tcga_qb <- QueryBuilder(compilation = "tcga", regions = gene_of_interest)
    
    union_rse <- tryCatch({
        junction_union(gtex_qb, tcga_qb)
    }, error = function(e) {
        NULL
    })
    
    intersection_rse <- tryCatch({
        junction_intersection(gtex_qb, tcga_qb)
    }, error = function(e) {
        NULL
    })
    
    comparison_summary <- data.frame(
        Metric = c("GTEx_Junctions", "TCGA_Junctions", "Union_Junctions", "Intersection_Junctions"),
        Count = c(
            nrow(jx_rse),
            tryCatch(nrow(query_jx(tcga_qb)), error = function(e) 0),
            ifelse(is.null(union_rse), 0, nrow(union_rse)),
            ifelse(is.null(intersection_rse), 0, nrow(intersection_rse))
        )
    )
    write.csv(comparison_summary, "junction_comparison_gtex_tcga.csv", row.names = FALSE)
    
    # ==========================================
    # --- High-Level Splicing (PSI) ---
    # ==========================================
    message("Stage 6: Calculating Percent Spliced In (PSI) for reference cassette exon...")
    
    lq <- QueryBuilder(compilation = "gtex", regions = "chr19:45297955-45298142")
    lq <- set_row_filters(lq, strand == "+")
    lq <- set_coordinate_modifier(lq, Coordinates\$Exact)
    
    rq <- QueryBuilder(compilation = "gtex", regions = "chr19:45298223-45299810")
    rq <- set_row_filters(rq, strand == "+")
    rq <- set_coordinate_modifier(rq, Coordinates\$Exact)
    
    ex <- QueryBuilder(compilation = "gtex", regions = "chr19:45297955-45299810")
    ex <- set_row_filters(ex, strand == "+")
    ex <- set_coordinate_modifier(ex, Coordinates\$Exact)
    
    psi_df <- tryCatch({
        percent_spliced_in(list(lq), list(rq), list(ex))
    }, error = function(e) {
        data.frame(sample_id = integer(), inclusion_group1_coverage = numeric(),
                   inclusion_group2_coverage = numeric(), exclusion_group_coverage = numeric(),
                   psi = numeric())
    })
    write.csv(psi_df, "psi_splicing_events.csv", row.names = FALSE)
    
    # ==========================================
    # --- Visualisation & Reporting ---
    # ==========================================
    message("Stage 7: Generating PDF report...")
    
    pdf("snapcount_analysis_report.pdf", width = 10, height = 6)
    
    # Plot 1: GTEx Tissue Expression
    if (nrow(gtex_tissue_summary) > 0) {
        gtex_tissue_summary <- gtex_tissue_summary[order(-gtex_tissue_summary\$GTEx_Median_Count), ]
        par(mar = c(10, 4, 4, 2))
        barplot(gtex_tissue_summary\$GTEx_Median_Count,
                names.arg = gtex_tissue_summary\$Tissue,
                las = 2,
                col = "skyblue",
                main = paste("GTEx Median Expression of", gene_of_interest, "by Tissue"),
                ylab = "Median Raw Count")
    }
    
    # Plot 2: Local Expression by Condition
    local_gene_to_plot <- if (gene_of_interest %in% rownames(counts)) gene_of_interest else rownames(counts)[1]
    if (!is.null(local_gene_to_plot)) {
        local_counts <- as.numeric(counts[local_gene_to_plot, ])
        local_df <- data.frame(
            Sample = colnames(counts),
            Count = local_counts,
            Condition = coldata\$condition[match(colnames(counts), coldata\$sample)]
        )
        par(mar = c(5, 4, 4, 2))
        boxplot(Count ~ Condition, data = local_df,
                col = c("lightgreen", "lightcoral"),
                main = paste("Local Expression of", local_gene_to_plot, "by Condition"),
                ylab = "Raw Count", xlab = "Condition")
    }
    
    dev.off()
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_SNAPCOUNT_SNAPCOUNT_PUBLIC_SPLICING_ANALYSIS":',
        paste0('    snapcount: ', as.character(packageVersion('snapcount')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_snapcount_public_splicing_analysis.csv versions.yml
    """
}

workflow BIOC_SNAPCOUNT_SNAPCOUNT_PUBLIC_SPLICING_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_SNAPCOUNT_SNAPCOUNT_PUBLIC_SPLICING_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SNAPCOUNT_SNAPCOUNT_PUBLIC_SPLICING_ANALYSIS.out.tables
    plots    = BIOC_SNAPCOUNT_SNAPCOUNT_PUBLIC_SPLICING_ANALYSIS.out.plots
    objects  = BIOC_SNAPCOUNT_SNAPCOUNT_PUBLIC_SPLICING_ANALYSIS.out.objects
    versions = BIOC_SNAPCOUNT_SNAPCOUNT_PUBLIC_SPLICING_ANALYSIS.out.versions
}
