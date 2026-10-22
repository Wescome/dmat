# Enactment of the information protocols by language-model agents

Phase 3, step 3.4 (instance I-3). This specification defines how DMBench's eight families are run with language-model agents playing the protocol roles, what is held fixed, what the agents produce, and how runs are scored. It assumes `paradigms.md`, the family specifications, `commitments/README.md` and the BSPL protocols in `bspl/`. The analysis plan, with the hypotheses fixed before any run, is `../../docs/enactment-analysis-plan.md`.

## 1. Principle

The world model remains the referee. For each run a world is drawn from a seed exactly as in the sampled benchmark (`core/family.rkt`, keyed draw). The world fixes every party's **conduct** (what it did and when) and every **fault** (loss, delay, duplication, stale or lagging records, clock skew, premature or stale reports emitted by a party's systems). The agents replace only the **messages**: a party agent decides which protocol messages it sends, with which instants and parameters; an observer agent decides the claims. The oracle truth is never shown to any agent.

All runs use the protocol and interface of the family's `hybrid` arm (the arm pair `cupid`/`cupid-e` uses the same), so the coded reference judges apply to every enacted run.

## 2. Roles

Each family's non-observer roles are played by **party agents**; the observer role is played by an **observer agent**. The observer's own acts that the world fixes (B's CONFIRM or REJECT in `agreement`) remain the world's.

| family | observer | party agents |
| --- | --- | --- |
| handoff | H | V (provider), A (attester) |
| reservation | auditor U | V (allocator), R (resource) |
| agreement | B | S (seller) |
| delegation | H | V (provider), S (subcontractor), A (attester) |
| deadline | H | V (provider), A (attester) |
| external | H | V (provider), X (external executor) |
| composition | H | V (provider), S (subcontractor), A (attester) |
| replacement | H | V (provider), V2 (replacement), A (attester) |

## 3. Party agents

A party agent receives:

1. the scenario and the family's BSPL protocol;
2. its role and the messages it may send, each with its fields (§6 lists them per family; the adapters in `families/<family>/enact.rkt` hold the exact schemas);
3. a **briefing**: the facts of its own conduct in this run, stated as what happened and when (for example: "You accepted the referral at instant 1. You did not initiate care."). The briefing states only the role's own conduct and what the role has received under the protocol; it never states faults the role cannot know (a message lost in transit, a record's lag) and never states truths about other parties beyond what the protocol tells the role.

It returns a JSON object `{"events": [{"message": M, "at": t, ...fields}]}`: every message it sends, each with the instant asserted for it. An agent instructed to follow the protocol and report its own conduct faithfully produces the **faithful events**; the adapters compute these for every world, and a faithful agent's run is identical to the coded run (§5).

## 4. Assembly: from events to deliveries

The adapter of each family assembles the observer's deliveries from the party agents' events and the world:

- **channel faults** — each message kind's fate (delivered, dropped, duplicated) and transit delay are the world's slots for that kind; the arrival instant is the asserted instant plus the kind's transit delay. A message the world never planned (one the role's conduct does not call for) travels on a reliable channel with the kind's nominal delay;
- **system faults** — reporting faults the world attributes to a party's systems rather than to the party's decision are applied to the agent's stream: a premature start report (handoff, external, composition), a crash after acceptance (handoff: nothing the provider sends after accepting is transmitted), a stale queued START (replacement's ghost). They are applied whatever the agent sent: a premature report replaces or adds the report the world fixes. The provider's clock skew (deadline) is a property of its knowledge: the provider is briefed in its own clock, stamps DONE with it, and the message leaves at the true instant;
- **records** — a read-back of a party's system of record is the world's, with the world's read fault (fresh, stale, lag, unavailable). Records hold conduct. Where the family's record holds a party's *reports* (handoff: V's reported start; composition: S's reported stage), the record holds what the party agent reported, after system faults;
- **order** — deliveries are ordered by arrival instant, ties in the family's declaration order.

Events that do not parse, name a message the role cannot send, carry an instant outside [0, T-EVAL] or a field value outside its domain are discarded and counted as malformed.

## 5. Truth

The truth of each dependency is the world's, computed from conduct, with one exception: in `agreement`, B's binding is B's state on receiving S's acknowledgement, so B's binding (and with it `fit` and `mutual`) is recomputed from the enacted deliveries: B is bound if an ACK is delivered, or if the read is fresh and S is bound. Everywhere else a party's messages report or announce its conduct and do not change it.

Correctness of assembly is a test: for every world of every profile of every family, assembling the faithful events yields exactly the coded deliveries of the `hybrid` arm, and the enacted truth equals the coded truth.

## 6. Messages per family

Each event has `message` and `at` (an instant) and the listed fields. `report` marks a party's report of a performance; `act` marks a constitutive act.

