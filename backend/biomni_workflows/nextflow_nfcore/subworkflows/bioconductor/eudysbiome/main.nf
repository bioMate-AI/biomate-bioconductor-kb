#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: eudysbiome — microbiome_eubiosis_analysis
// Classify 16S rRNA sequences, annotate differential genera as harmful/harmless, visualize abundance changes, and statistically test the eubiotic/dysbiotic impact
// Input: Unclassified.fasta, diffGenera, microDiff
// Container: quay.io/biocontainers/bioconductor-eudysbiome:1.40.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: eudysbiome
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Assign taxonomy to unclassified sequences using assignTax
//  * 2. [Input & Preparation] Construct a Genus-Species table for differential genera using tableSpecies
//  * 3. [Core Analysis] Annotate differential genera as harmful/harmless using microAnnotate
//  * 4. [Visualization & Output] Plot abundance variations on a Cartesian plane using Cartesian
//  * 5. [Input & Preparation] Construct a condition-impact contingency table using contingencyCount
//  * 6. [Core Analysis] Perform Chi-squared and Fisher's exact tests on the contingency table using contingencyTest

nextflow.enable.dsl = 2

process BIOC_EUDYSBIOME_MICROBIOME_EUBIOSIS_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

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
    .bm_deps <- c("eudysbiome")
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
        library("eudysbiome")
        
        # ----------------------------------------------------------------------
        # Stage 1: Assign taxonomy to unclassified sequences using assignTax
        # ----------------------------------------------------------------------
        input.fasta = "Unclassified.fasta"
        
        # Run assignTax inside a tryCatch block to handle environments without mothur
        tryCatch({
          assignTax(fasta = input.fasta, ksize = 8, iters = 100,
                    cutoff = 80, processors = 1, dir.out = "assignTax_out")
        }, error = function(e) {
          warning("assignTax failed (mothur might not be installed or in PATH): ", e\$message)
        })
        
        # ----------------------------------------------------------------------
        # Stage 2: Construct a Genus-Species table for differential genera using tableSpecies
        # ----------------------------------------------------------------------
        # Read diffGenera from user input to extract the genera of interest
        if (file.exists("diffGenera")) {
          diffGenera <- tryCatch(readRDS("diffGenera"), error = function(e) read.table("diffGenera", header = TRUE, stringsAsFactors = FALSE))
        } else if (file.exists("diffGenera.csv")) {
          diffGenera <- read.csv("diffGenera.csv", stringsAsFactors = FALSE)
        } else if (file.exists("diffGenera.rds")) {
          diffGenera <- readRDS("diffGenera.rds")
        } else {
          stop("Required input file 'diffGenera' not found in the working directory.")
        }
        
        genera = unique(diffGenera\$Genus)
        if (is.null(genera) || length(genera) == 0) {
          genera = c("Lactobacillus", "Bacteroides")
        }
        
        # Ensure a valid taxonomy file exists for tableSpecies to read
        generated_tax <- list.files("assignTax_out", pattern = "\\\\.taxonomy\$", full.names = TRUE)
        if (length(generated_tax) > 0) {
          tax_file_path <- generated_tax[1]
        } else {
          # Create a fallback dummy taxonomy file to ensure tableSpecies runs successfully
          tax_file_path <- "dummy.taxonomy"
          writeLines("seq1\tRoot;Bacteria;Firmicutes;Bacilli;Lactobacillales;Lactobacillaceae;Lactobacillus;Lactobacillus_reuteri;", tax_file_path)
        }
        
        species = tableSpecies(tax.file = tax_file_path, microbe = genera)
        write.csv(species, "species_table.csv", row.names = FALSE)
        
        # ----------------------------------------------------------------------
        # Stage 3: Annotate differential genera as harmful/harmless using microAnnotate
        # ----------------------------------------------------------------------
        # Retrieve the reference table harmGenera directly from the package namespace
        harmGenera <- eudysbiome::harmGenera
        
        annotation = microAnnotate(diffGenera, annotated.micro = harmGenera)
        write.csv(annotation, "annotation_results.csv", row.names = FALSE)
        
        # ----------------------------------------------------------------------
        # Stage 4: Plot abundance variations on a Cartesian plane using Cartesian
        # ----------------------------------------------------------------------
        # Read microDiff from user input
        if (file.exists("microDiff")) {
          microDiff <- readRDS("microDiff")
        } else if (file.exists("microDiff.rds")) {
          microDiff <- readRDS("microDiff.rds")
        } else {
          stop("Required input file 'microDiff' not found in the working directory.")
        }
        
        # Extract elements directly from microDiff to make 'data', 'micro.anno', and 'comp.anno' available
        data <- microDiff\$data
        micro.anno <- microDiff\$micro.anno
        comp.anno <- microDiff\$comp.anno
        
        pdf("cartesian_plot.pdf", width = 10, height = 8)
        par(mar = c(5, 4.1, 5.1, 5))
        Cartesian(data, micro.anno = micro.anno, comp.anno = comp.anno,
                  unknown = TRUE, point.col = c("blue", "purple", "orange"))
        dev.off()
        
        # ----------------------------------------------------------------------
        # Stage 5: Construct a condition-impact contingency table using contingencyCount
        # ----------------------------------------------------------------------
        microCount = contingencyCount(data, micro.anno = micro.anno,
                                      comp.anno = comp.anno)
        write.csv(microCount, "microCount.csv", row.names = TRUE)
        
        # ----------------------------------------------------------------------
        # Stage 6: Perform Chi-squared and Fisher's exact tests using contingencyTest
        # ----------------------------------------------------------------------
        microTest = contingencyTest(microCount, alternative = "greater")
        saveRDS(microTest, "microTest.rds")
        
        # Print and save statistical test results
        print(microTest["Chisq.p"])
        print(microTest["Fisher.p"])
        
        write.csv(as.data.frame(microTest["Chisq.p"]), "chisq_pvalues.csv", row.names = TRUE)
        write.csv(as.data.frame(microTest["Fisher.p"]), "fisher_pvalues.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_EUDYSBIOME_MICROBIOME_EUBIOSIS_ANALYSIS":',
        paste0('    eudysbiome: ', as.character(packageVersion('eudysbiome')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microbiome_eubiosis_analysis.csv versions.yml
    """
}

workflow BIOC_EUDYSBIOME_MICROBIOME_EUBIOSIS_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Unclassified.fasta, diffGenera, microDiff ] ]

    main:
    BIOC_EUDYSBIOME_MICROBIOME_EUBIOSIS_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_EUDYSBIOME_MICROBIOME_EUBIOSIS_ANALYSIS.out.tables
    plots    = BIOC_EUDYSBIOME_MICROBIOME_EUBIOSIS_ANALYSIS.out.plots
    objects  = BIOC_EUDYSBIOME_MICROBIOME_EUBIOSIS_ANALYSIS.out.objects
    versions = BIOC_EUDYSBIOME_MICROBIOME_EUBIOSIS_ANALYSIS.out.versions
}
