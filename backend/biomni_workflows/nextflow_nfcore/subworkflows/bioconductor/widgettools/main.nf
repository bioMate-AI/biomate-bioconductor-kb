#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: widgetTools
// This packages contains tools to support the construction of tcltk widgets
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/widgetTools/inst/doc/widgetTools.R
// Upstream  : none
// Downstream: tkWidgets
//
// Install: BiocManager::install("widgetTools")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_WIDGETTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-widgettools"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_widgettools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_widgettools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_widgettools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(widgetTools)
    library(jsonlite)

    # --- Widget Environment Setup ---
    # Key functions: label, entryBox, button, wName, wValue<-
    PWEnv <- new.env(hash = TRUE, parent = parent.frame(1))
    label1 <- label(wName = "label1", wValue = "File Name: ", wEnv = PWEnv)
    entry1 <- entryBox(wName = "entry1", wValue = "Feed me using browse",
                       wEnv = PWEnv)
    browse2Entry1 <- function() {
        temp <- get(wName(entry1), env = PWEnv)
        wValue(temp) <- "selected_file.txt"
        assign(wName(entry1), temp, env = PWEnv)
    }
    button1 <- button(wName = "button1", wValue = "Browse",
                      wFuns = list(command = browse2Entry1), wEnv = PWEnv)

    # --- Widget Component Definition ---
    # Key functions: listBox, textBox, radioButton, checkButton
    list1 <- listBox(wName = "list1", wValue = c(Option1 = TRUE,
                     Option2 = FALSE, Option3 = FALSE), wEnv = PWEnv)
    text1 <- textBox(wName = "text1", wValue = "Feed me something",
                     wEnv = PWEnv)
    label2 <- label(wName = "label2", wValue = "Select one:  ",
                    wEnv = PWEnv)
    radios1 <- radioButton(wName = "radios1", wValue = c(radio1 = TRUE,
                           radio2 = FALSE, radio3 = FALSE), wEnv = PWEnv)
    checks1 <- checkButton(wName = "checks1", wValue = c(check1 = TRUE,
                           check2 = FALSE, check3 = FALSE), wEnv = PWEnv)

    # --- Widget Attribute Manipulation ---
    # Key functions: wName, wName<-, wValue<-
    current_name <- wName(label1)
    wName(label1) <- "new_label_name"
    restored_name <- wName(label1)
    wName(label1) <- "label1"
    wValue(entry1) <- "Updated File Path"

    # --- Widget Assembly ---
    # Key functions: widget
    pWidgets <- list(
        topRow = list(label1 = label1, entry1 = entry1, button1 = button1),
        textRow = list(list1 = list1, text1 = text1),
        radGroup = list(label2 = label2, radios1 = radios1)
    )
    aWidget <- widget(wTitle = "A test widget", pWidgets, funs = list(),
                      preFun = function() { "Starting widget" },
                      postFun = function() { "Closing widget" },
                      env = PWEnv)

    # --- Widget State Querying ---
    # Key functions: pWidgets, wValue
    widget_components <- pWidgets(aWidget)
    val_entry <- wValue(widget_components[["topRow"]][["entry1"]])
    val_list <- wValue(widget_components[["textRow"]][["list1"]])
    val_radios <- wValue(widget_components[["radGroup"]][["radios1"]])


    # --- Save outputs ---
    .objs <- setdiff(ls(), c("args", "prefix", ".objs"))
    .cells <- function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                            if (is.data.frame(x) || is.matrix(x)) prod(dim(x)) else -1 }
    .dfs  <- Filter(function(v) is.data.frame(tryCatch(get(v), error = function(e) NULL)), .objs)
    .tabs <- Filter(function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                                  is.data.frame(x) || is.matrix(x) }, .objs)
    .cand <- if (length(.dfs) > 0) .dfs else .tabs
    if (length(.cand) > 0) {
        .main <- get(.cand[[ which.max(sapply(.cand, .cells)) ]])
        write.csv(as.data.frame(.main), "${prefix}_widgettools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_widgettools_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_widgettools_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_WIDGETTOOLS:", paste0("    widgettools: ", as.character(packageVersion("widgetTools")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_widgettools_results.csv
    touch ${prefix}_widgettools_output.rds
    echo "BIOC_WIDGETTOOLS:" > versions.yml
    echo "    widgettools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_WIDGETTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_WIDGETTOOLS(ch_input)

    emit:
    results  = BIOC_WIDGETTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_WIDGETTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_WIDGETTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_WIDGETTOOLS.out.versions  // channel: path(versions.yml)
}
