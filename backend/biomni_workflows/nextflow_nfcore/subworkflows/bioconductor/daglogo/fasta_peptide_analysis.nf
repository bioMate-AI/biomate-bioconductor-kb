#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dagLogo — fasta_peptide_analysis
// Perform differential amino acid usage analysis using a local FASTA file for the proteome and a text file of peptide sequences.
// Input: grB.txt, HUMAN.fasta
// Container: quay.io/biocontainers/bioconductor-daglogo:1.48.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: dagLogo
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read peptide sequences from a text file
//  * 2. [Input & Preparation] Prepare a proteome object from a local FASTA file using prepareProteome
//  * 3. [Core Analysis] Format peptide sequences using formatSequence
//  * 4. [Input & Preparation] Build a background model using buildBackgroundModel
//  * 5. [Core Analysis] Test for differential amino acid usage (DAU) with or without grouping using testDAU
//  * 6. [Visualization & Output] Visualize results using dagHeatmap and dagLogo

nextflow.enable.dsl = 2

process BIOC_DAGLOGO_FASTA_PEPTIDE_ANALYSIS {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(dagLogo)
    
    # 1. Read peptide sequences from a local text file
    dat <- unlist(read.delim("grB.txt", header = FALSE, as.is = TRUE))
    
    # 2. Prepare a proteome object from a local FASTA file
    proteome <- prepareProteome(fasta = "HUMAN.fasta", species = "Homo sapiens")
    
    # 3. Format peptide sequences
    seq <- formatSequence(seq = dat, proteome = proteome, upstreamOffset = 14,
                          downstreamOffset = 15)
    
    # 4. Build a background model
    bg_ztest <- buildBackgroundModel(seq, background = "wholeProteome", 
                                     proteome = proteome, testType = "ztest")
    
    # 5. Test for differential amino acid usage (DAU) with various grouping schemes
    t0 <- testDAU(seq, dagBackground = bg_ztest)
    
    t1 <- testDAU(dagPeptides = seq, dagBackground = bg_ztest,
                  groupingScheme = "chemistry_property_Mahler_group")
    
    t2 <- testDAU(dagPeptides = seq, dagBackground = bg_ztest, 
                  groupingScheme = "charge_group")
    
    t3 <- testDAU(dagPeptides = seq, dagBackground = bg_ztest, 
                  groupingScheme = "consensus_similarity_SF_group")
    
    t4 <- testDAU(dagPeptides = seq, dagBackground = bg_ztest, 
                  groupingScheme = "hydrophobicity_KD")
    
    # Define and add a custom grouping scheme
    color = c(LVIMC = "#33FF00", AGSTP = "#CCFF00",
              FYW = '#00FF66', EDNQKRH = "#FF0066")
    symbol = c(LVIMC = "L", AGSTP = "A", FYW = "F", EDNQKRH = "E")
    group = list(
        LVIMC = c("L", "V", "I", "M", "C"), 
        AGSTP = c("A", "G", "S", "T", "P"),
        FYW = c("F", "Y", "W"),
        EDNQKRH = c("E", "D", "N", "Q", "K", "R", "H"))
    addScheme(color = color, symbol = symbol, group = group) 
    
    t5 <- testDAU(dagPeptides = seq, dagBackground = bg_ztest, 
                  groupingScheme = "custom_group")
    
    # Save the test results as RDS objects
    saveRDS(t0, "t0_ungrouped.rds")
    saveRDS(t1, "t1_chemistry_property.rds")
    saveRDS(t2, "t2_charge_group.rds")
    saveRDS(t3, "t3_consensus_similarity.rds")
    saveRDS(t4, "t4_hydrophobicity.rds")
    saveRDS(t5, "t5_custom_group.rds")
    
    # 6. Visualize results and save to a PDF file
    pdf("dagLogo_analysis_plots.pdf", width = 8, height = 6)
    
    dagHeatmap(t0)
    dagLogo(t0)
    dagLogo(t1, groupingSymbol = getGroupingSymbol(t1@group), legend = TRUE)
    dagLogo(t2, groupingSymbol = getGroupingSymbol(t2@group), legend = TRUE)
    dagLogo(t3, groupingSymbol = getGroupingSymbol(t3@group), legend = TRUE)
    dagLogo(t4, groupingSymbol = getGroupingSymbol(t4@group), legend = TRUE)
    
    dev.off()

    writeLines(c(
        '"BIOC_DAGLOGO_FASTA_PEPTIDE_ANALYSIS":',
        paste0('    dagLogo: ', as.character(packageVersion('dagLogo')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fasta_peptide_analysis.csv versions.yml
    """
}

workflow BIOC_DAGLOGO_FASTA_PEPTIDE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ grB.txt, HUMAN.fasta ] ]

    main:
    BIOC_DAGLOGO_FASTA_PEPTIDE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DAGLOGO_FASTA_PEPTIDE_ANALYSIS.out.tables
    plots    = BIOC_DAGLOGO_FASTA_PEPTIDE_ANALYSIS.out.plots
    objects  = BIOC_DAGLOGO_FASTA_PEPTIDE_ANALYSIS.out.objects
    versions = BIOC_DAGLOGO_FASTA_PEPTIDE_ANALYSIS.out.versions
}
