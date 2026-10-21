# Commitment arms — contract, evaluator and evidential layer

This directory specifies the two commitment arms of each DMBench family, `cupid` and `cupid-e` (phase 3 of the plan, instance I-3: multiagent systems). Read `../paradigms.md` §1–§2 for the setting, the deliveries and the claim grammar, and the family's own spec (`../<family>.md`) for its scenario, constants, fault model and deliveries. Each family's commitment spec (`<family>.md` here) and its information protocol (`../bspl/<family>.bspl`) then say what to declare. Together these documents are sufficient to write the arms; no other file is assumed.

## 1. What a commitment arm is

A commitment arm judges a family's dependencies by evaluating **commitments over the observer's information base**, in the style of Cupid: the observer's information is a set of events, and a commitment's lifecycle state is a query over it. The arm does three things:

1. builds an information base from its deliveries alone: **facts** (events the information reports) and **coverages** (records known complete through an instant);
2. declares the family's commitments and evaluates each with the shared evaluator `core/cupid.rkt`;
3. maps commitment states (and the family's declared side rules) to dependency judgments, citing the deliveries the state rests on.

The two arms differ in one thing only: `cupid` evaluates with `#:evidential? #f` (closed-world reading), `cupid-e` with `#:evidential? #t` (rules E1–E3). Same protocol, same interface, same declarations, same side rules unless the family spec says a rule depends on the layer. The pair is therefore an exact ablation of the evidential layer.

Both arms use the protocol and interface of the family's `hybrid` arm (family spec, "Arms" table).

## 2. The evaluator (`core/cupid.rkt`)

    (struct fact (event source kind time attrs index))
    (struct coverage (party through events index))
    (struct commitment (name debtor creditor antecedent a-deadline consequent c-deadline))

- `fact` — `event`: a symbol naming the event; `source`: the party the information comes from; `kind`: `'act` (constitutive — an acceptance, a grant, a binding, a refusal: a party's own act is evidence of itself) or `'performance` (a report that something was done); `time`: the instant asserted for the event; `attrs`: a list of attributes; `index`: the delivery the fact comes from (an index into the deliveries, or `#f` for the observer's own knowledge).
- `coverage` — a record from `party`, complete through instant `through` for the event kinds in `events`, read in delivery `index`.
- `commitment` — `antecedent` and `consequent` are predicates `fact → boolean`, or `'true` for an antecedent that holds from the start; deadlines are instants.

    (commitment-state c facts coverages #:evidential? ev #:a-kinds ak #:c-kinds ck [#:debtor-clock? #t])
      → (values state cites)

`state` is one of `discharged` (consequent held by its deadline), `violated` (antecedent held, consequent not held by its deadline; a late discharge does not cure), `expired` (antecedent not held by its deadline, consequent not held), `unknown`. `ak`, `ck`: the event kinds the antecedent and consequent refer to, used to select coverages. `cites`: the delivery indices the state rests on.

Event status (held, late, absent, unknown) is computed per condition:

- **closed world** (`cupid`): a matching fact by the deadline → held; a matching fact after it → late; otherwise absent. What is not in the information base did not happen.
- **evidential** (`cupid-e`):
  - **E1** a performance fact whose source is the commitment's debtor is not evidence that the performance happened. It can still establish that the debtor *admits* a late performance, unless the family declares the debtor's time stamps unreliable (`#:debtor-clock? #f`).
  - **E2** absence is established only by a coverage that includes the event kind, is complete through the deadline, and does not itself report the event.
  - **E3** otherwise the status is unknown.

  For the antecedent the E1 "debtor" is the commitment's creditor (the antecedent is normally the creditor's act).

Helpers: `(state->judgment st #:expired j)` maps `discharged → Fulfilled`, `violated → Violated`, `expired → j` (default `Indeterminate`; the family spec says what an expired commitment means for its dependency), `unknown → Indeterminate`. `(dep-claim dep j cites)` builds a claim entry for `claims` (abstentions cite nothing).

## 3. Arm contract

A commitment arm module is `families/<family>/cupid.rkt`-shaped: it provides `cupid-arms`, a list of two `arm` structures named `cupid` and `cupid-e`, in that order, with the family symbol, protocol and interface of the family's `hybrid` arm. It may import only `core/arm.rkt`, `core/observe.rkt`, `core/grammar.rkt`, `core/cupid.rkt`, the family's `terms.rkt`, and Racket standard libraries. An independently authored version goes in `independent/<family>-cupid.rkt` under the same contract.

The claims list has one entry per dependency, in the family's order.

Citations. A closed-world absence rests on nothing the observer holds when no coverage applies; `cupid` then makes a definitive claim with no citation. That is the closed-world reading, not an omission: the judge classifies such a claim as lucky when it is true and false when it is not, never as supported. (Clarification after the differential check, 2026-10-21.)

## 4. What the family specs declare

For each family:

- **Information protocol** — the BSPL protocol in `../bspl/<family>.bspl`: roles, messages, parameters, and the record read-back modelled as a query and its answer. It fixes which information exists, not how the arm reads it.
- **Information base** — for each delivery form, the facts and coverages it yields: event, source, kind, time, attributes.
- **Commitments** — debtor, creditor, antecedent and deadline, consequent and deadline, and the event kinds each refers to.
- **Judgments** — how each dependency's judgment follows from commitment states, and any side rule the protocol itself fixes (for example: a party's refusal settles that a binding did not occur). Side rules are the same in both arms unless stated.
- **Declarations for the evidential layer** — `#:debtor-clock?` where a debtor's stamps are unreliable; deadlines that are the protocol's schedule rather than the dependency's evaluation instant.

## 5. Where the evidential layer is expected to cost coverage

`cupid-e` should make no false claim under any profile of any family. Where it abstains while the hub's `hybrid` arm decides, the cause is reported in `../../commitments.txt` (generated by `commitments.rkt`); the known case is the `deadline` family's completion dependency (§ in `deadline.md`).
