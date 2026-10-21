# Commitment arms — `agreement`

Read `README.md` here, `../paradigms.md` and `../agreement.md` first. Protocol: `../bspl/agreement.bspl`. Protocol and interface: those of `hybrid` — `(hasheq 'fit-check #t 'bind 'ack-reconcile)` and `(hasheq 'view 'full)`.

## Information base

| delivery | fact | coverage |
|---|---|---|
| `(msg ACCEPT 2 1 terms)` | `ACCEPT`, source S, act, time 1, attrs `(terms)` | — |
| `(msg CONFIRM 2 2)` | `CONFIRM`, source B, act, time `T-CONFIRM` | — |
| `(msg REJECT 2 2)` | `REJECT`, source B, act, time `T-CONFIRM` | — |
| `(msg REVOKE 3 2)` | `REVOKE`, source S, act, time `T-CONFIRM` | — |
| `(msg ACK 4 3)` | `BIND`, source S, act (S's act of binding), time `T-S-PROCESS` | — |
| `(read-ok 11 (full ss terms as-of))` | `ss = bound`: `BIND`, S, act, time `T-S-PROCESS`; `ss = revoked`: `REVOKE`, S, act, time `T-S-PROCESS` | S, through `as-of`, events `BIND REVOKE` |
| (B's own log) | — | B, through `T-READ`, events `CONFIRM REJECT`, index `#f` |

B's outgoing messages are B's own acts: B's log is complete for them.

## Commitments

- `C_S = C(S, B, CONFIRM by T-CONFIRM, BIND by T-S-PROCESS)`; antecedent kinds `CONFIRM`, consequent kinds `BIND`.

## Judgments

S's binding, in this order: `C_S` discharged → bound (cite the state's citations); a `REVOKE` fact → not bound (cite it); a `REJECT` fact → not bound (the protocol binds S only on a confirmation; cite it); `C_S` violated or expired → not bound; otherwise unknown.

B's binding (B's own state under the protocol): an `ACK`, or a read showing `ss = bound` — in `cupid-e` only if `as-of ≥ T-S-PROCESS`, in `cupid` from any read. Cite the ACKs and the read used.

- `fit`: Violated if B sent `CONFIRM` and S's `ACCEPT` carried `altered`; else Fulfilled. Cite the ACCEPT and B's CONFIRM/REJECT.
- `mutual`: if S's binding is unknown, Indeterminate; else Fulfilled when B's and S's bindings agree, Violated otherwise; cite both.

Debtor's clock: reliable (default).
