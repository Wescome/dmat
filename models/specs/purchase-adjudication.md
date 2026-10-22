---
id: DMAT-PURCHASE-ADJ-2026-10
title: Family purchase — adjudication of the external arms (step 3.7.4)
date: 2026-10-22
parent: docs/brief-mas-instance.md (phase 3, step 3.7); models/specs/purchase.md; models/specs/external-arms.md
---

# Family `purchase` — adjudication of the external arms

Two external arms were written for the family by independent authors, each from `purchase.md` §1–§8, `external-arms.md` and the product's own code and decision records, without the world, the judge, the reference arms or any result:

- **product-r**, a transaction-recovery control plane: its purchase use case runs unchanged behind port adapters (bridge revision `dc9ce83`, private).
- **product-o**, an obligation engine: a purchase program in the engine's language, driven by a closed-loop bridge over the reference engine (revision `b0452cf`, private).

Both ran in all 2,592 worlds of the family's support; every run ended normally (no timeout, malformed output or call limit), and every stored run replays against the world exactly. With the products present, the tests rerun every 27th stored world and reproduce its calls, replies and claims. Each author recorded where the provider interface and the product did not fit (product-r 18 points, product-o 17) and where the specification was silent; this record decides the specification questions and traces every false claim and every operational failure to its cause. The rule is the one of `adjudication.md`: the written specification is the contract; the product is the product as its developers wrote it; a bridge may translate but may not add recovery or judgment of its own.

## 1. Results (adversarial profile; `purchase.txt`)

| arm | SFR | FCR | coverage | false | abstained-miss | determinable | funds failed | flow failed | temporal failed |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| hybrid | 0 | 0 | 0.833 | 0 | 0.056 | 0.889 | 0 | 0.111 | 0.778 |
| hybrid-noe | 0.397 | 0.167 | 1.000 | 0.126 | 0 | 0.889 | 0.056 | 0.111 | 0.778 |
| cupid | 0.463 | 0.180 | 1.000 | 0.144 | 0 | 0.889 | 0 | 0.111 | 0.778 |
| cupid-e | 0 | 0 | 0.847 | 0 | 0.042 | 0.889 | 0 | 0.111 | 0.778 |
| product-r | 0.074 | 0.065 | 0.757 | 0.035 | 0.208 | 0.937 | 0.389 | 0.145 | 0.895 |
| product-o | 0 | 0 | 0.903 | 0 | 0.056 | 0.958 | 0 | 0.111 | 0.778 |

"Failed" is the probability that the dependency in fact failed: the arm's own conduct makes the truth (operational adequacy). Determinability differs between arms because their conduct differs, so the same world gives different transcripts.

## 2. Specification questions

**A1. Cite form.** `purchase.md` §8 said a claim cites deliveries by index; `external-arms.md` §1 said cites are call sequence numbers. Both authors noticed it and sent sequence numbers. *Decision:* both are right for their reader — external arms cite sequence numbers `n`, and the runner converts to delivery indices `n − 1`. `purchase.md` §8 is clarified. No arm changes.

**A2. The deadline was not in the start message.** DEADLINE is a family constant (`purchase.md` §6), but the start message gave the principal's limit and not the principal's deadline, so a mechanism that takes the deadline as an input could not receive it. product-o read it from §6; product-r has no deadline input. *Decision:* a specification omission. The start message now carries `principal.deadline` (`external-arms.md` §1). The change cannot alter a stored run (the start message is not part of the transcript, and neither arm reads the field); the reproduction test was rerun after it and passes. Whether product-r uses it is a product question (§3, §7).

**A3. Shipment requires captured funds.** In the family, `ship` needs an accepted order and a captured hold (`purchase.md` §3). product-o's author recorded it (misfit 11): the engine's own purchase example captures only after delivery and releases the authorisation if delivery is late, and here the release had to become a refund. With capture after delivery, a charge can never stand without delivered goods, so `flow` cannot fail by construction; the family as written excludes that mechanism, so it cannot credit it. *Decision:* not an error in either arm; a design question for the family, decision **M6** (`docs/brief-mas-instance.md`). Recommended: let a seller ship against an authorised hold, so capture timing is the mechanism's choice and part of what is compared; until decided, the results stand for the family as written. *Decided (b), 2026-10-22:* a seller ships against an authorised or a captured hold (`purchase.md` §3). Every stored run of §1 replays unchanged under it, and the report is identical, since no arm shipped against an uncaptured hold.

