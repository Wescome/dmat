#lang racket/base
;; Family `delegation` — the five arms, written independently from
;; specs/paradigms.md and specs/delegation.md.
;;
;; Scenario: hospital H refers a patient to provider V; V accepts at T-ACCEPT.
;; If V lacks capacity it delegates to subcontractor S at T-DELEGATE; S accepts
;; or declines at T-S-RESPONSE. Whoever is responsible initiates care (or not).
;; The observer is H. Dependencies, in order: continuity, temporal.

(require racket/match
         "../core/arm.rkt"
         "../core/observe.rkt"
         "../families/delegation/terms.rkt")
(provide arms)

;; ---------------------------------------------------------------------------
;; Small shared readers over H's deliveries (no inference, only lookup).

(define (accept-idx ds) (msg-indices ds 'ACCEPT))
(define (delegated-idx ds) (msg-indices ds 'DELEGATED))
(define (read-cite ds) (let ([i (read-index ds)]) (if i (list i) '())))

;; ---------------------------------------------------------------------------
;; CHOR — release protocol; H's projection carries ACCEPT, DELEGATED and the
;; performer's START notice; the read-back returns the last message of V's
;; session log.
;;
;; The global type: V accepts H's referral (ACCEPT); V either proceeds itself
;; or selects the delegation branch, announced to H as DELEGATED, after which
;; V's role ends and S's acceptance and start happen in the V–S / S–H parts of
;; the choreography. H's local session awaits START with a timed branch at
;; DEADLINE: if START has not arrived by DEADLINE, the timeout branch fires.
;; A message is the event it names; V's logged last message is what V sent.
;;   temporal  — START arrived by DEADLINE, or V's log ends with START: care
;;               was initiated (Fulfilled). Otherwise H's timed branch fired at
;;               DEADLINE (Violated); the session has no other outcome.
;;   continuity — the paradigm has no notion of ownership, only of which role
;;               is in the session. If H's projection (or V's log) shows the
;;               delegation branch, the hand-off between V's role and S's role
;;               (S's acceptance) is outside H's projection: Indeterminate.
;;               If the session shows no delegation, V's role ran from ACCEPT
;;               to START or to the timeout with no hand-off: Fulfilled.
(define (judge-chor ds)
  (define acc (accept-idx ds))
  (define dlg (delegated-idx ds))
  (define starts (msg-indices ds 'START #:arrived-by DEADLINE))
  (define lm (match (read-view ds) [(list 'last-message m) m] [_ #f]))
  (define rd (read-cite ds))
  (define temporal
    (cond [(pair? starts) (list 'temporal 'Fulfilled starts)]
          [(eq? lm 'START) (list 'temporal 'Fulfilled rd)]
          [(pair? acc) (list 'temporal 'Violated acc)]          ; timed branch fired
          [else (list 'temporal 'Indeterminate '())]))
  (define continuity
    (cond [(or (pair? dlg) (eq? lm 'DELEGATED))
           (list 'continuity 'Indeterminate '())]
          [(pair? acc)
           (list 'continuity 'Fulfilled
                 (append acc starts (if lm rd '())))]
          [else (list 'continuity 'Indeterminate '())]))
  (claims continuity temporal))

;; ---------------------------------------------------------------------------
;; FSM — retain protocol; no START notice, no attestation; the read-back
;; returns V's current state.
;;
;; V runs the retain machine: accepted → started (capacity) or
;; accepted → delegating → delegated (S accepted) → sub-started, or
;; delegating → resumed (S declined; V's responsibility reactivated) → started.
;; Start transitions are guarded on V's clock (T-START, T-RESUME-START), both
;; before DEADLINE. The read at T-READ is after DEADLINE, and the recorded
;; state is where the machine is.
;;   temporal  — started / sub-started: care was initiated (Fulfilled). Any
;;               other state after DEADLINE: the machine never took a start
;;               transition (Violated). No record: Indeterminate.
;;   continuity — states in which V's own machine holds the referral
;;               (accepted, delegating under retain, resumed, started):
;;               Fulfilled. released: the machine let go of it (Violated).
;;               delegated / sub-started: responsibility now rests on S's
;;               obligation, a cross-party fact the FSM does not model
;;               (Indeterminate). No record: Indeterminate.
(define (judge-fsm ds)
  (define vs (match (read-view ds) [(list 'state s) s] [_ #f]))
  (define rd (read-cite ds))
  (define temporal
    (case vs
      [(started sub-started) (list 'temporal 'Fulfilled rd)]
      [(accepted delegating delegated released resumed) (list 'temporal 'Violated rd)]
      [else (list 'temporal 'Indeterminate '())]))
  (define continuity
    (case vs
      [(accepted delegating resumed started) (list 'continuity 'Fulfilled rd)]
      [(released) (list 'continuity 'Violated rd)]
      [else (list 'continuity 'Indeterminate '())]))
  (claims continuity temporal))

;; ---------------------------------------------------------------------------
;; COMM — retain protocol; START notice; read-back returns V's commitment
;; ledger (c1 = C(V, H, accepted, initiate care by DEADLINE), c2 = C(S, V,
;; delegated, initiate care)).
;;
;; ACCEPT creates and detaches c1 with H as creditor. DELEGATED is V's
;; delegation under retention: c1 goes pending while S's c2 is active and
;; reactivates if S declines; it is never dropped unless released. START is the
;; social event of care initiation and discharges the commitment. H judges c1
;; as the creditor holds it.
;;   temporal  — H saw c1 discharged (START asserted by DEADLINE, or the ledger
;;               shows c1 or c2 discharged): Fulfilled. Otherwise c1's deadline
;;               passed without H seeing it discharged: Violated.
;;   continuity — c1 was created and H holds no release or cancellation of it:
;;               someone (V, or S while c1 is pending under c2) owns it
;;               throughout: Fulfilled. The ledger shows c1 released, or c1
;;               pending with no active or discharged c2 to cover it: Violated.
(define (ledger-of ds)
  (match (read-view ds)
    [(list 'ledger c1 c2) (cons c1 c2)]
    [(list 'full _ c1 c2 _ _) (cons c1 c2)]
    [_ #f]))

(define (ownerless? c1 c2)
  (or (eq? c1 'released)
      (and (eq? c1 'pending) (not (memq c2 '(active discharged))))))

(define (judge-comm ds)
  (define acc (accept-idx ds))
  (define starts (msg-indices ds 'START #:asserted-by DEADLINE))
  (define led (ledger-of ds))
  (define rd (read-cite ds))
  (define led-discharged?
    (and led (or (eq? (car led) 'discharged) (eq? (cdr led) 'discharged))))
  (define temporal
    (cond [(pair? starts) (list 'temporal 'Fulfilled starts)]
          [led-discharged? (list 'temporal 'Fulfilled rd)]
          [(pair? acc) (list 'temporal 'Violated (append acc rd))]
          [else (list 'temporal 'Indeterminate '())]))
  (define continuity
    (cond [(and led (ownerless? (car led) (cdr led)))
           (list 'continuity 'Violated rd)]
          [(pair? acc) (list 'continuity 'Fulfilled (append acc rd))]
          [else (list 'continuity 'Indeterminate '())]))
  (claims continuity temporal))

;; ---------------------------------------------------------------------------
;; Shared reading of the full view for HYBRID and HYBRID-NOE.
;; (full vs c1 c2 stage as-of): V's state, both commitments, S's stage as
;; relayed in V's record, and the record's completeness watermark.

(define (full-of ds)
  (match (read-view ds)
    [(list 'full vs c1 c2 stage as-of) (list vs c1 c2 stage as-of)]
    [_ #f]))

(define (record-shows-start? f)
  (match-define (list vs c1 c2 stage _) f)
  (or (memq vs '(started sub-started))
      (eq? c1 'discharged) (eq? c2 'discharged) (eq? stage 'started)))

;; ---------------------------------------------------------------------------
;; HYBRID — retain protocol; START notice (performer's report), ATTEST
;; (independent attestation of care initiation), full view with watermark.
;;
;; Commitments as in COMM (c1 retained, suspended under S's c2, reactivated on
;; decline, never dropped), FSM records, and the evidentiary discipline:
;;   temporal  — E1: START and V's record of "started" / "sub-started" (S's
;;               start as relayed by V) are the performers' reports, not
;;               evidence. An ATTEST asserting initiation by DEADLINE is
;;               independent evidence: Fulfilled. E2: the record establishes
;;               the negative only if its watermark is at or after DEADLINE
;;               (the instant by which any timely start would be recorded),
;;               it shows no start, and no start report contradicts it:
;;               Violated. E3: otherwise Indeterminate.
;;   continuity — ownership is a commitment fact, not a performance report.
;;               ACCEPT created c1; the mechanism retains or assigns it
;;               explicitly and never drops it, so absent a recorded release
;;               it was owned throughout: Fulfilled. A record that contains a
;;               release, or c1 suspended with no S commitment covering it,
;;               proves an ownerless instant (a record proves what it
;;               contains, E2): Violated. The record is cited in support only
;;               when its watermark covers S's response (T-S-RESPONSE), where
;;               a gap could arise.
(define (judge-hybrid ds)
  (define acc (accept-idx ds))
  (define attests (msg-indices ds 'ATTEST #:asserted-by DEADLINE))
  (define starts (msg-indices ds 'START))
  (define f (full-of ds))
  (define rd (read-cite ds))
  (define temporal
    (cond [(pair? attests) (list 'temporal 'Fulfilled attests)]
          [(and f (>= (list-ref f 4) DEADLINE)
                (not (record-shows-start? f))
                (null? starts))
           (list 'temporal 'Violated rd)]
          [else (list 'temporal 'Indeterminate '())]))
  (define continuity
    (cond [(and f (ownerless? (list-ref f 1) (list-ref f 2)))
           (list 'continuity 'Violated rd)]
          [(pair? acc)
           (list 'continuity 'Fulfilled
                 (append acc (if (and f (>= (list-ref f 4) T-S-RESPONSE)) rd '())))]
          [else (list 'continuity 'Indeterminate '())]))
  (claims continuity temporal))

;; ---------------------------------------------------------------------------
;; HYBRID-NOE — the same mechanism and interface as HYBRID, without E1–E3.
;;
;; Reports count as evidence of what they report and every successful
;; read-back is authoritative; with no abstention rule, COMM's creditor rule
;; decides what remains open.
;;   temporal  — ATTEST or START asserting initiation by DEADLINE, or a record
;;               showing a start (V started, S started, c1/c2 discharged):
;;               Fulfilled. A record showing no start: care was not initiated
;;               (Violated). No record and no report: c1 was not seen
;;               discharged by its deadline (Violated).
;;   continuity — as HYBRID: the retained commitment was owned throughout
;;               (Fulfilled) unless the record shows it released or uncovered
;;               (Violated); any successful read is cited as authoritative.
(define (judge-hybrid-noe ds)
  (define acc (accept-idx ds))
  (define reports (append (msg-indices ds 'ATTEST #:asserted-by DEADLINE)
                          (msg-indices ds 'START #:asserted-by DEADLINE)))
  (define f (full-of ds))
  (define rd (read-cite ds))
  (define temporal
    (cond [(pair? reports) (list 'temporal 'Fulfilled reports)]
          [(and f (record-shows-start? f)) (list 'temporal 'Fulfilled rd)]
          [f (list 'temporal 'Violated rd)]
          [(pair? acc) (list 'temporal 'Violated acc)]
          [else (list 'temporal 'Indeterminate '())]))
  (define continuity
    (cond [(and f (ownerless? (list-ref f 1) (list-ref f 2)))
           (list 'continuity 'Violated rd)]
          [(pair? acc) (list 'continuity 'Fulfilled (append acc rd))]
          [else (list 'continuity 'Indeterminate '())]))
  (claims continuity temporal))

;; ---------------------------------------------------------------------------

(define arms
  (list
   (arm 'delegation 'chor
        (hasheq 'on-delegate 'release)
        (hasheq 'notice? #t 'attest? #f 'view 'last-message)
        judge-chor)
   (arm 'delegation 'fsm
        (hasheq 'on-delegate 'retain)
        (hasheq 'notice? #f 'attest? #f 'view 'state)
        judge-fsm)
   (arm 'delegation 'comm
        (hasheq 'on-delegate 'retain)
        (hasheq 'notice? #t 'attest? #f 'view 'ledger)
        judge-comm)
   (arm 'delegation 'hybrid
        (hasheq 'on-delegate 'retain)
        (hasheq 'notice? #t 'attest? #t 'view 'full)
        judge-hybrid)
   (arm 'delegation 'hybrid-noe
        (hasheq 'on-delegate 'retain)
        (hasheq 'notice? #t 'attest? #t 'view 'full)
        judge-hybrid-noe)))
