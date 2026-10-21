# Family `reservation` — resource reservation (Sharing, Temporal)

Read `paradigms.md` first. Grammar and constants: `families/reservation/terms.rkt` (language `RESERVATION`).

## Scenario

An allocator V holds one exclusive resource. V grants it to holder `h1` at `T-GRANT1` with a lease until `LEASE-END`; holder `h2` requests it at `T-REQ2`. The observer is an auditor who reads V's allocation log once, at `T-READ`.

## Dependencies (claims in this order)

1. `sharing` (Sharing) — at no instant do two holders effectively use the resource (an overcommit is a violation).
2. `temporal` (Temporal) — `h2` is granted the resource by `D2`.

## Constants (terms.rkt)

`T-GRANT1` 1, `T-REQ2` 2, `T-DEAD` 2, `T-RELEASE` 3, `LEASE-END` 5, `D2` 7, `T-SLOW-RELEASE` 8, `H2-USE` 2, `T-READ` 11, `T-EVAL` 12, `STALE-AS-OF` 4.

## What can happen (fault model)

- `h1` releases at 3 (`releases`), overruns its lease and uses the resource until 8 then releases (`slow`), or dies at 2 (`dead`: stops using the resource, never releases).
- A release message to V may be dropped (then V never learns of it).
- The read-back of V's log may be fresh (as of 11), stale (as of 4), or fail.

## Protocol feature `'regrant` (decides V's conduct — the truth depends on it)

- `on-release` — V grants to `h2` only when it receives `h1`'s release.
- `expiry` — V grants to `h2` at the earlier of a received release and `LEASE-END`; at `LEASE-END` without a release V records `EXPIRE`. `h1` is not stopped: if it still uses the resource after `h2`'s grant, both use it.
- `expiry-fenced` — as `expiry`, but grants carry fencing tokens checked by the resource: once `h2` is granted, `h1`'s further use is rejected (`REJECT h1 t`) and its use ends there.

Once granted, `h2` uses the resource for `H2-USE` instants.

## Deliveries (to the auditor)

Only one: `(read-ok 11 (log as-of e ...))` or `(read-failed 11)`. The log lists the events of the run whose instant is ≤ as-of and whose kind is in the interface's `'records` list, in time order. Event forms:

- `(GRANT who t)` — grant to `h1` or `h2` at `t`;
- `(RELEASE t)` — V received `h1`'s release at `t`;
- `(EXPIRE t)` — V expired `h1`'s lease at `t`;
- `(USE who from to)` — the resource reports `who` used it over [from, to] (instant of the event: `to`);
- `(REJECT who t)` — the resource rejected `who`'s stale-token use at `t`.

`GRANT`, `RELEASE`, `EXPIRE` are V's own entries. `USE` and `REJECT` come from the resource's access log (an independent source). A protocol whose interface does not list a kind does not record it.

## Arms (use exactly these)

| name | protocol | interface |
|---|---|---|
| chor | `(hasheq 'regrant 'on-release)` | `(hasheq 'records '(GRANT RELEASE))` |
| fsm | `(hasheq 'regrant 'expiry)` | `(hasheq 'records '(GRANT RELEASE EXPIRE))` |
| comm | `(hasheq 'regrant 'on-release)` | `(hasheq 'records '(GRANT RELEASE))` |
| hybrid | `(hasheq 'regrant 'expiry-fenced)` | `(hasheq 'records '(GRANT RELEASE EXPIRE USE REJECT))` |
| hybrid-noe | `(hasheq 'regrant 'expiry)` | `(hasheq 'records '(GRANT RELEASE EXPIRE USE REJECT))` |

In this family the hybrid's evidentiary component includes the fencing tokens; the ablation drops them (and E1–E3). Family symbol: `'reservation`.