**A4. The run had no horizon.** Raised by product-o's revision (§7): calls carry no instant, so a mechanism whose rules fire on time (an obligation falling due at DEADLINE) learns that the deadline has passed only if some reply names a later instant. Where none does — the seller reports a delivery the carrier never records — the revised program ended with its hold still authorised, though the run is evaluated after the deadline. *Decision:* a specification omission. The run's horizon is T-LATE: the run spans the instants up to it, the dependencies are evaluated when the arm ends, and an arm may treat the deadline as passed once it has nothing further to do before the horizon (`purchase.md` §6). The start message carries `horizon` (`external-arms.md` §1). No stored run of §1 changes; the reproduction test was rerun with every product present.

## 3. False claims

Every false claim of product-r (192 worlds of the adversarial support, 4 of `carrier`) is the same claim: **`temporal` claimed Fulfilled when delivery was late**, in two kinds of world.

- **Late delivery, honest report** (96 worlds): the seller reports `delivered_at: 14` and the carrier records 14. The reply reached the bridge, but the product's delivery port returns nothing, so the instant has no place to go; the product learns of lateness only from the carrier's DEADLINE_BREACH failure class (its ADR-0007), which a late but completed delivery does not raise. The run ends FINAL, and FINAL is the product's assertion that delivery is done with no breach signalled. *Cause:* the product's interface cannot represent when delivery happened — an observation-model limit of the product, in the sense of P2. The bridge's author declined to manufacture a DEADLINE_BREACH from the instant, correctly: that would be recovery the product does not have.
- **Late delivery, premature report** (96 worlds): the seller reports 10, the goods arrive at 14. Even with the instant passed through, the product takes the seller's report of its own performance as delivery and never reads the carrier's record. *Cause:* E1 is absent from the product's delivery path.

*Decision:* both are the product's. The claim mapping (`temporal` Fulfilled on FINAL) states what the product's FINAL asserts under its own decision records, and is kept. product-o makes no false claim under any profile.

## 4. Operational failures

**product-r leaves a hold live (funds failed 0.389 adversarial; 0.333 `unknown-outcome`, 0.222 `stale-release`).** After a payment call with an unknown outcome, the product does not resend; it reads the processor's record until the record is authoritative. Under `read=stale` the record never covers the call in doubt, the bridge reports each read as not authoritative (the product's own ADR-0004/0007 reading: a stale read establishes nothing), the product's read retry is exhausted, and it escalates with the hold possibly live. Example: `(world kept within lost replied stale replied on-time honest recorded)` — authorize (no reply), three stale records, escalation; the hold is in fact AUTHORIZED. The product's claims stay honest (`funds` Indeterminate), so this is operational, not epistemic, inadequacy: the mechanism is safe in what it says and leaves the dependency to a person. The reference hybrid and product-o resend under the same idempotency key, which the interface guarantees has no further effect, and the act reply establishes the state. The alternative bridge choice — passing the stale record as current state — would have reproduced the double-hold failure of `hybrid-noe`; it was rejected for that reason. *Decision:* the product's. The same escalation explains its higher `flow` (0.145) and `temporal` (0.895) failure rates: a capture in doubt that is never resolved leaves a standing charge and no shipment.

**product-o** has exactly the reference hybrid's failure rates under every profile. Its remaining `flow` and `temporal` failures are the family's: a dropped carrier scan with a premature seller report, and late or missing delivery the buyer cannot prevent.

## 5. Coverage beyond the reference

product-o decides more than the hybrid (coverage 0.903 against 0.833, determinable 0.958 against 0.889) with no false claim. Traced world by world: it decides `flow` where the hybrid abstains in 720 adversarial worlds, every one of them a world where the carrier scan failed and product-o read `shipment-state` instead, which the hybrid never does; and `temporal` in 288, worlds with the same fallback read where it also refunded after the seller's DEADLINE_BREACH, an admission against the seller's interest that E1 admits. It abstains where the hybrid decides in 144 worlds for each of the two dependencies. *Finding:* a fallback read of the shipment record when the carrier's scan is unavailable is a mechanism the reference hybrid lacks; the reference is the paradigm's instance and is not changed after seeing an external result.

## 6. What the external arms show

