# Commitment arms — `delegation`

Read `README.md` here, `../paradigms.md` and `../delegation.md` first. Protocol: `../bspl/delegation.bspl`. Protocol and interface: those of `hybrid` — `(hasheq 'on-delegate 'retain)` and `(hasheq 'notice? #t 'attest? #t 'view 'full)`. V retains responsibility when it delegates: S performs as V's delegate, and `C1` stays V's until discharged.

## Information base

| delivery | fact | coverage |
|---|---|---|
| `(msg ACCEPT 2 1)` | `ACCEPT`, source V, act, time 1 | — |
| `(msg START a s)` | `START`, source V (the performer reports on V's side), performance, time `s` | — |
| `(msg ATTEST a s)` | `START`, source attester, performance, time `s` | — |
| `(read-ok 11 (full vs c1 c2 stage as-of))` | if `c1 = discharged`: `START`, V, performance, time `min(as-of, DEADLINE)` — V's ledger reports C1 discharged, which places the performance within its deadline | V, through `as-of`, events `START` |

`DELEGATED` yields no fact.

## Commitments

- `C1 = C(V, H, ACCEPT by T-ACCEPT, START by DEADLINE)`; antecedent kinds `ACCEPT`, consequent kinds `START`.

## Judgments

- `continuity`: Violated if a read shows `c1 = released` (cite the read); otherwise Fulfilled (retention keeps C1 V's from acceptance to discharge; cite the ACCEPT).
- `temporal` ← state of `C1`; expired: **Violated**.

Debtor's clock: reliable (default).
