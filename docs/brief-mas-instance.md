---
id: DMAT-BRIEF-I3-MAS-2026-10
title: DMAT instance I-3 — multiagent systems
date: 2026-10-21
status: brief; decisions in §6 are the owner's
parent: docs/plan-audience-instances.md (decision D1 taken: I-3 first)
---

# DMAT instance I-3 — multiagent systems

## 1. Decision and resequencing

D1 is taken: the multiagent-systems instance goes first. The phase table in `plan-audience-instances.md` changes accordingly:

| Phase | Work | Model version |
| --- | --- | --- |
| 1 (done) | Core framework; models v0.3; hub paper WP-2026-DM-01 | v0.3 |
| 2 | Post the hub on arXiv; tag `models-v0.3`, `paper-v1`; venue windows (done for I-3, §2) | v0.3 |
| 3 | **I-3 multiagent systems** (this brief) | v0.4: BSPL/Cupid arms, evidential Cupid, enactment harness |
| 4 | I-1 formal methods; I-2 runtime verification; I-4 session types | v0.5 |
| 5 | I-5 software engineering | v1.0 |
| 6–9 | unchanged (I-6, I-11; I-8; I-7; I-9, I-10) | v1.0–v1.1 |

## 2. Venue facts (checked 2026-10-21)

- **AAMAS 2027 main track** is closed: abstracts were due 1 October 2026 and papers 8 October 2026; notification 21 December 2026; conference 3–7 May 2027. Relevant areas are COINE (coordination, organizations, institutions, norms), EMAS (engineering and analysis of MAS, including agent-to-agent protocols and business agreements) and GAAI (interaction protocols for agentic AI).
- **Workshops at AAMAS 2027** (EMAS, COINE): calls not yet published. EMAS 2026's submission deadline was 11 February 2026, so the 2027 deadlines should fall in February 2027. Both workshops have published LNCS post-proceedings in past editions; post-proceedings count as archival publication.
- **JAAMAS** accepts submissions continuously. Its track at AAMAS lets authors of an article accepted or published in JAAMAS within the twelve months before the AAMAS notification date present it, through a two-page abstract; the article must not extend a full paper already published in an archival conference.
- **AAMAS 2028 main track**: by the annual pattern, paper deadline early October 2027.

## 3. The instance

**Working title.** *Evidence Is Not Discharge: Evidential Commitment Semantics and the Limits of Compliance Judgment in Multiagent Protocols.*

**Audience question.** Do commitment-based protocols deliver accountability, and what must be added for an agent to know whether a commitment was discharged?

**Thesis.** Commitments give a protocol responsibility continuity but not evidence soundness. A creditor's commitment state is computed from what the creditor holds, and what it holds can be the debtor's own report, a stale record, or nothing; whether the creditor can know the commitment's true state is bounded by the observation model, not by the commitment semantics. An evidential layer on commitments (discharge requires evidence independent of the debtor; violation requires a record complete through the deadline; otherwise indeterminate) is sound under every fault DMBench admits, and removing it makes the protocol unsafe in every scenario family.

**Contributions (four, each defended in the body).**

1. **Evidential commitment semantics.** E1–E3 stated as rules over the commitment lifecycle (created, detached, discharged, expired, violated, released, delegated, pending), with soundness proved relative to an observation model, and the hub's ceiling theorem specialized: the coverage of any sound creditor judgment is at most the determinable mass of the creditor's information.
2. **Commitment protocols in the community's own formalisms.** For each of DMBench's eight families, an information protocol in BSPL and commitments specified as queries over the information base in the style of Cupid, evaluated by a commitment evaluator in the executable models, with and without the evidential layer. These arms replace the hub's hand-encoded commitment arm as the object of comparison, and the hand-encoded arm becomes a cross-check.
3. **Enactment by agents.** The same protocols enacted by language-model agents playing the debtor, creditor and third parties inside DMBench's fault worlds, with the creditor agent's claims judged by the unchanged evaluator. This tests whether enactment adds failure modes the encoded protocols do not have, in particular agents reporting completion they did not perform.
4. **Responsibility and composition.** H1 (retained responsibility removes the accountability gap) and H6 (unchecked composition creates compliance blind spots) restated for commitments, with the composition result as the general form of the compositional-verification problem identified for commitment protocols, and the delegation, replacement and composition families as witnesses.

**What comes from the hub, cited not repeated.** The calculus (§III–IV), the method (§V), the families and fault matrix (§VI), the independent-authorship protocol (§VII). The instance's own results are those of contributions 2 and 3.

**Spine (per the research guideline).** Problem (commitment protocols are judged by commitment state, not by what the creditor can establish) → gap (no evidential semantics; compositional verification lost) → new construct (evidential commitments) → formalization (lifecycle rules, soundness, ceiling) → architecture (BSPL information protocols, Cupid-style queries, evaluator, enactment harness) → example (the delegation family end to end) → implications → limitations → research agenda.