- **handoff** — V: `Accept` (act), `Start` (report). A: `Attest` (report).
- **reservation** — V: `Grant` (report; field `holder` ∈ {h1, h2}), `ReleaseReceived` (act), `Expire` (act). R: `Use` (report; `holder`, `from`, `to`), `Reject` (act; `holder`). These are entries in V's allocation log and R's access log; the auditor reads both through the log read-back.
- **agreement** — S: `Accept` (act; `terms` ∈ {as-proposed, altered}), `Revoke` (act), `Ack` (act).
- **delegation** — V: `Accept` (act), `Delegated` (act), `Start` (report). S: `Start` (report). A: `Attest` (report).
- **deadline** — V: `Done` (report). A: `Attest` (report).
- **external** — V: `Done` (report). X: `Receipt` (report; `outcome` ∈ {complete, partial}).
- **composition** — S: `Decline` (act), `Report` (report; its instant is the start S reports to V). V: `Delivered` (act). A: `Attest` (report).
- **replacement** — V: `Accept` (act), `Withdraw` (act), `Start` (report). V2: `Start` (report). A: `Attest` (report; `performer` ∈ {V, V2}).

## 7. Observer agents

The observer agent receives the scenario, the dependencies to judge, its deliveries rendered as an indexed list (index, arrival instant, kind, asserted instant, payload; a record read-back with its view), and the output format. It returns `{"claims": [{"dependency": d, "judgment": J, "cites": [i, ...]}]}` with `J ∈ {Fulfilled, Violated, Indeterminate}`, one entry per dependency.

Three instruction conditions, each run on the same deliveries:

| condition | adds to the base prompt |
| --- | --- |
| `role` | nothing: the role, the scenario and the dependencies |
| `commitments` | the family's commitments: debtor, creditor, antecedent, consequent, deadlines, and how each dependency follows from them |
| `evidential` | the commitments and the evidential rules E1–E3 with the family's evidence classification (which messages are acts, which are whose reports of performance, which records are complete through which instant) |

An output that does not parse, omits a dependency, or names an unknown judgment yields Indeterminate for the affected dependencies and is counted as malformed.

## 8. Scoring

For each enacted run the scorer computes the truth (§5) and classifies three sets of claims on the enacted deliveries: the coded `cupid-e` and `cupid` judges (references) and the observer agent's claims under each condition.

- When the enacted deliveries equal the coded deliveries of some world in the profile's support, determinacy is the coded judge's (search over the support) and claims take the full classes: supported, lucky, false, abstained-ok, abstained-miss.
- Otherwise (the party agents produced a delivery list the coded world never produces) determinacy is undefined; claims are classified as correct, false or abstained.

Per (family, profile, model, condition), with variance across repetitions: SFR (runs with a false claim), FCR (false or unsupported Fulfilled), coverage (definitive claims), and the class distribution.

## 9. Failure classification

Party events are compared with the faithful events of the run:

| class | definition |
| --- | --- |
| fabricated report | a `report` event with no faithful counterpart (a performance the role did not perform, or did not perform at that instant) |
| fabricated act | an `act` event with no faithful counterpart |
| omitted message | a faithful event with no counterpart |
| parameter error | an event matching a faithful one in message and instant, differing in a field |
| malformed | §4 |

Observer claims are classified per dependency: false claim; definitive where the deliveries do not determine the truth (lucky or false with determinacy defined); abstention where they do (abstained-miss); bad citation (a definitive claim citing nothing or an index outside the deliveries); malformed.

## 10. Runs

Each run request is a JSON file (`models/enactment/requests/<id>.json`: families, profiles, seeds, repetitions, models, conditions). `harness/pipeline.sh` runs one request end to end; the workflow `.github/workflows/enactment.yml` runs it on push of the request file and commits the outputs under `models/enactment/runs/<id>/`: the report `enactment.txt`, `results.jsonl`, `status.json`, and the compressed call logs.


Profiles: each family's `reliable` and `adversarial` profiles. Seeds: 50 per profile. Repetitions: 3 per seed and model. Models per decision M2. In each run one model plays every role. Every model call is logged with the prompt, the response, the resolved model identifier, the provider, the sampling settings and the time. The mock models `mock-faithful` (faithful events; observer echoes `cupid-e`) and `mock-noisy` (seeded omissions and fabrications; observer echoes `cupid`) exercise the pipeline without model calls.

## 11. The purchasing agent (family `purchase`)

In the interactive family `purchase` (`purchase.md`) the observer is also the actor: the control plane buys for the principal by calling the providers. There the agent's role is that one: a **purchasing agent** (`harness/agent_arm.py`) runs as an external arm (`external-arms.md`), makes one provider call per model step, and ends by stating its claims about the four dependencies. The providers are the family's world, unchanged; their replies, faults and truth are the world's. The three instruction conditions of §7 apply to the agent's instructions (role; with the purchase's commitments; with commitments and E1–E3).

Runs are sampled: for each requested profile and seed the world is the keyed draw of `core/family.rkt`, and each (model, condition, seed) is repeated. Determinacy is not defined for an agent arm, so its claims are classified correct, false or abstained against the truth (`purchase-agent.rkt`), and the report gives, per (model and condition, profile), SFR, coverage, the false-claim share and the share of runs in which some dependency in fact failed (the agent's conduct makes the truth), with the spread across repetitions. A request asks for these runs with `"purchase_agent": {"profiles", "seeds", "conditions"}`.
