# Commitment arms — `composition`

Read `README.md` here, `../paradigms.md` and `../composition.md` first. Protocol: `../bspl/composition.bspl`. Protocol and interface: those of `hybrid` — `(hasheq)` and `(hasheq 'obs 'staged 'attest? #t)`.

## Information base

| delivery | fact |
|---|---|
| `(msg ATTEST a t)` | `START`, source attester, performance, time `t` |
| `(msg DELIVERED a t)` | `DELIVERED`, source V, act (the delivery itself, which H observes), time `t` |
| `(read-ok 16 (staged cs ss ot))` | `ss = started`: `START`, source S (S's report, relayed by V), performance, time `ot`; `ss = declined`: `DECLINE`, source S, act, time `T-COMMIT`; `cs = closed`: `DELIVERED`, source V, performance (V's report of its own delivery), time `T-DELIVER` |

V's case record has no completeness watermark: it yields **no coverage**.

## Commitments

- `C_t = C(S, H, ⊤, START by DEADLINE)` — S's commitment, relayed to H by V's case record; kinds `START`.
- `C_d = C(V, H, ⊤, DELIVERED by T-EVAL)`; kinds `DELIVERED`.

## Judgments

- `temporal`: a `DECLINE` fact cancels `C_t` before discharge — Violated (cite it) unless `C_t` is discharged; otherwise ← state of `C_t`.
- `delivery` ← state of `C_d`.

Debtor's clock: reliable (default). S's report of a late start is an admission.