**Figures (eight).** Evidential commitment lifecycle; creditor information base vs truth; BSPL protocol for delegation with its commitments; evaluator architecture with oracle isolation; SFR by family for encoded, Cupid, evidential Cupid and enacted arms; accountability gap under release vs retention; composition determinable mass by observation model; enactment failure taxonomy.

**Citation layers.** Commitments and their semantics; information protocols and BSPL; commitment queries and Cupid; accountability and sociotechnical systems; normative MAS and governance of agents; agent communication languages and semantics; LLM agents and protocol enactment; runtime verification and epistemic logic (from the hub); benchmarking and independent implementation (from the hub).

## 4. New work, as phase 3 steps

**3.1 Commitment evaluator and BSPL protocols.** A module `core/cupid.rkt` in the models: an information base built from an observer's deliveries (each message an information tuple keyed by its protocol's key parameters, duplicates idempotent, order irrelevant, timestamps as asserted); commitments declared per family as debtor, creditor, antecedent query, consequent query and deadlines; lifecycle states computed by the standard rules. Per family, a BSPL protocol in `specs/bspl/<family>.bspl` and a commitment declaration; a sixth arm, `cupid`, in each family. Isolation, totality and brute-force judge tests extended to it.

**3.2 Evidential layer.** A seventh arm, `cupid-e`: the same declarations with E1–E3 applied to discharge and violation, and the evidence sources (attestations, receipts, independent records) declared per family. Ablation and P3 reports between `cupid` and `cupid-e`.

**3.3 Independent authorship of the new arms.** Specifications for the BSPL protocols and commitment declarations before code; independent authors write `cupid` declarations from them; differential check and adjudication as in the hub.

**3.4 Enactment harness.** A driver that runs each family's BSPL protocol with agents: the world fixes conduct and faults as now; agents playing the non-observer roles receive their role's instructions and the messages the world delivers and send BSPL messages; the observer agent receives its deliveries and returns claims in the hub's claim grammar. The evaluator is unchanged. Every run is logged with prompts, responses, seeds and model identifiers; runs are repeated to estimate variance, since agent outputs are sampled. Models per decision M2.

**3.5 Paper.** Produced per the research guideline in the chosen venue's template (decision M4), with every table generated from models v0.4.

**3.6 Workshop version.** An early-results paper (3.1–3.2) for EMAS or COINE 2027 if decision M1 selects route A, submitted with post-proceedings declined where the workshop allows it, so that the journal article remains eligible for the JAAMAS track.

## 5. Acceptance criteria for phase 3

- `cupid` and `cupid-e` exist for all eight families, pass the extended test suite, and agree with independently authored declarations up to documented, adjudicated readings.
- `cupid-e` makes no false claim under any profile, or every false claim it makes is reported with its cause.
- Enactment results report, per family and model, SFR, FCR and coverage with variance across repeated runs, and every enactment-specific failure is classified.
- The paper meets the guideline's definition of done.

## 6. Decisions

| # | Decision | Options | Recommendation |
| --- | --- | --- | --- |
| M1 | Publication route | (a) JAAMAS article as the primary venue, with an early-results workshop paper at EMAS or COINE 2027 (February 2027 deadlines expected) and the AAMAS 2028 JAAMAS track after acceptance; (b) AAMAS 2028 main track (October 2027 deadline); (c) workshop paper only in 2027, then decide | (a). The content needs a full article: four contributions, eight families, an enactment study. JAAMAS has no deadline, its track brings the work to AAMAS anyway, and the workshop gives the community an early look in May 2027 without making the article an extension of an archival conference paper |
| M2 | Models for the enactment study | (a) one frontier model; (b) two models from different providers; (c) two closed models plus one open-weights model | (c). Enactment failures may be model-specific; an open-weights model makes the runs reproducible by reviewers |
| M3 | Co-authorship from the commitment community | (a) none; (b) invite a co-author once 3.1–3.2 results exist; (c) invite now | (b). Results first gives a concrete reason to collaborate and a basis for the co-author's contribution (for example, review of the BSPL and Cupid encodings) |
| M4 | Template | follows M1: Springer Nature journal template for JAAMAS; ACM `acmart` (AAMAS format) for the workshop paper | As stated; the guideline's content and production standards apply in either template (plan decision D2) |

## 7. Sources for §2

- AAMAS 2027 call for main-track papers: https://warwick.ac.uk/fac/sci/dcs/aamas2027/calls/call-for-main-track/
- AAMAS 2026 JAAMAS track call: https://cyprusconferences.org/aamas2026/call-for-papers-jaamas-track/
- EMAS 2026 call (abstracts due 11 February 2026): https://lists.w3.org/Archives/Public/public-webagents/2026Feb/0007.html
