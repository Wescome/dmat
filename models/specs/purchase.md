# Family `purchase` — purchase on a principal's behalf (Sharing, Fit, Flow, Temporal)

Read `paradigms.md` §1–§2 first for the setting, the claim grammar and the judgment values. Grammar and constants: `families/purchase/terms.rkt` (language `PURCHASE`). External arms: `external-arms.md`.

This family is phase 3, step 3.7 of the research plan. Families 1–8 each isolate one coordination pattern; this one combines seven in one transaction, and its world is **interactive**: an arm acts by calling the providers, the providers answer, and the world's faults shape the answers. What happens depends on what the arm does, so every arm is also a mechanism, and truth depends on the arm (operational adequacy) throughout.

## 1. Scenario

A control plane C buys goods for a principal P under P's delegated spending limit `CAP`. It acts against four providers through one provider interface (§3):

- a payment processor X, which places holds on P's funds, captures, voids and refunds them, and keeps a record of its holds;
- the primary seller A, at price `PRICE-A`;
- an alternative seller B, at a price that may lie within or beyond `CAP`, or not available at all;
- a carrier, which ships and delivers the goods and keeps its own record of deliveries.

The nominal run: reserve at A, authorise a hold for A's price, confirm A's stock, have A accept the order, capture, ship, deliver. When A loses its stock after the hold exists, C must release A's hold before it buys from B, or P's funds carry two holds. When a reply is lost, C does not know whether its call took effect, and the processor's record, which C can read, may lag behind the processor's own state.

The patterns combined:

| Pattern | Where | Family it isolates |
| --- | --- | --- |
| responsibility handed to a provider | A or B accepts the order | handoff |
| participant replacement | reroute from A to B | replacement |
| delegated authority | P's limit `CAP` | delegation |
| exclusive claim on a shared resource | holds on P's funds | reservation |
| execution outside the protocol's participants | the carrier's delivery | external |
| several organisations, no single observer | processor, sellers, carrier | composition |
| a deadline | delivery by `DEADLINE` | deadline |

## 2. Dependencies (claims in this order)

Truth is computed from the providers' state when the arm ends its run.

1. `funds` (Sharing) — P's funds carry no live hold and at most one standing charge: no hold of X is `AUTHORIZED`, and at most one is `CAPTURED`.
2. `fit` (Fit) — no charge exceeds P's limit: every hold that was ever captured (now `CAPTURED` or `REFUNDED`) has an amount ≤ `CAP`.
3. `flow` (Flow) — every standing charge is matched by goods: if a hold is `CAPTURED`, the goods were delivered.
4. `temporal` (Temporal) — the goods were delivered, at an instant ≤ `DEADLINE`.

## 3. Provider interface

In the models' terms (`terms.rkt`) names written here with an underscore are written with a hyphen (`IN-TRANSIT`, `STATE-UNCERTAIN`), since Redex reserves the underscore; external arms use the names as written here.

An arm makes **calls**. Calls are numbered 1, 2, … in the order the arm makes them; the number is the call's **sequence number** `n`. Every call receives exactly one **reply**, either `(ok value)` or `(failed class code)`, where `class` is one of `STATE_UNCERTAIN` (the outcome is unknown), `BUSINESS_REJECTION`, `RESOURCE_UNAVAILABLE`, `DEPENDENCY_FAILURE`, `DEADLINE_BREACH`, and `code` is a symbol. A reply `(failed STATE_UNCERTAIN no-reply)` means the arm learnt nothing about the call's effect.

`key` arguments are idempotency keys chosen by the arm. Holds, orders and the shipment are identified by seller (`A` or `B`).

