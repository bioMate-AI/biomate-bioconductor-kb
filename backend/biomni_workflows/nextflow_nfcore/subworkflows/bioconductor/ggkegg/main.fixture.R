library(ggkegg)
library(dplyr)
library(tidygraph)

# Check if M00002 is shipped with ggkegg
m00002_path <- list.files(system.file("extdata", package="ggkegg"), pattern="M00002", full.names=TRUE, recursive=TRUE)

if (length(m00002_path) > 0) {
    file.copy(m00002_path[1], "M00002", overwrite = TRUE)
} else {
    # Mock KEGG module file for M00002
    m00002_content <- c(
        "ENTRY       M00002            Pathway   Module",
        "NAME        Glycolysis, core module involving three-carbon compounds",
        "DEFINITION  (K00134,K00150) K00927 K00161 K00114",
        "ORTHOLOGY   K00134  glyceraldehyde 3-phosphate dehydrogenase [EC:1.2.1.12]",
        "            K00150  glyceraldehyde 3-phosphate dehydrogenase (NADP+) [EC:1.2.1.9]",
        "            K00927  phosphoglycerate kinase [EC:2.7.2.3]",
        "            K00161  2,3-bisphosphoglycerate-dependent phosphoglycerate mutase [EC:5.4.2.11]",
        "            K00114  enolase [EC:4.2.1.11]",
        "CLASS       Pathway modules; Carbohydrate metabolism; Central carbohydrate metabolism",
        "PATHWAY     map00010  Glycolysis / Gluconeogenesis",
        "            map01100  Metabolic pathways",
        "            map01110  Biosynthesis of secondary metabolites",
        "            map01120  Microbial metabolism in diverse environments",
        "            map01130  Biosynthesis of antibiotics",
        "REACTION    R01061,R01063  C00118 -> C00236",
        "            R01512  C00236 -> C00197",
        "            R01518  C00197 -> C00631",
        "            R00658  C00631 -> C00074",
        "COMPOUND    C00118  D-Glyceraldehyde 3-phosphate",
        "            C00236  1,3-Bisphospho-D-glycerate",
        "            C00197  3-Phospho-D-glycerate",
        "            C00631  2-Phospho-D-glycerate",
        "            C00074  Phosphoenolpyruvate",
        "///"
    )
    writeLines(m00002_content, "M00002")
}