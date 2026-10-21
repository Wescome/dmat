# DMAT executable models (v0.4)

Executable models for Dependency–Mechanism Adequacy Theory and the DMBench protocol, in Racket with each family's terms as a PLT Redex language. v0.3 extends v0.2 from the one handoff family to DMBench's eight scenario families, each with its own fault profiles; makes the arms' protocols drive conduct where the family is about the mechanism, so truth depends on the arm (operational adequacy); varies timing per run (late conduct, transit delay, reordering, clock skew, stale queued messages, interleaved concurrent events); and adds arms written by independent authors from specifications alone, with a differential check against the reference arms.

The method is unchanged: a closed grammar per family; a world module that alone holds oracle truth; arms that see only deliveries; an independent judge that decides determinacy by search over the environment's support; the propositions as searches that produce witnesses.

v0.4 adds the commitment arms of instance I-3 (multiagent systems): a commitment evaluator over the observer's information base in the style of Cupid (`core/cupid.rkt`), an information protocol in BSPL and commitment declarations per family (`specs/bspl/`, `specs/commitments/`), and two arms per family — `cupid`, which reads the information base under the closed-world assumption, and `cupid-e`, which adds the evidential layer E1–E3. The five arms of the hub and every number in WP-2026-DM-01 are unchanged.

Requires Racket 8.10 or later with `redex-lib` (the standard distribution includes it).

```
raco test tests.rkt                          # 43 test cases: families, commitment arms, independent arms, enactment
racket bench.rkt exact                       # exact expected metrics: every world of each profile, weighted
racket bench.rkt sampled 100 results.jsonl   # DMBench: 100 seeds per (family, profile), 18,000 runs, one JSON line each
racket bench.rkt propositions                # P1 witnesses, P2 report, P3 reports
racket diff.rkt                              # reference arms vs independently authored arms
racket diff.rkt detail FAMILY                # every deliveries list on which they disagree, with the truths it can carry
racket commitments.rkt                       # commitment arms: metrics, the evidential-layer ablation, cupid-e against the hybrid
racket diff.rkt cupid > diff-cupid.txt       # reference commitment arms vs independently authored ones
racket enact.rkt check                       # enactment adapters: faithful agents reproduce every coded run
harness/pipeline.sh enactment/requests/test-mock.json OUT   # the enactment pipeline end to end, mock models
```

## Layout

| Path | Holds |
| --- | --- |
| `core/grammar.rkt` | `DMAT0`, the base Redex language every family extends: instants, judgments, claims, the shape of a delivery |
| `core/family.rkt` | The family structure (dependencies, slots, base weights, profiles, canonical map, execution, deliveries); exact supports and probabilities; keyed draws (SHA-256 of family, seed, profile, slot) |
| `core/arm.rkt`, `core/observe.rkt` | The arm descriptor (family, name, protocol, interface, judge) and pure helpers over deliveries — the only core modules an arm may import |
| `core/judge.rkt` | The adequacy judge: oracle truth, deliveries and claims kept apart; determinacy by search; claim classes; metrics |
| `families/<family>/terms.rkt` | The family's Redex language (worlds, views, deliveries) and its timing constants |
| `families/<family>/world.rkt` | Ω and oracle truth for the family: profiles, canonical map, execution of an arm's protocol in a world, deliveries |
| `families/<family>/arms.rkt` | The five reference arms: CHOR, FSM, COMM, HYBRID, HYBRID-NOE |
| `core/cupid.rkt` | The commitment evaluator: facts and coverages of an information base, achievement-commitment lifecycle (discharged, violated, expired, unknown), closed-world or evidential (E1–E3) event status |
| `families/<family>/cupid.rkt` | The two commitment arms, `cupid` and `cupid-e`, with the hybrid's protocol and interface |
| `families.rkt` | Registry of the eight families, their five arms and their two commitment arms |
| `propositions.rkt` | P1 witness search, P2 observation-model report, P3 variant reports, generic over families |
| `bench.rkt` | DMBench driver |
| `specs/commitments/`, `specs/bspl/` | The commitment-arm contract and evaluator semantics (`README.md`), one commitment specification and one BSPL information protocol per family |
| `commitments.rkt` | The commitment-arm report (`commitments.txt`) |
| `core/enact.rkt`, `families/<family>/enact.rkt`, `enact.rkt` | Enactment by language-model agents (`specs/enactment.md`): role specifications, briefings, faithful events, assembly of deliveries from agents' messages and the world's faults, observer prompts, scoring |
| `harness/run.py`, `harness/pipeline.sh` | The model calls (Anthropic, OpenAI, OpenAI-compatible endpoints, mocks) and one request end to end |
| `enactment/` | Run requests, queued requests and committed outputs (`enactment/README.md`) |
| `specs/` | `paradigms.md` (the arm contract and the five paradigms) and one specification per family: what the independent authors worked from; `adjudication.md`, the record of the differential check |
| `independent/<family>-arms.rkt`, `independent/<family>-cupid.rkt` | Arms and commitment arms written by independent authors from `specs/` and the family's `terms.rkt` only |
| `diff.rkt` | The differential check between reference and independent arms |
| `tests.rkt` | The models' tests |
| `paper-tables.rkt`, `paper-heat.rkt` | Write the paper's tables and heat-map figure (`../paper/tables`, `../paper/figures/heat.tex`) from the models |
| `exact.txt`, `sampled.txt`, `propositions.txt`, `diff.txt`, `results.jsonl`, `commitments.txt`, `diff-cupid.txt` | Outputs of the commands above |

