# Commitment arms — `reservation`

Read `README.md` here, `../paradigms.md` and `../reservation.md` first. Protocol: `../bspl/reservation.bspl`. Protocol and interface: those of `hybrid` — `(hasheq 'regrant 'expiry-fenced)` and `(hasheq 'records '(GRANT RELEASE EXPIRE USE REJECT))`.

## Information base

From `(read-ok 11 (log as-of e ...))`, one fact per entry (all citing the read):

| entry | fact |
|---|---|
| `(GRANT who t)` | `GRANT`, source V, performance (V's report of its own grant), time `t`, attrs `(who)` |
| `(RELEASE t)` | `RELEASE`, source h1, act, time `t` |
| `(EXPIRE t)` | `EXPIRE`, source V, act, time `t` |
| `(USE who from to)` | `USE`, source resource, performance, time `to`, attrs `(who from to)` |
| `(REJECT who t)` | `REJECT`, source resource, act, time `t`, attrs `(who)` |

Coverages: V through `as-of` for `GRANT RELEASE EXPIRE`; the resource through `as-of` for `USE REJECT`. With `read-failed`, no facts and no coverages.

## Commitments

- `C2 = C(V, h2, ⊤, granted(h2) by D2)`; consequent kinds `GRANT USE REJECT`. `granted(h2)` is any of: a `GRANT` to h2; a `USE` by h2; a `REJECT` of h1 (the resource refuses a superseded token only once h2 holds a newer one).
- `M` — V's maintenance commitment to both holders: no instant with two effective users.

## Judgments

- `sharing` (`M`):
  - Violated if two `USE` facts of different holders overlap (`from_a < to_b` and `from_b < to_a`); cite the read.
  - otherwise, `cupid-e`: Fulfilled if the log was read (the resource checks fencing tokens, and its access log shows no overlap), else Indeterminate.
  - otherwise, `cupid` (closed world over V's entries): Violated if V's log shows a `GRANT` to h2 and either no `RELEASE`/`EXPIRE` or the earliest of them after that grant; else Fulfilled. Cite the read.
- `temporal` ← state of `C2` (expired cannot occur).

Debtor's clock: reliable (default).
