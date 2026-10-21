# Family `external` — partial external execution (Flow, Flow)

Read `paradigms.md` first. Grammar and constants: `families/external/terms.rkt` (language `EXTERNAL`).

## Scenario

H orders a two-part service from V. V performs part A itself (at `T-A`), and at `T-DISPATCH` dispatches part B to an external executor X that is not a participant in the H–V protocol. X may perform B in full, partially, or not at all (at `T-X`). V cannot observe B's outcome. V reports DONE to H. Protocols that define an external receipt get X's signed outcome, and the hybrid's record relays it. The observer is H.

## Dependencies (claims in this order)

1. `internal` (Flow) — part A was performed.
2. `external` (Flow) — part B was performed in full (partial counts as violated).

## Constants (terms.rkt)

`T-A` 4, `T-DISPATCH` 5, `T-DONE` 6, `T-X` 7, `T-RECEIPT` 8, `T-READ` 11, `T-EVAL` 12, `LAG-WATERMARK` 6.

## What can happen (fault model)

- V performs A or not.
- X completes B, completes it partially, or does nothing.
- V reports DONE honestly (only if A was done) or prematurely (regardless of A).
- X's receipt may be dropped.
- The read-back of V's record may be fresh (complete as of 11), lagging (complete only through 6), or fail.

## Deliveries (to H, in arrival order)

- `(msg DONE 6 5)` — V's report, sent if A was done or V reports prematurely.
- `(msg RECEIPT 8 7 xs)` — X's signed outcome (`complete` or `partial`), if the interface has `receipt? #t` and X did something; may be dropped. X sends nothing if it did nothing.
- `(read-ok 11 view)` or `(read-failed 11)`.

## Views of V's record

- `(record as)` — `as` = `done` if V performed A, else `pending`.
- `(full as xs wm)` — A's status, X's outcome as relayed into V's record (`none` if X did nothing or the relay is past the watermark, else `partial`/`complete`), and `wm`, the instant through which the record is complete (11, or 6 under lag).

## Arms (use exactly these)

| name | protocol | interface |
|---|---|---|
| chor | `(hasheq)` | `(hasheq 'receipt? #f 'view 'record)` |
| fsm | `(hasheq)` | `(hasheq 'receipt? #f 'view 'record)` |
| comm | `(hasheq)` | `(hasheq 'receipt? #f 'view 'record)` |
| hybrid | `(hasheq)` | `(hasheq 'receipt? #t 'view 'full)` |
| hybrid-noe | `(hasheq)` | `(hasheq 'receipt? #t 'view 'full)` |

Family symbol: `'external`.

## Clarification added after the differential check

DONE is V's report that the order is complete (both parts). V sends it when A is done (honest) or regardless (premature); V cannot observe B, so a DONE never reflects B's outcome.