| Operation | Arguments | Effect and reply (no fault) |
| --- | --- | --- |
| `reserve` | seller | A: `(ok reserved)`. B: `(ok reserved)` when B exists, else `(failed RESOURCE_UNAVAILABLE no-offer)`. No effect |
| `alternatives` | — | `(ok ((B price)))` when B exists, else `(ok ())`. A read |
| `authorize` | seller, amount, key | If the seller has no hold, or its hold is `VOIDED` and `key` is new: the seller's hold becomes `AUTHORIZED` with `amount`. A key already used for this seller has no further effect. Reply `(ok AUTHORIZED)` |
| `confirm` | seller | `(ok available)`, or `(ok lost)` for A when A's stock is lost. A read |
| `accept` | seller, key | The seller's order becomes `ACCEPTED`. Reply `(ok ACCEPTED)`. A with lost stock: `(failed BUSINESS_REJECTION out-of-stock)`, no effect |
| `void` | seller, key | If the seller's hold is `AUTHORIZED` it becomes `VOIDED`. Reply `(ok S)` with the hold's state after the call (`NONE` when there is no hold) |
| `capture` | seller, key | If the seller's hold is `AUTHORIZED` it becomes `CAPTURED`; reply `(ok CAPTURED)`. If already `CAPTURED`, no effect, `(ok CAPTURED)`. Otherwise `(failed BUSINESS_REJECTION not-authorized)` |
| `refund` | seller, key | If the seller's hold is `CAPTURED` it becomes `REFUNDED`. Reply `(ok S)` with the state after the call |
| `cancel` | seller, key | If the seller's order is `ACCEPTED` and nothing has shipped, the order becomes `CANCELLED`; reply `(ok CANCELLED)`. Otherwise `(failed BUSINESS_REJECTION not-cancellable)` |
| `ship` | seller, key | If the seller's order is `ACCEPTED`, the seller's hold is `AUTHORIZED` or `CAPTURED` and nothing has shipped: the shipment, from this seller, becomes `IN_TRANSIT`; reply `(ok IN_TRANSIT)`. Otherwise `(failed BUSINESS_REJECTION not-shippable)` |
| `deliver` | seller, key | If the shipment is `IN_TRANSIT` from this seller, the carrier delivers (§4, `deliver` slot): reply `(ok delivered-at)`, the seller's report of the delivery instant. Otherwise `(failed BUSINESS_REJECTION nothing-in-transit)` |
| `payment-record` | — | The processor's record of every hold, `((seller state amount) …)`, as of its **completeness point** (§5) |
| `order-state` | seller | `(ok S)`, the seller's order state: `NONE`, `ACCEPTED`, `CANCELLED`. A read |
| `shipment-state` | — | `(ok S)`: `NONE`, `IN_TRANSIT` or `DELIVERED`. A read |
| `carrier-scan` | — | The carrier's own record: `(ok delivered-at)` or `(ok none)` |
| `reconcile` | — | `(ok report)`: the payment record (as `payment-record`, with its faults and completeness point), every order state, the shipment state, and the count of `CAPTURED` holds in that record |

A call to a seller other than `A` or `B`, or with arguments of the wrong form, is answered `(failed BUSINESS_REJECTION bad-call)` with no effect. An arm that makes more than `CALL-LIMIT` calls is stopped; its claims are then all `Indeterminate`.

## 4. Environment (world slots)

A world is `(world stock alt auth void read capture deliver report scan)`. Faults on an operation apply to the **first call** of that operation in the run; later calls of the same operation behave without fault, except `read`, which applies to every payment-record read. `deliver`, `report` and `scan` are the carrier's and the seller's conduct and apply to every call.

| Slot | Values | Meaning |
| --- | --- | --- |
| `stock` | `kept`, `lost` | A's stock. `lost`: `confirm A` answers `lost` and `accept A` is refused |
| `alt` | `within`, `over`, `none` | B's offer: price `PRICE-B-WITHIN` (≤ CAP), `PRICE-B-OVER` (> CAP), or no B |
| `auth` | `replied`, `lost` | `lost`: the first `authorize` takes effect and its reply is `(failed STATE_UNCERTAIN no-reply)` |
| `void` | `replied`, `lost`, `timeout` | First `void`: `lost` takes effect, reply unknown; `timeout` has no effect, reply unknown |
| `read` | `fresh`, `stale`, `unavailable` | Every `payment-record` (and the payment part of `reconcile`): `stale` omits the latest payment effect; `unavailable` answers `(failed DEPENDENCY_FAILURE record-unavailable)` |
| `capture` | `replied`, `lost` | `lost`: the first `capture` takes effect, reply unknown |
| `deliver` | `on-time`, `late`, `never` | Delivery at `T-ON-TIME`, at `T-LATE`, or never: `never` answers `(failed DEADLINE_BREACH not-delivered)` and the shipment stays `IN_TRANSIT` |
| `report` | `honest`, `premature` | The seller's delivery report. `premature`: whenever the goods have not been delivered by `DEADLINE`, `deliver` answers `(ok T-ON-TIME)` as if they had |
| `scan` | `recorded`, `dropped` | The carrier's record: `dropped` answers `carrier-scan` with `(failed DEPENDENCY_FAILURE scan-unavailable)` |

The unknown-outcome reply of `auth`, `void` and `capture` is `(failed STATE_UNCERTAIN no-reply)`. A `delivered-at` instant in a `deliver` reply is the seller's report; `carrier-scan` is the carrier's.

