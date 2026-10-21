# DMAT

Research on Dependency–Mechanism Adequacy Theory (DMAT) and its benchmark, DMBench.

| Path | Holds |
| --- | --- |
| `models/` | Executable models (Racket, PLT Redex), v0.3: DMBench's eight scenario families, five arms per family (CHOR, FSM, COMM, HYBRID, HYBRID-NOE), an independent adequacy judge, P1–P3 as searches, independently authored arms with a differential check. See `models/README.md`. |

```
cd models
raco test tests.rkt
racket bench.rkt exact
racket bench.rkt sampled 100 results.jsonl
racket bench.rkt propositions
racket diff.rkt
```

Requires Racket 8.10 or later with `redex-lib`.
