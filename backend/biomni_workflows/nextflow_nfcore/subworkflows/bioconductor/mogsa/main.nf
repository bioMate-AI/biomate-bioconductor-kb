#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mogsa — multiple_omics_gene_set_analysis
// Integrate multiple omics datasets and project gene set annotations to calculate gene set scores (GSS), decompose scores across datasets, and identify key gene i
// Input: NCI60_4arrays.RData, NCI60_4array_supdata.RData
// Container: quay.io/biocontainers/bioconductor-mogsa:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: gplots, graphite, mogsa
// Visualizations: heatmap, bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load and verify matching dimensions and names of multi-omics data and supplementary gene set data. 2. Run MOGSA in one step using 

nextflow.enable.dsl = 2

process BIOC_MOGSA_MULTIPLE_OMICS_GENE_SET_ANALYSIS {
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
    library(mogsa)
    library(gplots)
    
    # 1. Load and verify matching dimensions and names of multi-omics data and supplementary gene set data
    # Reading user input files from the working directory
    load("NCI60_4arrays.RData")
    load("NCI60_4array_supdata.RData")
    
    # Check dimensions of expression data
    sapply(NCI60_4arrays, dim)
    # Check dimensions of supplementary data
    sapply(NCI60_4array_supdata, dim)
    
    # Check if the gene expression data and annotation data are matched in the same order
    identical(names(NCI60_4arrays), names(NCI60_4array_supdata))
    head(rownames(NCI60_4arrays\$agilent)) # the type of gene IDs
    
    dataColNames <- lapply(NCI60_4arrays, colnames)
    supColNames <- lapply(NCI60_4arrays, colnames)
    identical(dataColNames, supColNames)
    
    # Define cancer type
    cancerType <- as.factor(substr(colnames(NCI60_4arrays\$agilent), 1, 2))
    # Define color code to distinguish cancer types
    colcode <- cancerType
    levels(colcode) <- c("black", "red", "green", "blue", 
                         "cyan", "brown", "pink", "gray", "orange")
    colcode <- as.character(colcode)
    
    # 2. Run MOGSA in one step using the mogsa function
    mgsa1 <- mogsa(x = NCI60_4arrays, sup=NCI60_4array_supdata, nf=3,
                   proc.row = "center_ssq1", w.data = "inertia", statis = TRUE)
    
    # Save the primary MOGSA object
    saveRDS(mgsa1, "mgsa1.rds")
    
    # Extract and plot partial eigenvalues
    eigs <- getmgsa(mgsa1, "partial.eig")
    pdf("partial_eigenvalues.pdf")
    barplot(as.matrix(eigs), legend.text = rownames(eigs))
    dev.off()
    
    # 3. Extract and visualize the gene set score (GSS) matrix using heatmaps
    scores <- getmgsa(mgsa1, "score")
    write.csv(scores, "scores.csv")
    
    pdf("gss_heatmap.pdf", width = 10, height = 10)
    heatmap.2(scores, trace = "n", scale = "r", Colv = NULL, dendrogram = "row", 
              margins = c(6, 10), ColSideColors=colcode)
    dev.off()
    
    # 4. Identify the most significant gene sets based on p-values
    p.mat <- getmgsa(mgsa1, "p.val") # get p value matrix
    write.csv(p.mat, "p_values.csv")
    
    # Select gene sets with most significant GSS scores
    top.gs <- sort(rowSums(p.mat < 0.01), decreasing = TRUE)[1:20]
    top.gs.name <- names(top.gs)
    top.gs.name
    
    pdf("top20_gss_heatmap.pdf", width = 10, height = 10)
    heatmap.2(scores[top.gs.name, ], trace = "n", scale = "r", Colv = NULL, dendrogram = "row",
              margins = c(6, 10), ColSideColors=colcode)
    dev.off()
    
    # 5. Decompose gene set scores across datasets and identify key gene influencers
    gs1 <- top.gs.name[1] # select the most significant gene set
    gs1
    
    # Decompose the gene set score over datasets for gs1
    pdf("gs1_decomposition.pdf")
    decompose.gs.group(mgsa1, gs1, group = cancerType) 
    dev.off()
    
    # Gene influential score for gs1
    pdf("gs1_gis.pdf")
    gis1 <- GIS(mgsa1, gs1, barcol = gray.colors(4))
    dev.off()
    write.csv(gis1, "gis1.csv", row.names = FALSE)
    head(gis1) # print top 6 influencers
    
    # Decompose and analyze the second gene set
    gs2 <- "PUJANA_ATM_PCC_NETWORK"
    pdf("gs2_decomposition.pdf")
    decompose.gs.group(mgsa1, gs2, group = cancerType, x.legend = "topright")
    dev.off()
    
    pdf("gs2_gis.pdf")
    gis2 <- GIS(mgsa1, "PUJANA_ATM_PCC_NETWORK", topN = 6, barcol = gray.colors(4))
    dev.off()
    write.csv(gis2, "gis2.csv", row.names = FALSE)
    gis2
    
    # 6. Project gene sets and samples in latent space using plotGS
    fs <- getmgsa(mgsa1, "fac.scr") # extract the factor scores for cell lines (cell line space)
    pdf("factor_scores_and_plotGS.pdf", width = 12, height = 6)
    layout(matrix(1:2, 1, 2))
    plot(fs[, 1:2], pch=20, col=colcode, axes = FALSE)
    abline(v=0, h=0)
    legend("topright", col=unique(colcode), pch=20, legend=unique(cancerType), bty = "n")
    plotGS(mgsa1, label.cex = 0.8, center.only = TRUE, topN = 0, label = c(gs1, gs2))
    dev.off()
    
    # 7. Alternatively, perform the analysis in two steps by running multivariate analysis with moa first
    ana <- moa(NCI60_4arrays, proc.row = "center_ssq1", w.data = "inertia", statis = TRUE)
    saveRDS(ana, "moa_analysis.rds")
    slot(ana, "partial.eig")[, 1:6] # extract the eigenvalue
    
    # Show the eigenvalues in scree plot
    pdf("moa_scree_plots.pdf", width = 12, height = 6)
    layout(matrix(1:2, 1, 2)) 
    plot(ana, value="eig", type = 2, n=20, main="variance of PCs")
    plot(ana, value="tau", type = 2, n=20, main="Scaled variance of PCs")
    dev.off()
    
    # Run mogsa using the pre-computed moa object
    mgsa2 <- mogsa(x = ana, sup=NCI60_4array_supdata, nf=3)
    saveRDS(mgsa2, "mgsa2.rds")
    identical(mgsa1, mgsa2) # check if the two methods give the same results
    
    # 8. Prepare custom gene set data from graphite or MSigDB GMT files
    tryCatch({
      library(graphite)
      keggdb <- prepGraphite(db = pathways("hsapiens", "kegg")[1:50], id = "symbol")
      keggdb <- lapply(keggdb, function(x) sub("SYMBOL:", "", x))
      print(keggdb[1:2])
      
      # Create a dummy MSigDB GMT file to demonstrate prepMsigDB without using bundled package data
      writeLines(c(
        "SET1\thttp://example.com\tST8SIA1\tYWHAQ\tEPHA4",
        "SET2\thttp://example.com\tGTPBP5\tPVR\tATP6V1H"
      ), "dummy_msigdb.gmt")
      preGS <- prepMsigDB(file="dummy_msigdb.gmt")
      
      # Prepare supplementary data and run MOGSA
      sup_data1 <- prepSupMoa(NCI60_4arrays, geneSets=keggdb, minMatch = 1)
      mgsa3 <- mogsa(x = NCI60_4arrays, sup=sup_data1, nf=3,
                     proc.row = "center_ssq1", w.data = "inertia", statis = TRUE)
      saveRDS(mgsa3, "mgsa3.rds")
    }, error = function(e) {
      message("Optional graphite/prepMsigDB step failed or skipped: ", e\$message)
    })

    writeLines(c(
        '"BIOC_MOGSA_MULTIPLE_OMICS_GENE_SET_ANALYSIS":',
        paste0('    mogsa: ', as.character(packageVersion('mogsa')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiple_omics_gene_set_analysis.csv versions.yml
    """
}

workflow BIOC_MOGSA_MULTIPLE_OMICS_GENE_SET_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ NCI60_4arrays.RData, NCI60_4array_supdata.RData ] ]

    main:
    BIOC_MOGSA_MULTIPLE_OMICS_GENE_SET_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MOGSA_MULTIPLE_OMICS_GENE_SET_ANALYSIS.out.tables
    plots    = BIOC_MOGSA_MULTIPLE_OMICS_GENE_SET_ANALYSIS.out.plots
    objects  = BIOC_MOGSA_MULTIPLE_OMICS_GENE_SET_ANALYSIS.out.objects
    versions = BIOC_MOGSA_MULTIPLE_OMICS_GENE_SET_ANALYSIS.out.versions
}