- **E1 and E2 carry over to products.** The product that reads records only up to their completeness point and never takes a party's report as its own performance (product-o) is safe in every world; the product without E1 on its delivery path (product-r) is false exactly where a party's report is the only evidence.
- **Epistemic and operational adequacy separate in products, too.** product-r is cautious in what it claims and inadequate in what it leaves in place (a live hold after a stale record); `hybrid-noe` is the reverse at the same faults (it acts and claims on the stale record).
- **The interface is part of adequacy.** product-r's false claims come from a port that has no place for the delivery instant, not from its decision logic.

## 7. Revisions after adjudication (step 3.7.6)

Each product was revised for the causes traced to it above, on a branch of its own repository, and entered as a second arm beside its first measurement: `product-r2` (revision `64b1ce9`) and `product-o2` (revision `dd0d02c`). The revisions were made by authors who read this record; they are product changes made in light of the results, not independent measurements, and are reported beside the first measurement, which stands.

- **product-r2** — three changes, each recorded in the product's own decision records: (1) the transaction carries the principal's delivery deadline and delivery yields an instant, so a late delivery is disclosed as a missed deadline rather than presented as on time; (2) delivery and its instant are established only by the carrier's record, through a new port; the seller's report is kept as a claim; when the carrier's record cannot be read, delivery may be established by the shipment read and its timing is not; (3) after an unknown outcome on an operation whose provider declares idempotency by key, when no authoritative read is available, the operation is resent under the same key and the act reply establishes the state; escalation remains for undeclared operations and spent resends. The bridge passes the deadline, maps the new port to `carrier-scan` and declares the processor's guarantee (`purchase.md` §3).
- **product-o2** — the program captures only once delivery is established (the carrier's record, or the shipment read when the carrier's record cannot be read) and releases the authorisation when the delivery obligation is breached, as the engine's own direct-payment program does; a delivery established after the deadline is never captured. The bridge advances the engine to the run's horizon (A4) before it ends. One claim-mapping change: a breach recorded only at the horizon, when the carrier's record was never read and the shipment read shows delivery, says nothing about when the goods arrived, and leaves `temporal` Indeterminate.

Both revisions ran in all 2,592 worlds; every run ended normally, every stored run replays against the world, and with every product version present the tests reproduce the sampled runs of all four product arms.

| adversarial | SFR | coverage | abstained-miss | determinable | funds failed | flow failed | temporal failed |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| hybrid | 0 | 0.833 | 0.056 | 0.889 | 0 | 0.111 | 0.778 |
| product-r | 0.074 | 0.757 | 0.208 | 0.937 | 0.389 | 0.145 | 0.895 |
| product-r2 | 0 | 0.796 | 0.162 | 0.958 | 0 | 0.111 | 0.778 |
| product-o | 0 | 0.903 | 0.056 | 0.958 | 0 | 0.111 | 0.778 |
| product-o2 | 0 | 0.958 | 0 | 0.958 | 0 | 0 | 0.778 |

- **product-r2 makes no false claim under any profile** (product-r: SFR 0.074 adversarial, 0.333 `carrier`), and leaves no hold live in any world (product-r: 0.389). Each of the three changes removes exactly the failure traced to it in §3–§4: the delivery instant and the carrier's record remove the false `temporal` claims of both kinds; the resend under the same key removes the live holds, and with them the excess `flow` and `temporal` failures. Its failure rates now equal the reference hybrid's.
- **product-r2's remaining abstentions are its finality rule.** Under stale or unavailable records its final reconciliation never succeeds — there is no act to resend for a read — so it ends in escalation and claims `funds` and `flow` Indeterminate although the act replies of its own resends established them (abstained-miss 0.162; 0.333 under `unknown-outcome` and `stale-release`, where its coverage fell from 0.708 and 0.722 to 0.667). This is the product's choice to require a reconciled record for finality (its obligation-lifecycle rule), not a defect traced here.
- **product-o2: capture after delivery removes the `flow` failure entirely** (0.111 → 0 adversarial; 0.167 → 0 `carrier`): no charge is ever standing without delivered goods. It decides every determined claim (abstained-miss 0) with no false claim. Its remaining `temporal` failures are late and missing deliveries, which no buyer's mechanism can prevent.
- **The theory's prediction held in both directions.** The causes traced in §3–§4 were stated as the absence of E1 (the seller's report taken as delivery), the absence of the observation (no delivery instant at the port), and conduct that waited on a record E2 would not accept. Adding exactly those — and nothing else — made the product sound at the same faults, and as adequate operationally as the reference hybrid.
