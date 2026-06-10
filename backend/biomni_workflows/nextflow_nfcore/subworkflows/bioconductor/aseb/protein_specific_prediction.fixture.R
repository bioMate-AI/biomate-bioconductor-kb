library(ASEB)

bg_file <- system.file("extdata", "background_sites.fa", package="ASEB")
if (file.exists(bg_file)) {
    file.copy(bg_file, "background_sites.fa", overwrite = TRUE)
} else {
    writeLines(c(">O60313_K698", "KEHDDIFDKLKEAVKEE", 
                 ">Q96H12_K26", "SILLALVEKYKYVLECK"), 
               "background_sites.fa")
}

predef_file <- system.file("extdata", "predefined_sites.fa", package="ASEB")
if (file.exists(predef_file)) {
    file.copy(predef_file, "predefined_sites.fa", overwrite = TRUE)
} else {
    writeLines(c(">P35227_K233", "KYRVQPACKRLTLATVP", 
                 ">Q9BX69_K747", "GNFNHVSLKASWVMGRP"), 
               "predefined_sites.fa")
}

prot_file <- system.file("extdata", "proteins_to_test.fa", package="ASEB")
if (file.exists(prot_file)) {
    file.copy(prot_file, "proteins_to_test.fa", overwrite = TRUE)
} else {
    writeLines(c(">protein_test1", "MKEHDDIFDKLKEAVKEESILLALVEKYKYVLECK"), 
               "proteins_to_test.fa")
}