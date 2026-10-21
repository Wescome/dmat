# Adjudication of the differential check — commitment arms (2026-10-21)

The reference commitment arms (`families/<family>/cupid.rkt`) were compared with arms written independently from `specs/paradigms.md`, the family specifications, this directory and `specs/bspl/` alone (`independent/<family>-cupid.rkt`), by an author who did not see the reference arms, the world modules or any output. `racket diff.rkt cupid` compares the two on every distinct deliveries list any profile of any family can produce: 411 lists per arm over the eight families.

**First comparison: no disagreement** on any list, for either arm, in any family.

The independent author raised two points about the specifications. They were decided by the rule of the hub's adjudication (`../adjudication.md`): the written specification is the contract; a specification found wrong is amended with a dated note, the reference follows it, and no independent arm is edited.

| # | Family / arm | Point raised | Decision |
| --- | --- | --- | --- |
| C1 | replacement / cupid | The responsibility rule admits a START from V whenever the registry shows V holding after `T-V2`. V holds the role then only because V2 declined, and it resumes at `T-RESUME`; a START from V between `T-V2` and `T-RESUME` is a ghost from V's queue, which the rule let pass (false Fulfilled under the closed-world reading). | Specification wrong. `replacement.md` amended (dated section): after a withdrawal, V's START counts only before `T-V2` or from `T-RESUME`. Reference amended. `cupid-e` was unaffected (E1 already discounts the role holder's report). Residue: **9 lists** for `cupid`, where the independent arm keeps the original rule; pinned by `tests.rkt`. Effect on the reference `cupid`: SFR under `ghost` 0.063 → 0, under `adversarial` 0.133 → 0.082. |
| C2 | all / cupid | A closed-world absence with no applicable coverage yields a definitive claim with no citation. | Specification incomplete, behaviour intended. `README.md` clarified: such a claim is the closed-world reading; the judge classifies it lucky or false, never supported. No change to either arm. |

The author also recorded eighteen readings of points the specifications leave open (view forms other than the hybrid's, which deliveries a citation names, strict versus non-strict instants). None produces a disagreement on any reachable deliveries list: the hybrid interface never produces the other view forms, and the remaining readings coincide on every list the families generate.

Observation for the hub: the hub's `hybrid-noe` uses the responsibility rule C1 amends. Its effect on the hub's numbers is examined in phase 4 (models v0.5), with the hub's other arms; WP-2026-DM-01 reports models v0.3.
