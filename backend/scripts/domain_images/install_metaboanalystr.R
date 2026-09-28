#!/usr/bin/env Rscript
# MetaboAnalystR + OptiLCMS install — run as a FILE (COPY + Rscript), NOT inline
# `Rscript -e '...'`. Long/complex inline R code does not survive the Dockerfile
# RUN -> /bin/sh -> Rscript -e transport intact: it corrupted twice at different
# points ("OptiLCMS/archive" and "/tmp/opti.tar.gz" both split mid-string ->
# "unexpected symbol" parse errors). A file is byte-exact and needs zero shell
# escaping. Self-gates on MetaboAnalystR's heavy Bioc deps so it is a no-op for
# every non-metabolomics domain that shares this template.

gate <- all(vapply(c("impute", "pcaMethods", "siggenes", "limma"),
                   function(p) requireNamespace(p, quietly = TRUE), logical(1)))
if (!gate) {
  cat("Skipping MetaboAnalystR (non-metabolomics domain)\n")
  quit(status = 0)
}

if (!requireNamespace("remotes", quietly = TRUE)) {
  install.packages("remotes", repos = "https://packagemanager.posit.co/cran/2024-10-30")
}
# CAMERA (transitive dep) needs xfun >= 0.52; the deps snapshot pins 0.48 for mia,
# but mia is not in metabolomics — safe to bump here too as a belt-and-suspenders.
if (utils::packageVersion("xfun") < "0.52") {
  install.packages("xfun", repos = "https://cloud.r-project.org")
}

# First attempt: installs all of OptiLCMS's deps, then tries to compile OptiLCMS.
# Its src/mzClust.cpp uses std::array but omits #include <array>; GCC 13 (the noble
# base) no longer pulls <array> in transitively -> "incomplete type" compile error.
# So this attempt installs the DEPS but the package itself fails — tolerated.
try(remotes::install_github("xia-lab/OptiLCMS", upgrade = "never", quiet = FALSE),
    silent = TRUE)

if (!requireNamespace("OptiLCMS", quietly = TRUE)) {
  cat("[optilcms-patch] OptiLCMS compile failed (mzClust.cpp missing #include <array>);",
      "patching via R file-IO + local install. Deps were installed by the attempt above.\n")
  download.file("https://github.com/xia-lab/OptiLCMS/archive/refs/heads/master.tar.gz",
                "/tmp/opti.tar.gz", quiet = TRUE)
  untar("/tmp/opti.tar.gz", exdir = "/tmp")
  f <- "/tmp/OptiLCMS-master/src/mzClust.cpp"
  writeLines(c("#include <array>", readLines(f)), f)
  if (system("R CMD INSTALL /tmp/OptiLCMS-master") != 0) {
    stop("OptiLCMS patched local install failed")
  }
}

remotes::install_github("xia-lab/MetaboAnalystR", upgrade = "never",
                        build = FALSE, quiet = FALSE)

ok <- requireNamespace("OptiLCMS", quietly = TRUE) &&
      requireNamespace("MetaboAnalystR", quietly = TRUE)
cat("OptiLCMS present:", requireNamespace("OptiLCMS", quietly = TRUE),
    "| MetaboAnalystR present:", requireNamespace("MetaboAnalystR", quietly = TRUE), "\n")
if (!ok) {
  stop("OptiLCMS/MetaboAnalystR failed to install — failing the build loudly")
}
