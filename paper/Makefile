# DMAT paper — IEEE journal, two-column, double-sided.
MAIN    = main
TABLES  = tables/adversarial.tex tables/worst.tex tables/ceiling.tex tables/exact-full.tex \
          tables/p1.tex tables/p2.tex tables/p3.tex tables/families.tex
SOURCES = $(MAIN).tex $(wildcard sections/*.tex) $(wildcard appendices/*.tex) \
          $(wildcard figures/*.tex) bibliography/references.bib $(TABLES)
MODELS ?= ../models

.PHONY: pdf tables clean cleanall release arxiv

pdf: $(MAIN).pdf

$(MAIN).pdf: $(SOURCES)
	pdflatex -interaction=nonstopmode -halt-on-error $(MAIN)
	bibtex $(MAIN)
	pdflatex -interaction=nonstopmode -halt-on-error $(MAIN)
	pdflatex -interaction=nonstopmode -halt-on-error $(MAIN)

# Regenerate every table and the heat-map figure from the executable models.
tables:
	racket $(MODELS)/paper-tables.rkt tables
	racket $(MODELS)/paper-heat.rkt > figures/heat.tex

release: pdf
	rm -rf release && mkdir -p release
	cp $(MAIN).pdf release/dmat-wp-2026-dm-01.pdf
	zip -qr release/dmat-wp-2026-dm-01-source.zip $(MAIN).tex sections appendices figures tables \
	    bibliography Makefile README.md .github

# arXiv source package: sources plus the generated .bbl (arXiv does not run bibtex).
arxiv: pdf
	rm -rf arxiv && mkdir -p arxiv/src
	cp -r $(MAIN).tex $(MAIN).bbl sections appendices figures tables arxiv/src/
	cd arxiv/src && tar czf ../dmat-wp-2026-dm-01-arxiv.tar.gz *
	cd arxiv && mkdir check && tar xzf dmat-wp-2026-dm-01-arxiv.tar.gz -C check && cd check && \
	  pdflatex -interaction=nonstopmode -halt-on-error $(MAIN) >/dev/null && \
	  pdflatex -interaction=nonstopmode -halt-on-error $(MAIN) >/dev/null && \
	  pdflatex -interaction=nonstopmode -halt-on-error $(MAIN) >/dev/null && echo "arxiv package builds"
	rm -rf arxiv/src arxiv/check

clean:
	rm -f $(MAIN).aux $(MAIN).bbl $(MAIN).blg $(MAIN).log $(MAIN).out $(MAIN).toc

cleanall: clean
	rm -f $(MAIN).pdf
	rm -rf release arxiv
