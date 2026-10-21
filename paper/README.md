# Dependency–Mechanism Adequacy (WP-2026-DM-01)

*Dependency–Mechanism Adequacy: A Formal and Empirical Framework for Coordination Protocols in Autonomous Multi-Actor Systems.* Wislet J. Celestin, WeOps Research, October 2026.

IEEE journal format (`IEEEtran`, two-column, double-sided).

## Build

```
make pdf        # pdflatex → bibtex → pdflatex → pdflatex
make release    # release/dmat-wp-2026-dm-01.pdf and release/dmat-wp-2026-dm-01-source.zip
make tables     # regenerate every table and the heat-map figure from the executable models (../models)
make clean      # remove intermediate files
```

Requires TeX Live with `IEEEtran`, `tikz`, `cleveref`, `longtable` and `stfloats`; `make tables` also requires Racket 8.10 or later with `redex-lib`.

## Layout

| Path | Holds |
| --- | --- |
| `main.tex` | Preamble, front matter, section and appendix order |
| `sections/` | Body sections I–XIII (`09b-implications.tex` is Section X) |
| `appendices/` | A proofs, B family specifications, C adjudication record, D complete exact results |
| `figures/heat.tex` | Worst-profile SFR heat map, generated from the models; the other seven figures are TikZ inline in their sections |
| `tables/` | Every numeric table, generated from the models by `paper-tables.rkt`; nothing is transcribed by hand |
| `bibliography/references.bib` | 52 references, all cited |
| `.github/workflows/build.yml` | Builds the release on a `paper-v*` tag and attaches it to the GitHub release |

## Provenance of the numbers

Every number in the paper is produced by the executable models in `../models` (v0.3): `paper-tables.rkt` writes `tables/`, `paper-heat.rkt` writes `figures/heat.tex`, and the body cites figures that the models' `bench.rkt`, `propositions.rkt` and `diff.rkt` also print.
