# DMBench arms — paradigm definitions and the arm contract

This document is shared by the eight family specifications in this directory. It defines what an *arm* is, what an arm may observe, what it must return, and the five coordination paradigms an arm is written in. It is self-contained; it does not assume any other file except the core Racket modules named below.

## 1. Setting

DMAT (Dependency–Mechanism Adequacy Theory) asks whether a coordination mechanism lets a participant decide whether a dependency between parties held. A *dependency* has a kind — Flow (something passes from one party to another, with responsibility), Sharing (a resource used by several parties under an exclusivity constraint), Fit (what one party produces satisfies what another requires), Temporal (an event happens by a deadline). For each run, a dependency is in fact either **Fulfilled** or **Violated**. That truth is computed by an oracle the arm never sees.

An arm is the mechanism's *judge*: given only what the observing participant receives during a run (its *deliveries*), it returns, for each dependency of the family, a judgment

    J ∈ { Fulfilled, Violated, Pending, Indeterminate }

with the indices of the deliveries it relies on. `Fulfilled`, `Violated` and `Pending` are definitive; `Indeterminate` is an abstention. A definitive judgment that differs from the truth is a **false claim**. The benchmark rewards arms that never make false claims and that abstain only when their deliveries do not determine the truth.

## 2. The arm contract (Racket)

An arm module is `families/<family>/arms.rkt`-shaped: it provides `arms`, a list of five `arm` structures, in this order of names: `chor`, `fsm`, `comm`, `hybrid`, `hybrid-noe`.

    (struct arm (family name protocol interface judge))   ; core/arm.rkt

- `family` — the family's symbol, as given in the family spec.
- `name` — one of the five names.
- `protocol` — a `hasheq` of conduct-affecting protocol features. The family spec fixes these per arm; use exactly the values given (they change how participants act, and so change the truth).
- `interface` — a `hasheq` saying what the protocol makes observable (which optional messages exist, which read-back view kind). The family spec fixes these per arm; use exactly the values given.
- `judge` — a procedure `deliveries → claims`.

The judge sees only its argument. It must not import anything except:

- `core/arm.rkt` — the struct above;
- `core/observe.rkt` — helpers over deliveries (below);
- the family's `terms.rkt` — the family's grammar and its timing constants;
- Racket standard libraries.

### Deliveries

Deliveries are a list in arrival order. Each element is one of

    (msg M arrival asserted payload ...)   ; a message of kind M; arrival instant at the observer;
                                           ; the instant its sender asserts for it (the event it
                                           ; reports, or the sender's clock); payload
    (read-ok t view)                       ; a read-back of a participant's record at t, returning view
    (read-failed t)                        ; a read-back at t that returned nothing

All instants are natural numbers on one global time line unless the family spec says a sender's clock may be wrong.

### Helpers (`core/observe.rkt`)

- `(msg-indices ds M #:asserted-by T #:arrived-by T #:where pred)` → indices of messages of kind `M` whose asserted instant ≤ `#:asserted-by`, arrival ≤ `#:arrived-by`, and satisfying `pred` (each optional).
- `(msg-arrival d)`, `(msg-asserted d)`, `(msg-payload d)` → arrival, asserted instant, payload list of a message.
- `(read-index ds)` → index of the `read-ok` delivery, or `#f`; `(read-view ds)` → its view, or `#f`.
- `(claims (list dep J cites) ...)` → a claims term. Entries must be given for every dependency of the family, **in the family's dependency order**. `cites` is a list of delivery indices; a definitive claim should cite at least one delivery that supports it.

## 3. Paradigms

Each arm is a mechanism written in one paradigm. The judge is that mechanism's own account of whether each dependency held — what a participant running that mechanism would conclude. Write each judge as a faithful practitioner of the paradigm would: neither handicap it nor give it inferences the paradigm does not make.

### CHOR — choreographies / multiparty session types

A global type describes the interaction; each participant runs its projection. The observer's knowledge is its local session: the messages of its projection, in order, and (where the interface defines one) a read-back of the counterpart's session log, typically its last message. Timeouts are protocol events of the session (a timed branch fires when the awaited message has not *arrived* by the bound). The paradigm has no notion of a party's internal state beyond what the session says, no notion of obligation surviving a session's end, and no notion of evidence versus report: a message is the event it names. Judgments about facts outside the observer's projection are `Indeterminate`.

### FSM — protocol state machines

Each participant runs a finite state machine with guarded transitions (including timeouts on its own clock). The observer reads the counterpart's current state from its record; the state record is authoritative — the machine *is* in the state it records. Judgment maps states to dependency outcomes. The paradigm trusts the record as current when read and has no notion of a record's staleness or completeness, and none of obligations across parties.

### COMM — commitment-based protocols

Interactions create and manipulate commitments `C(debtor, creditor, antecedent, consequent)` with the lifecycle conditional → detached (antecedent holds) → discharged (consequent holds) | violated (deadline passes undischarged) | released | cancelled | delegated/assigned (debtor changes) | pending (suspended while a delegated commitment is active). Messages are social events that change commitment states as the creditor holds them. Judgment is the commitment's state from the creditor's point of view: a commitment the creditor cannot see discharged by its deadline is violated. Read-backs return the counterpart's commitment ledger where the interface defines one.

### HYBRID — commitments with state-machine guards and an evidentiary discipline

The hybrid composes COMM's commitments (responsibility is retained or assigned explicitly, never dropped), FSM guards and records, and three evidentiary rules:

- **E1 — reports are not evidence of performance.** A participant's own message or record entry asserting that it performed is not evidence that it performed. A `Fulfilled` claim about performance requires independent evidence: an attestation or receipt from a party other than the performer, a third party's record, or a trusted clock's stamp. (A participant's report *not* to have performed, or its record *not* showing performance when complete, may establish a negative.)
- **E2 — records are authoritative only up to their watermark.** A record read-back is authoritative for an event only if its completeness watermark (the instant through which it is complete, given in the view where the interface defines one) is at or after the instant by which that event would have been recorded. Otherwise the record proves only what it contains, not what it omits.
- **E3 — abstain otherwise.** Where E1–E2 leave the truth open, the judgment is `Indeterminate`.

