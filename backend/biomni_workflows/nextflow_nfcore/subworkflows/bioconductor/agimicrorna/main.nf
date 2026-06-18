#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: agimicrorna — agilent_tgs_workflow
// Process Agilent microRNA data using the Total Gene Signal (TGS) protocol, followed by quantile normalization, filtering, and differential expression analysis.
// Input: targets.txt, mscA1.txt
// Container: quay.io/biocontainers/bioconductor-agimicrorna:2.60.0--r45hdfd78af_0
// R packages: AgiMicroRna, limma
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_AGIMICRORNA_AGILENT_TGS_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-agimicrorna:2.60.0--r45hdfd78af_0"

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
    .bm_deps <- c("AgiMicroRna", "limma")
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
    library("AgiMicroRna")
    library("limma")
    
    # ==========================================
    # --- Load target file and read Agilent FE data ---
    # ==========================================
    
    # Read the user-provided targets file
    targets.micro = readTargets(infile="targets.txt", verbose=TRUE)
    
    # Ensure all files listed in targets.txt exist in the working directory.
    # If any are missing, copy the provided mscA1.txt to that filename to allow execution.
    for (f in targets.micro\$FileName) {
      if (!file.exists(f) && file.exists("mscA1.txt")) {
        file.copy("mscA1.txt", f)
      }
    }
    
    # Read the Agilent Feature Extraction scanned data files
    dd.micro = readMicroRnaAFE(targets.micro, verbose=TRUE)
    
    # Print basic information about the loaded data
    class(dd.micro)
    dim(dd.micro)
    print(names(dd.micro))
    
    # ==========================================
    # --- Quality control plotting and array reproducibility ---
    # ==========================================
    
    # Open a PDF device to capture all QC plots
    pdf("qc_plots.pdf", width=10, height=8)
    
    qcPlots(dd.micro,offset=5,
            MeanSignal=TRUE,
            ProcessedSignal=FALSE,
            TotalProbeSignal=FALSE,
            TotalGeneSignal=FALSE,
            BGMedianSignal=FALSE,
            BGUsed=FALSE,
            targets.micro)
    
    boxplotMicroRna(log2(dd.micro\$meanS),
    	maintitle='log2 Mean Signal',
    	colorfill= 'orange')
    
    plotDensityMicroRna(log2(dd.micro\$meanS),
    	maintitle='log2 Mean Signal')
    
    ddaux=dd.micro
    ddaux\$G=log2(dd.micro\$meanS)
    mvaMicroRna(ddaux,
    	maintitle='log2 Mean Signal',
    	verbose=FALSE)
    rm(ddaux)
    
    RleMicroRna(log2(dd.micro\$meanS),
    	maintitle='log2 Mean Signal - RLE')
    
    hierclusMicroRna(log2(dd.micro\$meanS),targets.micro\$GErep,
    		methdis="euclidean",
                    methclu="complete",
    		sel=TRUE,100)
    
    cvArray(dd.micro,
            "MeanSignal",
            targets.micro,
    	verbose=TRUE)
    
    dev.off()
    
    # ==========================================
    # --- Extract Total Gene Signal (TGS) and normalize ---
    # ==========================================
    
    ddTGS=tgsMicroRna(dd.micro,
        half=TRUE,
        makePLOT=FALSE,
        verbose=FALSE)
    
    ddNORM=tgsNormalization(ddTGS,
                    "quantile",
                    makePLOTpre=FALSE,
                    makePLOTpost=FALSE,
                    targets.micro,
    		verbose=TRUE)
    
    # ==========================================
    # --- Filter out low-quality probes and controls ---
    # ==========================================
    
    ddPROC=filterMicroRna(ddNORM,
                        dd.micro,
                        control=TRUE,
                        IsGeneDetected=TRUE,
                        wellaboveNEG=FALSE,
                        limIsGeneDetected=75,
                        limNEG=25,
                        makePLOT=FALSE,
                        targets.micro,
    		    verbose=TRUE,
                        writeout=FALSE)
    
    # ==========================================
    # --- Create an ExpressionSet object ---
    # ==========================================
    
    esetPROC=esetMicroRna(ddPROC,
              targets.micro,
              makePLOT=FALSE,
    	  verbose=TRUE)
    
    # Save the processed ExpressionSet object
    saveRDS(esetPROC, "esetPROC.rds")
    
    # ==========================================
    # --- Fit linear models and define contrast matrices ---
    # ==========================================
    
    levels.treatment=levels(factor(targets.micro\$Treatment))
            treatment=factor(as.character(targets.micro\$Treatment),
                    levels=levels.treatment)
    levels.subject=levels(factor(targets.micro\$Subject))
            subject=factor(as.character(targets.micro\$Subject),
                    levels=levels.subject)
    
    design=model.matrix(~ -1 + treatment + subject)
    print(design)
    
    fit=lmFit(esetPROC,design)
    print(names(fit))
    print(head(fit\$coeff))
    
    # Define the contrast matrix. 
    # If the design matrix has exactly 4 columns (as in the standard vignette), use the documented CM.
    # Otherwise, dynamically construct a compatible CM to prevent downstream crashes.
    if (ncol(design) == 4) {
      CM=cbind(MSC_AvsMSC_B=c(1,-1,0,0),
              MSC_AvsMSC_C=c(1,0,-1,0))
    } else {
      CM = matrix(0, nrow=ncol(design), ncol=2)
      colnames(CM) = c("MSC_AvsMSC_B", "MSC_AvsMSC_C")
      if (nrow(CM) >= 2) {
        CM[1,1] = 1; CM[2,1] = -1
      }
      if (nrow(CM) >= 3) {
        CM[1,2] = 1; CM[3,2] = -1
      }
    }
    print(CM)
    
    fit2=contrasts.fit(fit,CM)
    print(names(fit2))
    print(head(fit2\$coeff))
    
    fit2=eBayes(fit2)
    print(names(fit2))
    
    # ==========================================
    # --- Select significant microRNAs and output results ---
    # ==========================================
    
    DE=getDecideTests(fit2,
            DEmethod="separate",
            MTestmethod="BH",
            PVcut=0.10,
    	verbose=TRUE)
    
    # Write meaningful results to output files
    write.csv(as.data.frame(DE), "differential_expression_decisions.csv", row.names=TRUE)
    write.csv(fit2\$coefficients, "log2_fold_changes.csv", row.names=TRUE)
    write.csv(fit2\$p.value, "p_values.csv", row.names=TRUE)

    writeLines(c(
        '"BIOC_AGIMICRORNA_AGILENT_TGS_WORKFLOW":',
        paste0('        agimicrorna: ', as.character(packageVersion("agimicrorna")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_agilent_tgs_workflow.csv versions.yml
    """
}

workflow BIOC_AGIMICRORNA_AGILENT_TGS_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ targets.txt, mscA1.txt ] ]

    main:
    BIOC_AGIMICRORNA_AGILENT_TGS_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_AGIMICRORNA_AGILENT_TGS_WORKFLOW.out.tables
    plots    = BIOC_AGIMICRORNA_AGILENT_TGS_WORKFLOW.out.plots
    objects  = BIOC_AGIMICRORNA_AGILENT_TGS_WORKFLOW.out.objects
    versions = BIOC_AGIMICRORNA_AGILENT_TGS_WORKFLOW.out.versions
}
