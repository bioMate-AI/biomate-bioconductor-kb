#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rbiopaxparser — parse_and_visualize_biopax
// Parse an existing BioPAX OWL file, extract a specific pathway, convert it to a regulatory graph, and visualize it.
// Input: file.owl
// Container: quay.io/biocontainers/bioconductor-rbiopaxparser:2.50.0--r45hdfd78af_0
// R packages: rBiopaxParser
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RBIOPAXPARSER_PARSE_AND_VISUALIZE_BIOPAX {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rbiopaxparser:2.50.0--r45hdfd78af_0"

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
    .bm_deps <- c("rBiopaxParser")
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
    library(rBiopaxParser)
    
    # Define the input file as specified by the user
    file <- "file.owl"
    
    # Check if the input file exists
    if (!file.exists(file)) {
      stop("Error: 'file.owl' not found in the working directory. Please provide a valid BioPAX OWL file.")
    }
    
    # 1. Parse the BioPAX file into R
    biopax = readBiopax(file)
    print(biopax)
    
    # 2. List and select pathway instances
    pw_list = listInstances(biopax, class="pathway")
    pw_complete = selectInstances(biopax, class="pathway")
    
    # Define the pathway ID to extract
    pwid1 = "pid_p_100002_wntpathway"
    
    # Robust fallback: if the hardcoded pathway ID is not present in the user's file,
    # use the first available pathway ID to ensure the pipeline runs successfully.
    if (!is.null(pw_list) && nrow(pw_list) > 0) {
      if (!(pwid1 %in% pw_list\$id)) {
        pwid1 = pw_list\$id[1]
        message("Warning: Hardcoded pathway ID 'pid_p_100002_wntpathway' not found. Using '", pwid1, "' instead.")
      }
    } else {
      stop("Error: No pathways found in the provided BioPAX file.")
    }
    
    # Retrieve properties and components of the selected pathway
    getInstanceProperty(biopax, pwid1, property="NAME")
    pw_1 = selectInstances(biopax, class="pathway", id=pwid1)
    pw_1_component_list = listPathwayComponents(biopax,pwid1)
    pw_1_components = selectInstances(biopax,id=pw_1_component_list\$id)
    
    # 3. Convert the selected pathway to a regulatory graph and adjacency matrix
    pw_1_adj = pathway2AdjacancyMatrix(biopax, pwid1, expandSubpathways=TRUE, splitComplexMolecules=TRUE, verbose=TRUE)
    pw_1_graph = pathway2RegulatoryGraph(biopax, pwid1, splitComplexMolecules=TRUE, verbose=TRUE)
    
    # 4. Layout and plot the regulatory graph
    pw_1_graph_laidout = layoutRegulatoryGraph(pw_1_graph)
    
    # Save the visualization to a PDF file
    pdf("regulatory_graph.pdf", width=10, height=8)
    plotRegulatoryGraph(pw_1_graph)
    dev.off()
    
    # Save meaningful results to output files
    write.csv(pw_list, "pathway_list.csv", row.names=FALSE)
    saveRDS(pw_complete, "pathway_complete.rds")
    write.csv(pw_1_component_list, "pathway_components_list.csv", row.names=FALSE)
    saveRDS(pw_1_components, "pathway_components.rds")
    write.csv(as.data.frame(pw_1_adj), "pathway_adjacency_matrix.csv")
    saveRDS(pw_1_graph, "regulatory_graph.rds")
    saveRDS(pw_1_graph_laidout, "regulatory_graph_laidout.rds")
    
    message("Pipeline completed successfully. Outputs saved to the working directory.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_RBIOPAXPARSER_PARSE_AND_VISUALIZE_BIOPAX":
        rbiopaxparser: \$(Rscript -e 'cat(as.character(packageVersion("rbiopaxparser")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_parse_and_visualize_biopax.csv versions.yml
    """
}

workflow BIOC_RBIOPAXPARSER_PARSE_AND_VISUALIZE_BIOPAX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file.owl ] ]

    main:
    BIOC_RBIOPAXPARSER_PARSE_AND_VISUALIZE_BIOPAX(ch_input)

    emit:
    tables   = BIOC_RBIOPAXPARSER_PARSE_AND_VISUALIZE_BIOPAX.out.tables
    plots    = BIOC_RBIOPAXPARSER_PARSE_AND_VISUALIZE_BIOPAX.out.plots
    objects  = BIOC_RBIOPAXPARSER_PARSE_AND_VISUALIZE_BIOPAX.out.objects
    versions = BIOC_RBIOPAXPARSER_PARSE_AND_VISUALIZE_BIOPAX.out.versions
}