## 5. The payment record and its completeness point

Each payment effect (a hold placed, voided, captured or refunded) is stamped with the sequence number of the call that caused it. A `payment-record` read made as call `n` answers with the holds as they stand after applying, in order, every effect of calls numbered ≤ `c`, where `c` is the record's **completeness point**:

- `fresh`: `c = n − 1`;
- `stale`: `c` is one less than the sequence number of the latest payment effect at the time of the read (when there is none, `c = n − 1`).

When the interface feature `'watermark` is `#t`, the reply carries `c`: `(ok (record c ((seller state amount) …)))`; otherwise `(ok (record #f (…)))`. Every arm in this family has `'watermark #t` (equal infrastructure); the feature exists so that P2 can vary it.

## 6. Instants and constants (terms.rkt)

`CAP` 180, `PRICE-A` 150, `PRICE-B-WITHIN` 170, `PRICE-B-OVER` 200, `T-ON-TIME` 10, `DEADLINE` 12, `T-LATE` 14, `CALL-LIMIT` 60.

**The run's horizon** is `T-LATE`: the run spans the instants up to `T-LATE`, and the dependencies are evaluated when the arm ends, at the horizon. Calls carry no instant of their own; an arm whose rules are triggered by time (an obligation falling due at `DEADLINE`) may treat the deadline as passed once it has nothing further to do before the horizon, and act on it before it ends. The start message carries the horizon (`external-arms.md` §1). Added 2026-10-22 (`purchase-adjudication.md`, A4).

## 7. Profiles

| Profile | Slots varied (others at their first value) |
| --- | --- |
| `reliable` | none |
| `stockout` | `stock` {kept 1, lost 3}; `alt` all three |
| `unknown-outcome` | `auth`, `capture` both values; `read` all three |
| `stale-release` | `stock` lost; `alt` within; `void` all three; `read` all three |
| `carrier` | `deliver` all three; `report` and `scan` both values |
| `adversarial` | every slot, every value |

Base weights are 1 per value unless a profile says otherwise. The canonical map is the identity: since conduct is the arm's, no slot is irrelevant for every arm.

## 8. Deliveries

An arm's deliveries are its **transcript**: for each call, in order, `(msg REPLY n n (op arg ...) reply)` — arrival and assertion instant are both the call's sequence number. A claim cites deliveries by index, as in every family (index = `n − 1`). An external arm cites by call sequence number `n` and the runner converts (`external-arms.md` §1; clarified 2026-10-22, `purchase-adjudication.md`, A1).

## 9. Arms

| name | protocol | interface |
| --- | --- | --- |
| hybrid | `(hasheq 'mechanism 'hybrid)` | `(hasheq 'watermark #t)` |
| hybrid-noe | `(hasheq 'mechanism 'hybrid-noe)` | `(hasheq 'watermark #t)` |
| cupid | `(hasheq 'mechanism 'hybrid)` | `(hasheq 'watermark #t)` |
| cupid-e | `(hasheq 'mechanism 'hybrid)` | `(hasheq 'watermark #t)` |
| external arms | `(hasheq 'mechanism 'external 'arm NAME)` | `(hasheq 'watermark #t)` |

Capture timing is each mechanism's choice since M6 (2026-10-22): a seller ships against an authorised or a captured hold. `hybrid` and `hybrid-noe` capture before shipment, as before M6; their runs are unchanged by it.

`hybrid` acts on established state only: after an unknown outcome it reads the payment record and accepts what the record shows only when the record's completeness point covers the call; it resends with the same key otherwise; it releases a hold before it reroutes, and reroutes only once the release is established; it captures only within `CAP`; it refunds a charge whose goods were not delivered by the deadline. Its claims follow E1–E3: a seller's report of delivery is not evidence of delivery (the carrier's scan is); a record shows an absence only up to its completeness point. `hybrid-noe` is the same mechanism without the evidential layer: it reads any record as current and any report as fact. `cupid` and `cupid-e` judge `hybrid`'s transcript with the commitments of `commitments/purchase.md`. The family module (`families/purchase/arms.rkt`) states each mechanism's rules in full.

## 10. Checks

- Totality: every arm's run ends within `CALL-LIMIT` calls in every world, with a claims term.
- Isolation: the reference arms' modules import only the core arm, observe, grammar and cupid modules, the family's terms, and the family's provider interface (which carries no truth).
- Determinacy by search over each profile's support, as in every family.
- An external arm's transcript in a world is reproduced exactly by replaying its calls against the world (§ `external-arms.md`).
