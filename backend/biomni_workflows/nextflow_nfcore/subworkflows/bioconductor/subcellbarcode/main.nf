#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SubCellBarCode — gene_centric_classification
// Classify protein subcellular localization at compartment and neighborhood levels using a gene-centric approach.
// Input: protein_abundance.tsv, marker_proteins.tsv, psm_counts.tsv
// Container: quay.io/biocontainers/bioconductor-subcellbarcode:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SubCellBarCode
// Visualizations: t-SNE plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and log2-transform protein data
//  * 2. [Core Analysis] Convert identifiers to gene symbols if necessary
//  * 3. [Core Analysis] Calculate covered marker proteins
//  * 4. [Core Analysis] Perform quality control on marker proteins
//  * 5. [Visualization & Output] Optimize and visualize marker proteins in t-SNE space
//  * 6. [Core Analysis] Train SVM classifier and predict probabilities
//  * 7. [Core Analysis] Estimate and apply compartment-level thresholds
//  * 8. [Core Analysis] Estimate and apply neighborhood-level thresholds
//  * 9. [Core Analysis] Merge compartment and neighborhood classifications
//  * 10. [Visualization & Output] Plot single protein barcode or multiple proteins

nextflow.enable.dsl = 2

process BIOC_SUBCELLBARCODE_GENE_CENTRIC_CLASSIFICATION {
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
    .bm_deps <- c("SubCellBarCode")
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
        
        # Load required library
        library(SubCellBarCode)
        
        # 1. Load and log2-transform protein data
        # Read the user input files from the working directory
        hcc827Ctrl <- read.delim("protein_abundance.tsv", sep = "\t", header = TRUE, row.names = 1, check.names = FALSE)
        markerProteins <- read.delim("marker_proteins.tsv", sep = "\t", header = TRUE, check.names = FALSE, stringsAsFactors = FALSE)
        hcc827CtrlPSMCount <- read.delim("psm_counts.tsv", sep = "\t", header = TRUE, check.names = FALSE)
        
        # Load and normalize data
        df <- loadData(protein.data = hcc827Ctrl)
        
        # 2. Convert identifiers to gene symbols if necessary
        # (Assuming input is already gene symbols as per workflow requirements, 
        # but keeping the documented structure available)
        # df <- convert2symbol(df = df, id = "UNIPROT")
        
        # Subset data safely (handling cases where input might have fewer than 6000 rows)
        set.seed(2)
        sample_size <- min(nrow(df), 6000)
        df <- df[sample(nrow(df), sample_size), ]
        
        # 3. Calculate covered marker proteins
        c.prots <- calculateCoveredProtein(proteinIDs = rownames(df), 
                                markerproteins = markerProteins[,1]) 
        
        # 4. Perform quality control on marker proteins
        r.markers <- markerQualityControl(coveredProteins = c.prots, protein.data = df)
        
        # 5. Optimize and visualize marker proteins in t-SNE space
        # Save t-SNE visualizations to a PDF file
        pdf("tsne_visualization.pdf", width = 8, height = 8)
        
        set.seed(6)
        tsne.map <- tsneVisualization(protein.data = df, 
                            markerProteins = r.markers, 
                            dims = 3, 
                            theta = c(0.1), 
                            perplexity = c(60)) 
        print(tsne.map)
        
        set.seed(9)
        tsne.map2 <- tsneVisualization(protein.data = df, 
                            markerProteins = r.markers, 
                            dims = 2, 
                            theta = c(0.5), 
                            perplexity = c(60))
        print(tsne.map2)
        
        dev.off()
        
        # 6. Train SVM classifier and predict probabilities
        set.seed(4)
        cls <- svmClassification(markerProteins = r.markers, 
                                            protein.data = df, 
                                            markerprot.df = markerProteins)
        
        test.A <- cls[[1]]\$svm.test.prob.out
        test.B <- cls[[2]]\$svm.test.prob.out
        all.A <- cls[[1]]\$all.prot.pred
        all.B <- cls[[2]]\$all.prot.pred
        
        # 7. Estimate and apply compartment-level thresholds
        t.c.df <- computeThresholdCompartment(test.repA = test.A, test.repB = test.B)
        c.cls.df <- applyThresholdCompartment(all.repA = all.A, all.repB = all.B,
                                            threshold.df = t.c.df)
        
        # 8. Estimate and apply neighborhood-level thresholds
        t.n.df <- computeThresholdNeighborhood(test.repA = test.A, test.repB = test.B)
        n.cls.df <- applyThresholdNeighborhood(all.repA = all.A, all.repB = all.B, 
                                            threshold.df = t.n.df)
        
        # 9. Merge compartment and neighborhood classifications
        cls.df <- mergeCls(compartmentCls = c.cls.df, neighborhoodCls = n.cls.df)
        
        # Save classification results to files
        write.csv(cls.df, "gene_centric_classification_results.csv", row.names = FALSE)
        saveRDS(cls.df, "gene_centric_classification_results.rds")
        write.csv(t.c.df, "compartment_thresholds.csv", row.names = FALSE)
        write.csv(t.n.df, "neighborhood_thresholds.csv", row.names = FALSE)
        
        # 10. Plot single protein barcode or multiple proteins
        # Save plots to a PDF file
        pdf("subcellular_localization_barcodes.pdf", width = 10, height = 8)
        
        # Plot single protein barcode (wrapped in tryCatch in case the specific protein is absent)
        tryCatch({
            print(plotBarcode(sampleClassification = cls.df, protein = "NLRP4",
                    s1PSM = hcc827CtrlPSMCount))
        }, error = function(e) {
            message("Skipping plotBarcode for NLRP4: ", e\$message)
        })
        
        # Plot multiple proteins (26S proteasome complex)
        proteasome26s <- c("PSMA7", "PSMC3","PSMA4", "PSMB4", 
                            "PSMB6", "PSMB5", "PSMC2","PSMC4",
                            "PSMB3", "PSMA6","PSMC5","PSMC6")
        
        tryCatch({
            print(plotMultipleProtein(sampleClassification = cls.df, proteinList = proteasome26s))
        }, error = function(e) {
            message("Skipping plotMultipleProtein: ", e\$message)
        })
        
        dev.off()
        
        message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_SUBCELLBARCODE_GENE_CENTRIC_CLASSIFICATION":',
        paste0('    SubCellBarCode: ', as.character(packageVersion('SubCellBarCode')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_centric_classification.csv versions.yml
    """
}

workflow BIOC_SUBCELLBARCODE_GENE_CENTRIC_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ protein_abundance.tsv, marker_proteins.tsv, psm_counts.tsv ] ]

    main:
    BIOC_SUBCELLBARCODE_GENE_CENTRIC_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_SUBCELLBARCODE_GENE_CENTRIC_CLASSIFICATION.out.tables
    plots    = BIOC_SUBCELLBARCODE_GENE_CENTRIC_CLASSIFICATION.out.plots
    objects  = BIOC_SUBCELLBARCODE_GENE_CENTRIC_CLASSIFICATION.out.objects
    versions = BIOC_SUBCELLBARCODE_GENE_CENTRIC_CLASSIFICATION.out.versions
}