## The eight families

Truth is `Fulfilled` when the dependency's success condition holds at evaluation and `Violated` otherwise. Where a family's arms differ in a conduct-affecting protocol feature, the world executes the arm's protocol, so the same world can make a dependency hold for one arm and fail for another.

| Family | Dependencies (kind) | Conduct-affecting protocol feature | Profiles |
| --- | --- | --- | --- |
| `handoff` — hospital H refers to provider V | `flow` (Flow): V accepted by the acceptance deadline; `temporal` (Temporal): care initiated by the deadline | — | reliable, lossy, timing, stale-read, record-lag, evidence-contradiction, adversarial |
| `reservation` — allocator V, holders h1 and h2, one exclusive resource | `sharing` (Sharing): no instant with two effective users; `temporal`: h2 granted by D2 | `regrant`: on release only (CHOR, COMM), on lease expiry (FSM, HYBRID-NOE), on expiry with fencing tokens (HYBRID) | reliable, lossy-release, stale-read, adversarial |
| `agreement` — buyer B, seller S; S may alter terms or revoke concurrently with B's confirmation | `fit` (Fit): nobody bound to terms that do not fit; `mutual` (Flow): both bound or neither | `fit-check` (CHOR none), `bind`: on send (CHOR), on acknowledgement (FSM, COMM), on acknowledgement or a fresh read of S bound (HYBRID, HYBRID-NOE) | reliable, lossy, concurrent-revoke, stale-read, adversarial |
| `delegation` — V delegates to subcontractor S when it lacks capacity | `continuity` (Flow): the obligation never owned by nobody; `temporal`: care by the deadline | `on-delegate`: release (CHOR) or retain until S accepts, reactivated if S declines (others) | reliable, lossy, stale-read, adversarial |
| `deadline` — V owes a service by a deadline, reports completion stamped by its own clock | `temporal`: completed by the deadline in true time; `completion` (Flow): completed at all | — | reliable, transit, clock-skew, adversarial |
| `external` — V performs part A, dispatches part B to an external executor X outside the protocol | `internal` (Flow): A performed; `external` (Flow): B performed in full | — | reliable, external-failure, premature, adversarial |
| `composition` — H ← V ← S across three organizations; H has no protocol with S | `temporal`: S initiated its stage by the deadline; `delivery` (Flow): V delivered | — (observation model of V's case: coarse or staged) | reliable, lossy, self-report, adversarial |
| `replacement` — V may withdraw; replacement V2 accepts or declines; a withdrawn V may emit a stale START | `continuity` (Flow); `temporal` | `on-withdraw`: release (CHOR) or retain until V2 accepts (others) | reliable, ghost, stale-read, adversarial |

### DMBench's fault matrix, as modelled

| DMBench fault | Where it is modelled |
| --- | --- |
| Lost reply | dropped ACCEPT, DELEGATED, START, ATTEST, RECEIPT, DONE, DELIVERED, CONFIRM, ACK, release messages — every family |
| Duplicate command | duplicated ACCEPT (handoff `lossy`, `adversarial`) |
| Stale observation | stale read-backs (handoff, agreement, delegation, reservation, replacement), record lag with a watermark (handoff, external), a stale queued START from a withdrawn party (replacement `ghost`) |
| Concurrent updates | revocation and confirmation crossing, both processing orders (agreement `concurrent-revoke`); two holders using one resource (reservation) |
| Resource exhaustion | V without capacity delegates (delegation) |
| Conflicting acceptance | S accepts with altered terms; confirmation and revocation cross (agreement) |
| Deadline expiry | care, service and stage deadlines (handoff, delegation, deadline, composition, replacement); lease expiry (reservation) |
| Actor disappears | V crashes after accepting (handoff), h1 dies holding the lease (reservation), V withdraws (replacement), S declines (delegation, composition) |
| Evidence contradiction | premature start report (handoff), premature DONE (external), S's premature self-report (composition), clock skew in V's stamps (deadline), the ghost START (replacement) |

Timing now varies per run: late acceptance and slow replies that arrive after the start notice (handoff `timing`), transit delay and clock skew (deadline), late stages (composition, replacement), and interleavings of concurrent events (agreement). Time remains discrete, and each variation is an enumerated world choice, not a continuous delay distribution.

## The arms

The five paradigms are defined in `specs/paradigms.md`. In short: CHOR judges from the observer's session projection, with timeouts as session events and no notion of evidence; FSM takes the counterpart's state record as authoritative; COMM judges commitments as the creditor holds them; HYBRID composes commitments (responsibility retained or assigned, never dropped), state-machine guards and an evidentiary discipline (E1: a participant's report is not evidence of its own performance; E2: a record is authoritative only up to its watermark; E3: abstain otherwise); HYBRID-NOE is the hybrid without E1–E3 — and, in `reservation`, without the fencing tokens.

## The judge

Unchanged from v0.2. For each run the judge holds oracle truth, the arm's deliveries and the arm's claims apart; truth is computed from the arm's own protocol. A dependency is *determined* for an arm in a run when every world of the profile's support that gives the arm the same deliveries has the same truth. Classes: `supported` (definitive, true, determined, cited), `lucky` (definitive and true but not determined, or uncited), `false`, `abstained-ok` (Indeterminate, not determined), `abstained-miss` (Indeterminate though determined). Metrics: SFR (runs with any false claim), FCR (Fulfilled claims that are false or lucky, over Fulfilled claims), AGR (unowned responsibility time over required responsibility time, from the execution), coverage, each class's share, determinability.

## Results

### Exact, `adversarial` profile of each family (every world, weighted)

| Family | CHOR SFR | FSM SFR | COMM SFR | HYBRID SFR / coverage | HYBRID-NOE SFR |
| --- | --- | --- | --- | --- | --- |
| handoff | 0.461 | 0.506 | 0.289 | 0 / 0.539 | 0.199 |
| reservation | 0 | 0.300 | 0 | 0 / 0.500 | 0.233 |
| agreement | 0.297 | 0.047 | 0.047 | 0 / 0.891 | 0.047 |
| delegation | 0.266 | 0.250 | 0.250 | 0 / 0.823 | 0.063 |
| deadline | 0.300 | 0.267 | 0.300 | 0 / 0.733 | 0.067 |
| external | 0.500 | 0.031 | 0.563 | 0 / 0.484 | 0.219 |
| composition | 0.089 | 0.200 | 0.522 | 0 / 0.418 | 0.214 |
| replacement | 0.328 | 0.219 | 0.375 | 0 / 0.827 | 0.106 |

Full tables: `exact.txt` (180 family × profile × arm rows); `sampled.txt` (100 seeds per family and profile; worst SFR deviation from the exact value 2.7 standard errors over 180 cells); `results.jsonl` (every sampled run with its world, deliveries, claims and classification; SHA-256 `b4a82093…c312db`, identical on every run of the same command).

### What the results show

- **No single paradigm is adequate across DMBench, and each is adequate somewhere (A2, H5).** CHOR and COMM are each unsafe in seven of the eight families and FSM in all eight; each is safe on some family/profile pairs: FSM in handoff under reliable delivery but not once replies are lost (its own timeout fires on a dropped ACCEPT) or reads are stale; COMM in reservation under every profile, but in external even under reliable delivery; CHOR in reservation under every profile, but in agreement even under reliable delivery.
- **Operational adequacy and epistemic adequacy separate.** In reservation, CHOR and COMM regrant only on release, so they never overcommit (sharing always holds), but h2 waits past its deadline whenever h1 overruns, dies or its release is lost (temporal fails by the protocol's own conduct); FSM's unfenced expiry regrant meets the deadline but lets an overrunning h1 overlap h2. The hybrid's fenced expiry gives both. In delegation and replacement, releasing the delegator (CHOR) leaves responsibility unowned: AGR 0.25 in both, against 0 for every retaining arm.
- **HYBRID makes no false claim in any family under any profile; its ablation is unsafe in every family.** The evidentiary component carries the safety. P3 (`propositions.txt`) finds the ablation loses safety in every family and, where conduct and observation are unchanged (all families but reservation), never loses observation: the loss is in interpretation. Both facts hold for the independently written arms as well, before any adjudication.
- **False completion follows the evidence model across families.** Self-reports are accepted as performance by whichever single-paradigm arms observe them and by the ablation, and produce false Fulfilled claims in handoff (premature start: FCR 0.467 for CHOR, FSM and COMM under `evidence-contradiction`), external (premature DONE), composition (S's self-report), deadline (V's skewed clock) and replacement (the ghost START, which passes for the debtor's start when V has resumed the role). HYBRID's FCR is 0 throughout.
- **Granularity is part of adequacy.** In external, COMM's single conjunctive commitment for both parts makes it claim the external part violated whenever the internal part is, and is false whenever X completed B: SFR 0.25 under reliable delivery. The independent author's reading (one commitment per part, with nothing H holds able to discharge B's) is false on every run where X completes B.
- **Timing faults break arms that judge by arrival or by a party's clock.** In deadline, CHOR and COMM (judging by DONE's arrival) are false under transit delay (SFR 0.30); FSM (judging by V's stamp) is safe under transit delay and false under clock skew (0.27); the hybrid uses the trusted stamp. In handoff, a slow but timely acceptance takes CHOR's and FSM's timeout branch (SFR 0.30 under `timing`).
- **P1 witnesses exist wherever faults hide state**, in every family but deadline: there every fault leaves a distinct trace, and the difficulty is interpretation, not observation.
- **P2, sharpened: decidability needs distinguishable *evidence*, not just a finer report.** In composition, under the coarse model H's dependency on S is never determined (mass 0); under the staged model it is determined with honest reporting (mass 1) but only 0.25 when S may report prematurely; with an attestation of S's start, 1.0 again.

## Commitment arms (v0.4)

Each family's commitments are declared as queries over the observer's information base (`specs/commitments/<family>.md`, with the information protocol in `specs/bspl/<family>.bspl`) and evaluated by `core/cupid.rkt`. `cupid` reads the information base under the closed-world assumption, as commitment queries over a database do; `cupid-e` applies E1 (a debtor's report of its own performance is not evidence of it), E2 (absence only from a record complete through the deadline that does not itself report the event) and E3 (otherwise unknown). Both use the hybrid's protocol and interface, so they see the same deliveries in every world. From `commitments.txt`:

| family | worst-profile SFR: hybrid | cupid | cupid-e | mean coverage: hybrid | cupid-e |
| --- | ---: | ---: | ---: | ---: | ---: |
| handoff | 0 | 0.267 | 0 | 0.840 | 0.840 |
| reservation | 0 | 0.567 | 0 | 0.750 | 0.750 |
| agreement | 0 | 0.250 | 0 | 0.953 | 0.953 |
| delegation | 0 | 0.063 | 0 | 0.935 | 0.935 |
| deadline | 0 | 0.117 | 0 | 0.933 | 0.842 |
| external | 0 | 0.508 | 0 | 0.590 | 0.590 |
| composition | 0 | 0.281 | 0 | 0.566 | 0.566 |
| replacement | 0 | 0.082 | 0 | 0.936 | 0.937 |

- **The evidential layer is what makes commitment judgment sound.** `cupid-e` makes no false claim under any profile of any family; `cupid` is unsafe in every family. P3 between them loses no observation anywhere: the whole loss is in judgment.
- **Evidential commitments recover the hybrid.** `cupid-e` decides exactly what the hub's hybrid decides except on two documented runs: deadline completion, where the commitment's deadline is the evaluation instant and V's record is complete only through the read, so E2 abstains where the hybrid uses the family's schedule; and replacement temporal, where V's own report of a late resumption is an admission under E1 and `cupid-e` decides where the hybrid abstains.
- **Independent authorship.** The commitment arms were written a second time from the specifications alone. The first comparison disagreed on no deliveries list. The author found one specification error (a ghost START admitted by the replacement responsibility rule under the closed-world reading), now amended in the specification and the reference, leaving a pinned residue of 9 lists; `specs/commitments/adjudication.md` records it.

## Enactment (phase 3, step 3.4)

The information protocols can be enacted by language-model agents (`specs/enactment.md`). The world still draws conduct and faults per seed; party agents are briefed with their own conduct and choose the protocol messages they send; their messages pass through the world's channel and system faults into the observer's deliveries; an observer agent judges under three instruction conditions (role only; with commitments; with commitments and E1–E3); the coded `cupid-e` and `cupid` judge the same deliveries. Agents never see the truth. Assembly is checked against the coded models: in every world of every family, agents that send the faithful events produce exactly the coded deliveries and truth. The analysis plan, with hypotheses fixed before any model run, is `../docs/enactment-analysis-plan.md`; runs are requested and their outputs committed through `enactment/`.

## Independent authorship

The five arms of each family were rewritten by independent authors, each given only `specs/paradigms.md` §1–§4, `specs/<family>.md`, the core arm, observe and grammar modules and the family's `terms.rkt`, in a workspace without the reference arms, the world modules or v0.2. `diff.rkt` compares the two sets of judges on every distinct deliveries list any profile can produce (1,309 lists over the 40 family × arm pairs).

The first comparison disagreed on 310 lists. `specs/adjudication.md` traces each to a cause and decides it by one rule — the written specification is the contract. Twelve causes were reference departures from the specification and were corrected in the reference (among them: CHOR timeouts as violations, arrival-based bounds, E1 applied to a party's own records, continuity judged from the commitment structure, the ablation keeping the commitment rule, responsibility by instant for the ghost). Eight were admissible alternative readings the specification left open; the reference reading was kept, the specification was clarified in a dated section, and the residue is reported: 33 lists, pinned by `tests.rkt`. No independent arm was edited. `diff.txt` has the per-profile metric differences that remain.

## Validity notes

- **Independence is partial.** The independent authors are instances of the same model family as the reference author, working from specifications the reference author wrote. They did not see the reference arms or the world, so the check catches judgment errors and spec-to-code slips — it found twelve in the reference — and agreement shows the specification determines the arms up to eight documented choices; it does not give the diversity of separate human teams. DMBench's validity rule (independent authors, equal infrastructure) is met in form and only partly in substance.
- **Single-paradigm results are sensitive to the documented readings.** Under the independent readings the per-cell SFR of CHOR, FSM and COMM moves in the cells `diff.txt` lists (for example agreement CHOR under `reliable`: 0.25 by type-level conformance, 0 by payload checking). The cross-family conclusions above hold under both sets of arms.
- **Determinacy is relative to the modelled support.** An `abstained-miss` can be (a) a guarantee by construction that the mechanism declines to claim without run evidence — in reservation the hybrid's fenced expiry makes both dependencies hold in every world, so a failed read leaves them determined (abstained-miss 0.500 under adversarial), and A5 (evidence soundness) is why the hybrid still abstains; or (b) an inference that holds only because the world space is narrower than the paradigm assumes — in composition `lossy`, the absence of an attestation implies S never started only because that profile never drops attestations. A third source is a view without a completeness watermark: composition's case record has none, so E2 keeps the hybrid from reading `open` at T-READ (after T-DELIVER) as a missing delivery, and most of its abstained-miss there (0.411 under `lossy`) is that. A watermark on the case view would remove it; it is a property of the modelled interface, not of the hybrid.
- **Profiles are built per family.** Each family's profiles admit the faults its scenario is about, so metrics compare arms within a family and profile; averages across families would weight families by the arbitrary number of profiles each has.
- **Time is discrete and enumerated.** Delays, skews and orders are world choices with fixed instants. Concurrency is modelled as interleaving choices where a family has concurrent independent events (agreement), not as a general interleaving semantics over all participants.
- **Duplicate commands are modelled as duplicated messages only.** A duplicate that causes a second execution (the idempotency fault) is not in any family.
- **The handoff family's results changed from v0.2** because its profiles now include timing variation (`timing`: late acceptance, slow replies reordered after the start notice) and the adversarial profile admits them.

## Changes from v0.2

| v0.2 limit | v0.3 |
| --- | --- |
| Only the handoff family | DMBench's eight families, each a closed Redex language extending `DMAT0`, with its own world and arms |
| All arms by one author | Independent arms from specifications alone, and a differential check over every reachable deliveries list |
| Time abstract and fixed; no reordering or concurrency | Late conduct, transit delay, reordering, clock skew, stale queued messages, interleaved concurrent events, each as world choices |
| Five DMBench fault profiles missing | DMBench's nine faults mapped to families and profiles (table above) |
| Conduct exogenous to the arm | Protocol features the world executes (regrant, binding, delegation and withdrawal rules), so truth depends on the arm where the family is about the mechanism |
