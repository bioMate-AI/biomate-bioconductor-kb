library(msa)
library(Biostrings)

# Attempt to locate the example file shipped with the package
src_file <- system.file("examples", "exampleAA.fasta", package="msa")

if (file.exists(src_file)) {
    file.copy(src_file, "exampleAA.fasta", overwrite = TRUE)
} else {
    # Fallback: construct a synthetic FASTA file if the package file is missing
    mySequences <- AAStringSet(c(
        Seq1 = "MVHLTPEEKSAVTALWGKVNVDEVGGEALGRLLVVYPWTQRFFESFGDLSTPDAVMGNPKVKAHGKKVLGAFSDGLAHLDNLKGTFATLSELHCDKLHVDPENFRLLGNVLVCVLAHHFGKEFTPPVQAAYQKVVAGVANALAHKYH",
        Seq2 = "MVHLTPEEKSAVTALWGKVNVDEVGGEALGRLLVVYPWTQRFFESFGDLSTPDAVMGNPKVKAHGKKVLGAFSDGLAHLDNLKGTFATLSELHCDKLHVDPENFRLLGNVLVCVLAHHFGKEFTPPVQAAYQKVVAGVANALAHKYH",
        Seq3 = "MVHLTPEEKSAVTALWGKVNVDEVGGEALGRLLVVYPWTQRFFESFGDLSTPDAVMGNPKVKAHGKKVLGAFSDGLAHLDNLKGTFATLSELHCDKLHVDPENFRLLGNVLVCVLAHHFGKEFTPPVQAAYQKVVAGVANALAHKYH"
    ))
    writeXStringSet(mySequences, filepath = "exampleAA.fasta")
}