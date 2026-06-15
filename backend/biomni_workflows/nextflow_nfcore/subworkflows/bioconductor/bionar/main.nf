#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BioNAR — ppi_network_analysis_pipeline
// Build, annotate, and analyze a protein-protein interaction (PPI) network to identify central proteins, functional communities, bridging proteins, and disease/an
// Input: PPI_Presynaptic.csv, flatfile_human_gene2HDO.csv, SCH_flatfile.csv, flatfile.go.BP.csv
// Container: quay.io/biocontainers/bioconductor-bionar:1.12.2--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BioNAR, ggplot2, igraph
// Visualizations: cluster plot, ridge plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build the network from a data frame or load a predefined graph
//  * 2. [Core Analysis] Annotate vertices with gene names, diseases, and functional annotations
//  * 3. [Core Analysis] Estimate vertex centrality measures (degree, betweenness, clustering coefficient, semilocal centrality, mean shortest path, page r
//  * 4. [Core Analysis] Fit degree distribution to power law and estimate entropy rate
//  * 5. [Core Analysis] Perform community detection (clustering) and evaluate modularity
//  * 6. [Visualization & Output] Recluster dense communities and visualize
//  * 7. [Input & Preparation] Build consensus matrix and evaluate cluster robustness
//  * 8. [Visualization & Output] Calculate and plot bridgeness
//  * 9. [Core Analysis] Analyze disease/annotation pair overlaps and calculate significance
//  * 10. [Core Analysis] Perform cluster overrepresentation analysis (ORA)

nextflow.enable.dsl = 2