### HYBRID-NOE — the hybrid without its evidentiary component (ablation)

The same mechanism, protocol features and interface as HYBRID unless the family spec says otherwise, with E1–E3 removed: participants' reports count as evidence of what they report, and every successful read-back is authoritative.

## 4. What to deliver

For one family: a Racket module `independent/<family>-arms.rkt` (`#lang racket/base`) that requires only the modules allowed in §2 (paths relative to the module: `"../core/arm.rkt"`, `"../core/observe.rkt"`, `"../families/<family>/terms.rkt"`) and provides `arms`. Each judge must be total: it must return a claims term for every deliveries list the family can produce. Above each judge, a comment states the paradigm's reading of the family in domain terms: what the mechanism is, what the observer holds, and why each judgment follows.

## 5. Clarifications added after the differential check

The independent arms were written from §1–§4 as they stand above. The differential check (`specs/adjudication.md`) found the points below underdetermined or easy to misread; they are stated here as the benchmark's reading, and the reference arms follow them.

- **CHOR.** A timed branch fires on *arrival* at the observer. When the branch for a missing or late message fires, the session records the partner's failure: the dependency that message would have constituted is `Violated`. Messages are checked by type, not by payload value (no refinement types): a trace that conforms to the global type conforms whatever its values. A message from a party outside the current branch of the observer's projection (for example, a party whose session has ended) is not part of the session.
- **FSM.** The observer's own machine, with timeouts on its own clock, decides what its received messages constitute. A message the observer received that moves the counterpart to a final state takes precedence over a counterpart record. A state record carries no instants, so it cannot decide a deadline.
- **COMM.** The creditor rule applies to every commitment the creditor holds, including one retained by a delegator or assigned to a replacement: not seen discharged by its deadline is violated. A conditional commitment that never detached yields no judgment.
- **HYBRID.** E1 applies to messages and to record entries alike: a party's record of its own performance is a report. Continuity of responsibility is a property of the commitment structure (retained or assigned, never released), not a report of performance: it is judged from the protocol's commitments and from records that show them released. Guarantees checked by an independent party (fencing tokens checked by the resource) are evidence.
- **HYBRID-NOE.** Removing E3 does not remove the commitment semantics: where the hybrid would abstain, the creditor rule applies. With E2 removed, a successful read is authoritative, including over messages.
