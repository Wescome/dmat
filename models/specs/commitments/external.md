# Commitment arms — `external`

Read `README.md` here, `../paradigms.md` and `../external.md` first. Protocol: `../bspl/external.bspl`. Protocol and interface: those of `hybrid` — `(hasheq)` and `(hasheq 'receipt? #t 'view 'full)`.

## Information base

| delivery | fact | coverage |
|---|---|---|
| `(msg DONE 6 5)` | two facts, `A` and `B`, each source V, performance, time 5, attrs `(complete)` — V's report of the whole service | — |
| `(msg RECEIPT 8 7 xs)` | `B`, source X, performance, time 7, attrs `(xs)` | — |
| `(read-ok 11 (full as xs wm))` | if `as = done`: `A`, V, performance, time `T-A`, attrs `()`; if `xs` is `complete` or `partial`: `B`, source X (the receipt is signed, so relayed it is still X's report), performance, time `T-X`, attrs `(xs)` | V, through `wm`, events `A B` |

## Commitments

V owes the whole service; X is not a protocol participant. The deadlines are the protocol's schedule: V performs A (at `T-A`) before it dispatches B at `T-DISPATCH`, and X performs B at `T-X` or not at all.

- `C_A = C(V, H, ⊤, A by T-DISPATCH)`; consequent: an `A` fact whose attrs are empty or `(complete)`; kinds `A`.
- `C_B = C(V, H, ⊤, B by T-X)`; consequent: a `B` fact whose attrs are empty or `(complete)`; kinds `B`.

## Judgments

- `internal` ← state of `C_A`.
- `external`: a `B` fact with attrs `(partial)` is a known non-performance of B in full — Violated (cite it) unless `C_B` is discharged; otherwise ← state of `C_B`.

Debtor's clock: reliable (default).