process BIOC_BIONAR_PPI_NETWORK_ANALYSIS_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("BioNAR", "igraph", "ggplot2")
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
        library(BioNAR)
        library(igraph)
        library(ggplot2)
        
        # ==========================================
        # STAGE 1: Build the network
        # ==========================================
        # Read the PPI edge list from the working directory
        tbl <- read.csv("PPI_Presynaptic.csv", sep = "\t")
        gg <- buildNetwork(tbl)
        
        # ==========================================
        # STAGE 2: Annotate vertices
        # ==========================================
        # Annotate with gene names
        gg <- annotateGeneNames(gg)
        
        # Check for NA GeneNames and resolve them to prevent downstream errors
        if (any(is.na(V(gg)\$GeneName))) {
          na_idx <- which(is.na(V(gg)\$GeneName))
          V(gg)\$GeneName[na_idx] <- V(gg)\$name[na_idx]
        }
        
        # Annotate with Human Disease Ontology (HDO) terms
        dis <- read.table("flatfile_human_gene2HDO.csv", sep = "\t", skip = 1, header = FALSE, strip.white = TRUE, quote = "")
        gg <- annotateTopOntoOVG(gg, dis)
        
        # Annotate with Schizophrenia-related synaptic gene functional annotations
        shan <- read.table("SCH_flatfile.csv", sep = "\t", skip = 1, header = FALSE, strip.white = TRUE, quote = "")
        gg <- annotateSCHanno(gg, shan)
        
        # Annotate with Gene Ontology (GO) terms
        gg <- annotateGOont(gg)
        
        # Annotate with GO Biological Process (BP) terms from user input file
        goBP <- read.table("flatfile.go.BP.csv", sep = "\t", skip = 1, header = FALSE, strip.white = TRUE, quote = "")
        gg <- annotateGoBP(gg, goBP)
        
        # ==========================================
        # STAGE 3: Estimate vertex centrality measures
        # ==========================================
        gg <- calcCentrality(gg)
        mc <- getCentralityMatrix(gg)
        write.csv(mc, "centrality_matrix.csv", row.names = FALSE)
        
        # ==========================================
        # STAGE 4: Fit degree distribution and estimate entropy
        # ==========================================
        # Fit degree distribution to power law
        pdf("power_law_fit_plot.pdf")
        pFit <- fitDegree(as.vector(igraph::degree(graph = gg)), threads = 1, Nsim = 5, plot = TRUE, WIDTH = 2480, HEIGHT = 2480)
        dev.off()
        saveRDS(pFit, "power_law_fit.rds")
        
        # Estimate entropy rate
        ent <- getEntropyRate(gg)
        SRprime <- getEntropy(gg, maxSr = NULL)
        write.csv(SRprime, "entropy_results.csv", row.names = FALSE)
        
        pdf("entropy_plot.pdf")
        plotEntropy(SRprime, subTIT = "Entropy", SRo = ent\$SRo, maxSr = ent\$maxSr)
        dev.off()
        
        # ==========================================
        # STAGE 5: Modularity and Clustering
        # ==========================================
        nm <- normModularity(gg, alg = 'louvain')
        write.csv(data.frame(NormalizedModularity = nm), "normalized_modularity.csv", row.names = FALSE)
        
        alg <- "louvain"
        mem <- calcMembership(gg, alg)
        gg <- calcClustering(gg, alg)
        mem.df <- data.frame(names = V(gg)\$name, membership = factor(V(gg)\$louvain))
        write.csv(mem.df, "community_membership.csv", row.names = FALSE)
        
        # ==========================================
        # STAGE 6: Recluster and Layout
        # ==========================================
        lay <- layoutByCluster(gg, mem.df, layout = layout_nicely)
        remem <- calcReclusterMatrix(gg, mem.df, alg, 10)
        write.csv(remem, "recluster_matrix.csv", row.names = FALSE)
        
        lay <- layoutByRecluster(gg, remem, layout_nicely)
        
        pdf("recluster_layout_plot.pdf")
        plot(gg, vertex.size = 3, layout = lay, vertex.label = NA, vertex.color = as.numeric(mem.df\$membership), edge.color = 'grey95')
        dev.off()
        
        # ==========================================
        # STAGE 7: Consensus Matrix and Robustness
        # ==========================================
        conmat <- makeConsensusMatrix(gg, N = 5, alg = alg, type = 2, mask = 10, reclust = FALSE, Cnmax = 10)
        saveRDS(conmat, "consensus_matrix.rds")
        
        clrob <- getRobustness(gg, alg = alg, conmat)
        write.csv(clrob, "cluster_robustness.csv", row.names = FALSE)
        
        # ==========================================
        # STAGE 8: Bridgeness
        # ==========================================
        br <- getBridgeness(gg, alg = alg, conmat)
        write.csv(br, "bridgeness_results.csv", row.names = FALSE)
        
        gg <- calcBridgeness(gg, alg = alg, conmat)
        
        g <- plotBridgeness(gg, alg = alg, 
                            VIPs = c('8495', '22999', '8927', '8573', '26059', '8497', '27445', '8499'), 
                            Xatt = 'SL', Xlab = "Semilocal Centrality (SL)", Ylab = "Bridgeness (B)", 
                            bsize = 3, spsize = 7, MainDivSize = 0.8, xmin = 0, xmax = 1, ymin = 0, ymax = 1, 
                            baseColor = "royalblue2", SPColor = "royalblue2")
        ggsave("bridgeness_plot.pdf", plot = g, width = 8, height = 8)
        
        # ==========================================
        # STAGE 9: Disease/Annotation Pairs Overlap
        # ==========================================
        p <- calcDiseasePairs(gg, name = "TopOnto_OVG_HDO_ID", diseases = c("DOID:10652", "DOID:3312"), permute = "r")
        write.csv(p\$disease_separation, "disease_separation.csv")
        
        r <- runPermDisease(gg, name = "TopOnto_OVG_HDO_ID", diseases = c("DOID:10652", "DOID:3312"), Nperm = 100, alpha = c(0.05, 0.01, 0.001))
        write.csv(r\$Disease_overlap_sig, "disease_overlap_significance.csv", row.names = FALSE)
        
        # ==========================================
        # STAGE 10: Cluster Overrepresentation Analysis (ORA)
        # ==========================================
        ora <- clusterORA(gg, alg, name = 'TopOnto_OVG_HDO_ID', vid = "name", alpha = 0.1, col = 'COLLAPSE')
        write.csv(ora, "cluster_ora_results.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_BIONAR_PPI_NETWORK_ANALYSIS_PIPELINE":',
        paste0('    BioNAR: ', as.character(packageVersion('BioNAR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ppi_network_analysis_pipeline.csv versions.yml
    """
}

workflow BIOC_BIONAR_PPI_NETWORK_ANALYSIS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ PPI_Presynaptic.csv, flatfile_human_gene2HDO.csv, SCH_flatfile.csv, flatfile.go.BP.csv ] ]

    main:
    BIOC_BIONAR_PPI_NETWORK_ANALYSIS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_BIONAR_PPI_NETWORK_ANALYSIS_PIPELINE.out.tables
    plots    = BIOC_BIONAR_PPI_NETWORK_ANALYSIS_PIPELINE.out.plots
    objects  = BIOC_BIONAR_PPI_NETWORK_ANALYSIS_PIPELINE.out.objects
    versions = BIOC_BIONAR_PPI_NETWORK_ANALYSIS_PIPELINE.out.versions
}
