# Adjudication of the differential check (2026-10-21)

The reference arms (`families/<family>/arms.rkt`) were compared with the independently authored arms (`independent/<family>-arms.rkt`) on every distinct deliveries list any profile of any family can produce: 1,309 lists over the 40 family × arm pairs. Judges depend only on deliveries, so a list on which two judges agree is agreement on every world that produces it.

The first comparison found disagreements on **310** of the 1,309 lists. Each was traced to a cause and decided by one rule: **`paradigms.md` and the family specification are the contract.** Where the independent reading follows the written specification and the reference departs from it, the reference was amended. Where the specification leaves the question open and both readings are admissible paradigm practice, the reference reading was kept, the specification was clarified (`paradigms.md` §5 and the family specs' clarification notes, added after the check, original text unchanged), and the residue is reported. No independent arm was edited.

After adjudication **33** lists disagree, all of them in the admissible-alternative class below. `tests.rkt` pins that residue exactly.

## Amendments to the reference (the independent reading follows the specification)

| # | Family / arm | Cause | Reference before | Amended to |
| --- | --- | --- | --- | --- |
| A1 | handoff, deadline, delegation, reservation, replacement, external, composition / CHOR | Timed branches fire on arrival and the session records the partner's failure (`paradigms.md` §3 CHOR) | Absence never evidence; never Violated; handoff judged by asserted instants | Timeout branch ⇒ the awaited dependency Violated; arrival-based bounds |
| A2 | handoff / FSM | V's state record carries no instants and cannot decide the acceptance deadline; H's own-clock timeout does | Flow Fulfilled from state `accepted` (false on late acceptance) | Flow from H's machine: ACCEPT arrived by the deadline, else overdue |
| A3 | all families / HYBRID-NOE | Removing E3 leaves the commitment semantics the hybrid is built on: a commitment the creditor has not seen discharged by its deadline is violated | Abstained where the hybrid abstains | Commitment rule applies where the hybrid would abstain; a successful read is authoritative over messages |
| A4 | agreement / CHOR, FSM, COMM, HYBRID, HYBRID-NOE | S's ACK (the act that creates the binding), S's REVOKE and B's own REJECT settle S's binding; a received final message precedes a counterpart record | Stale record read as current over a received ACK; no-read cases guessed or abstained | S's binding from messages first, then the record (the hybrid: an authoritative record) |
| A5 | delegation, replacement / COMM, HYBRID, HYBRID-NOE | Continuity is a property of the commitment structure: retained or assigned, never released; not a report of performance (E1 does not apply) | Abstained without an authoritative record | Fulfilled citing the creating ACCEPT, unless a record shows the commitment released / the role vacant |
| A6 | replacement / CHOR | Under release, a withdrawal opens a vacancy until T-V2 by the protocol's own conduct | Abstained | WITHDRAW ⇒ continuity Violated |
| A7 | replacement / CHOR, COMM, HYBRID, HYBRID-NOE | A START counts only from the party responsible at its instant (the session's current branch; the commitment's debtor) | Any START counted (the ghost passed everywhere) | Responsibility by instant; a withdrawn V counts only if it still holds the role or resumes |
| A8 | replacement / FSM, HYBRID | Care started by V after its withdrawal is the resume transition, which fires after the deadline | Fulfilled (FSM, false) / abstained (HYBRID) | Violated |
| A9 | external, composition, reservation / HYBRID | E1 applies to records: V's `done`, V's closed case and V's GRANT entry are V's reports of its own performance | Accepted as evidence | Positive claims need X's receipt, H's own receipt (DELIVERED), or the resource's USE/REJECT entries; V's records establish only negatives, and only within a watermark |
| A10 | composition / HYBRID | E2 with no watermark: the case record proves only what it contains | `committed` read as a negative | Indeterminate; S's report of declining or of a start after the deadline is a negative S itself admits (E1) |
| A11 | reservation / HYBRID | Fencing tokens are checked by the resource, an independent party: a stale access log cannot hide an overlap | Abstained on stale logs | Sharing Fulfilled unless the resource's uses overlap |
| A12 | reservation / HYBRID-NOE | A release recorded after h2's grant shows h1 held past it | Fulfilled (false) | Violated |

## Admissible alternative readings (reference kept; specification clarified; residue reported)

| # | Family / arm | Lists | Reference reading (kept) | Independent reading | Clarification |
| --- | --- | --- | --- | --- | --- |
| K1 | agreement / CHOR | 9 | Messages are checked by type, not payload value (no refinement types): a conforming trace is fit Fulfilled even when S's terms were altered | The ACCEPT payload is in H's session: confirming altered terms is fit Violated | `paradigms.md` §5: CHOR checks types, not values |
| K2 | composition / FSM | 3 | V's case `closed` implies the subcontract stage completed within its guard: temporal Fulfilled | The coarse record holds nothing about S: Indeterminate | — (both are state mappings) |
| K3 | composition / COMM | 5 | The creditor has not seen the stage commitment discharged by the deadline: Violated | No ledger entry for S's stage: Indeterminate | `paradigms.md` §5: the creditor rule applies to commitments the creditor holds, including retained ones |
| K4 | delegation / CHOR | 2 | No DELEGATED and no read: Indeterminate (a dropped DELEGATED is possible) | No delegation in the session: V held the role: Fulfilled | — |
| K5 | delegation / FSM | 6 | States `delegated` and `sub-started` keep V responsible by the retaining guard: Fulfilled | FSM has no cross-party obligations: Indeterminate | — |
| K6 | external / CHOR, COMM, HYBRID-NOE | 7 | DONE is V's report that the order is complete: both parts | The spec's sending condition names only part A, so DONE is about A | `external.md`: DONE reports the order complete |
| K7 | (part of K6) external / COMM | — | One conjunctive commitment for both parts, discharged by DONE | Two commitments; nothing H holds discharges B: external always Violated (SFR 1.0 under `reliable`) | — |
| K8 | deadline / CHOR | 1 | No DONE and no log: the wait for DONE timed out (A1) | Completion outside H's projection: Indeterminate | — |

K7's lists are counted under K6 (external COMM: 3).

## What the independent arms confirm without adjudication

These hold for the independent arms as written, before any change to the reference:

- The independent HYBRID makes no false claim in any family under any profile.
- The independent HYBRID-NOE is unsafe in every family.
- Every independent single-paradigm arm is unsafe somewhere, and no paradigm is safe in every family.

## Independence

The independent authors were separate agent instances of the same model family as the reference author, each in a workspace holding only `specs/paradigms.md`, its family's spec, the core arm/observe/grammar modules and the family's `terms.rkt`, with instructions not to read anything else. They did not see the reference arms, the world modules or v0.2. Agreement after adjudication shows that the specification determines the arms up to the eight documented choices; it does not provide the diversity of separate human teams.
