# arXiv submission — WP-2026-DM-01

Upload: `arxiv/dmat-wp-2026-dm-01-arxiv.tar.gz` (built by `make arxiv`; contains the sources and the generated `main.bbl`, and is checked to compile with pdflatex before it is written).

| Field | Value |
| --- | --- |
| Title | Dependency–Mechanism Adequacy: A Formal and Empirical Framework for Coordination Protocols in Autonomous Multi-Actor Systems |
| Authors | Wislet J. Celestin |
| Primary category | cs.MA (Multiagent Systems) |
| Cross-lists | cs.LO (Logic in Computer Science); cs.SE (Software Engineering) |
| Comments | 22 pages, 8 figures, 13 tables. WeOps Research Working Paper WP-2026-DM-01. Executable models, benchmark outputs and independently authored arms: https://github.com/Wescome/dmat |
| ACM classes | I.2.11; D.2.4; F.3.1 |
| Licence | per plan decision D5; the recommended choice is CC BY 4.0 |

## Abstract (plain text, 1734 characters; arXiv limit 1,920)

Coordination protocols are usually judged by whether their executions conform to a specification. That is distinct from whether a protocol manages the dependency it exists for, and whether a participant can know that it did. This paper develops Dependency–Mechanism Adequacy (DMAT), which defines adequacy relative to a dependency, an environment of admissible faults and an evidence model, and factors it into conduct (whether the dependency holds), observability (whether the participant's observations determine whether it holds) and interpretation (whether the participant's judgment is sound). Four contributions follow. First, an adequacy calculus in which the largest coverage any sound judge can attain equals the determinable mass of the protocol's observation model, so epistemic adequacy is a property of what a protocol makes observable; indistinguishability, composition and refinement results follow as theorems. Second, a method that builds the calculus as executable semantics: a closed PLT Redex language per scenario, a world model that alone holds oracle truth, and a judge that decides determinacy by exhaustive search, yielding exact metrics. Third, DMBench results over eight scenario families, five protocol arms and thirty-six fault profiles: no single paradigm is safe across the families, a hybrid with an explicit evidentiary discipline makes no false claim under any profile, and removing that discipline makes it unsafe in every family. Fourth, a differential protocol comparing arms written independently from specifications alone on all 1,309 reachable observation sequences; adjudication reduced 310 disagreements to 33 documented interpretive choices and exposed twelve errors in the reference arms.
