# Family `agreement` — multi-party agreement (Fit, Flow)

Read `paradigms.md` first. Grammar and constants: `families/agreement/terms.rkt` (language `AGREEMENT`).

## Scenario

A buyer B proposes terms to a seller S. S accepts — with the proposed terms, or with altered terms that do not fit B's requirement. B then confirms or rejects; S binds on processing the confirmation and acknowledges. S may revoke its offer concurrently with B's confirmation: the two cross, and the order in which S processes them varies (interleaving). The observer is B.

## Dependencies (claims in this order)

1. `fit` (Fit) — no party ends up bound to terms that do not fit B's requirement (violated if anyone is bound and the terms were altered).
2. `mutual` (Flow) — B and S agree on whether they are bound: both bound or neither.

## Constants (terms.rkt)

`T-ACCEPT-SENT` 1, `T-ACCEPT-ARR` 2, `T-CONFIRM` 2, `T-S-PROCESS` 3, `T-ACK-ARR` 4, `T-READ` 11, `T-EVAL` 12, `STALE-AS-OF` 1.

## What can happen (fault model)

- S's acceptance carries terms `as-proposed` or `altered`.
- S may revoke; if it does, S processes either B's confirmation first (then S is bound and the revocation is void) or its revocation first (then S is not bound).
- B's CONFIRM may be dropped; S's ACK may be dropped.
- The read-back of S's record may be fresh (as of 11), stale (as of 1), or fail.

## Protocol features (decide conduct — the truth depends on them)

- `'fit-check` — `#t`: B confirms only if the terms are `as-proposed`, and otherwise rejects; `#f`: B confirms whatever terms arrive.
- `'bind` — when B considers itself bound: `send` (on sending CONFIRM); `ack` (on receiving S's ACK); `ack-reconcile` (on the ACK, or, failing it, when a fresh read-back of S's record shows S bound).

S is bound iff the confirmation arrives and S does not process a revocation first. S revokes (sends REVOKE) if it chose to revoke and is not bound.

## Deliveries (to B, in this order)

1. `(msg ACCEPT 2 1 terms)` — always; payload is `as-proposed` or `altered`.
2. `(msg CONFIRM 2 2)` if B confirmed, else `(msg REJECT 2 2)` — B's own outgoing message, recorded in B's log (always present; it is B's own act, not a delivery from S).
3. `(msg REVOKE 3 2)` — if S revoked.
4. `(msg ACK 4 3)` — if S bound and the ACK was not dropped.
5. `(read-ok 11 view)` or `(read-failed 11)`.

## Views of S's record (as of the read's as-of; S's state is `offered` before 3)

- `(last-message lm)` — S's last session message: `ACK` (S bound), `REVOKE` (S revoked), `ACCEPT` (otherwise).
- `(state ss)` — `bound`, `revoked`, or `offered`.
- `(ledger cs)` — S's commitment C(S, B, confirmed, deliver on the terms): `active` (S bound), `released` (revoked), `none`.
- `(full ss terms as-of)` — state, the terms S accepted with, and the as-of instant.

## Arms (use exactly these)

| name | protocol | interface |
|---|---|---|
| chor | `(hasheq 'fit-check #f 'bind 'send)` | `(hasheq 'view 'last-message)` |
| fsm | `(hasheq 'fit-check #t 'bind 'ack)` | `(hasheq 'view 'state)` |
| comm | `(hasheq 'fit-check #t 'bind 'ack)` | `(hasheq 'view 'ledger)` |
| hybrid | `(hasheq 'fit-check #t 'bind 'ack-reconcile)` | `(hasheq 'view 'full)` |
| hybrid-noe | `(hasheq 'fit-check #t 'bind 'ack-reconcile)` | `(hasheq 'view 'full)` |

Note that B knows its own protocol's binding rule and its own outgoing messages. Family symbol: `'agreement`.

## Clarification added after the differential check

S's ACK is the act that creates S's binding, not a report of performance. CHOR checks messages by type, not by payload value (see `paradigms.md` §5).
