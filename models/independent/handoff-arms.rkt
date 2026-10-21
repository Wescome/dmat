#lang racket/base
;; Family `handoff` — five independently written arms.
;;
;; Hospital H refers a patient to home-care provider V at instant 0. H is the
;; observer. Dependencies, in order:
;;   flow     — V accepted the referral by ACCEPT-DEADLINE
;;   temporal — care was initiated by DEADLINE
;; Every judge runs after T-EVAL, when both deadlines have passed, so no judge
;; ever answers Pending.

(require racket/list
         "../core/arm.rkt"
         "../core/observe.rkt"
         "../families/handoff/terms.rkt")
(provide arms)

;; ---------------------------------------------------------------------------
;; Small shared helpers (pure, over deliveries only)

;; the view of the read-back, or #f when it failed or is absent
(define (view-of ds) (read-view ds))
(define (view-kind v) (and (pair? v) (car v)))
(define (rd ds) (let ([i (read-index ds)]) (if i (list i) '())))

;; ---------------------------------------------------------------------------
;; CHOR
;;
;; The mechanism is a global type  H→V: Refer ;  V→H: Accept (timed: must
;; ARRIVE by ACCEPT-DEADLINE) ;  V→H: Start (timed: must ARRIVE by DEADLINE).
;; H runs its projection. H holds its local session (the ACCEPT and START
;; messages it received, in order) and a read-back of V's session log, which
;; shows V's last message.
;;  flow:     if an ACCEPT arrived by ACCEPT-DEADLINE the session took the
;;            accept branch: Fulfilled. Otherwise the timed branch fired at
;;            ACCEPT-DEADLINE: Violated (a later ACCEPT is outside the session).
;;  temporal: a message is the event it names, so a START in H's session or
;;            START as V's last logged message means care started: Fulfilled.
;;            If the session is in the accept branch and no START arrived by
;;            DEADLINE, the timed branch fired: Violated. If the session left
;;            through the accept timeout, it has ended and care is a fact
;;            outside H's projection: Indeterminate.
(define (chor-judge ds)
  (define acc-in-time (msg-indices ds 'ACCEPT #:arrived-by ACCEPT-DEADLINE))
  (define acc-late (msg-indices ds 'ACCEPT #:where (λ (d) (> (msg-arrival d) ACCEPT-DEADLINE))))
  (define v (view-of ds))
  (define lm (and v (eq? (view-kind v) 'last-message) (cadr v)))
  (define flow
    (if (pair? acc-in-time)
        (list 'flow 'Fulfilled acc-in-time)
        (list 'flow 'Violated
              (append acc-late (if (eq? lm 'none) (rd ds) '())))))
  (define starts (msg-indices ds 'START #:arrived-by DEADLINE #:asserted-by DEADLINE))
  (define log-start? (and (pair? lm) (eq? (car lm) 'START) (<= (cadr lm) DEADLINE)))
  (define temporal
    (cond [(or (pair? starts) log-start?)
           (list 'temporal 'Fulfilled (append starts (if log-start? (rd ds) '())))]
          [(pair? acc-in-time)
           (list 'temporal 'Violated
                 (append acc-in-time
                         (if (and (pair? lm) (eq? (car lm) 'ACCEPT)) (rd ds) '())))]
          [else (list 'temporal 'Indeterminate '())]))
  (claims flow temporal))

;; ---------------------------------------------------------------------------
;; FSM
;;
;; H runs a machine  referred --ACCEPT--> handed-off, with a timeout on H's own
;; clock at ACCEPT-DEADLINE: referred --timeout--> overdue. V runs
;; referred → accepted → started and keeps its current state in a record that
;; H reads at T-READ. The record is authoritative: V is in the state it shows.
;;  flow:     H's own state. ACCEPT received by ACCEPT-DEADLINE → handed-off →
;;            Fulfilled; otherwise the timeout put H in overdue → Violated.
;;  temporal: V's recorded state, read after DEADLINE. started → Fulfilled;
;;            accepted or referred → V is not in started after the deadline →
;;            Violated. No state read → Indeterminate.
(define (fsm-judge ds)
  (define acc-in-time (msg-indices ds 'ACCEPT #:arrived-by ACCEPT-DEADLINE))
  (define acc-late (msg-indices ds 'ACCEPT #:where (λ (d) (> (msg-arrival d) ACCEPT-DEADLINE))))
  (define v (view-of ds))
  (define S (and v (eq? (view-kind v) 'state) (cadr v)))
  (define flow
    (if (pair? acc-in-time)
        (list 'flow 'Fulfilled acc-in-time)
        (list 'flow 'Violated (append acc-late (if (eq? S 'referred) (rd ds) '())))))
  (define temporal
    (case S
      [(started) (list 'temporal 'Fulfilled (rd ds))]
      [(accepted referred) (list 'temporal 'Violated (rd ds))]
      [else (list 'temporal 'Indeterminate '())]))
  (claims flow temporal))

;; ---------------------------------------------------------------------------
;; COMM
;;
;; Two commitments, held by H as creditor:
;;   c0 = C(V, H, referred, accept by ACCEPT-DEADLINE) — detached at 0
;;   c1 = C(V, H, accepted, initiate care by DEADLINE)
;; ACCEPT is the social event of acceptance at its asserted instant: it
;; discharges c0 if at or before ACCEPT-DEADLINE, and detaches c1. START is the
;; social event of initiating care: it discharges c1. The read-back is V's
;; commitment ledger.
;;  flow:     c0 seen discharged (ACCEPT asserted by the deadline, or ledger
;;            c0 = discharged) → Fulfilled. Otherwise H cannot see c0
;;            discharged by its deadline → Violated.
;;  temporal: c1 seen discharged (START asserted by DEADLINE, or ledger c1 =
;;            discharged) → Fulfilled. c1 detached (some acceptance seen) and
;;            not seen discharged → Violated. c1 never detached: it expired as
;;            a conditional commitment, no obligation about care ever bound V,
;;            so H's commitment state says nothing about care → Indeterminate.
(define (comm-judge ds)
  (define acc-ok (msg-indices ds 'ACCEPT #:asserted-by ACCEPT-DEADLINE))
  (define acc-all (msg-indices ds 'ACCEPT))
  (define acc-late (msg-indices ds 'ACCEPT #:where (λ (d) (> (msg-asserted d) ACCEPT-DEADLINE))))
  (define v (view-of ds))
  (define ledger? (and v (eq? (view-kind v) 'ledger)))
  (define c0 (and ledger? (cadr v)))
  (define c1 (and ledger? (caddr v)))
  (define flow
    (cond [(or (pair? acc-ok) (eq? c0 'discharged))
           (list 'flow 'Fulfilled (append acc-ok (if (eq? c0 'discharged) (rd ds) '())))]
          [else
           (list 'flow 'Violated
                 (append acc-late (if (memq c0 '(none late-discharged)) (rd ds) '())))]))
  (define starts (msg-indices ds 'START #:asserted-by DEADLINE))
  (define detached?
    (or (pair? acc-all)
        (memq c0 '(discharged late-discharged))
        (memq c1 '(detached discharged))))
  (define temporal
    (cond [(or (pair? starts) (eq? c1 'discharged))
           (list 'temporal 'Fulfilled (append starts (if (eq? c1 'discharged) (rd ds) '())))]
          [detached?
           (list 'temporal 'Violated
                 (append acc-all (if (and ledger? (not (eq? c0 'none))) (rd ds) '())))]
          [else (list 'temporal 'Indeterminate '())]))
  (claims flow temporal))

;; ---------------------------------------------------------------------------
;; HYBRID (shared reading of the full record)

;; (full S oat ost c0 c1 wm) → its fields, or #f
(define (full-of ds)
  (define v (view-of ds))
  (and v (eq? (view-kind v) 'full) (cdr v)))
(define (full-oat f) (list-ref f 1))
(define (full-ost f) (list-ref f 2))
(define (full-wm f) (list-ref f 5))

;; HYBRID
;;
;; COMM's two commitments, with V's record (state, recorded acceptance and
;; start instants, ledger, completeness watermark) as the FSM record, an
;; independent attester whose ATTEST confirms care was initiated, and E1–E3.
;;  flow:     acceptance is V's commitment-creating act, not a report of
;;            performance: an ACCEPT asserting acceptance by ACCEPT-DEADLINE,
;;            or a recorded acceptance instant by the deadline → Fulfilled.
;;            An ACCEPT, or a recorded acceptance, after the deadline is V's own
;;            statement that it had not accepted in time → Violated. A record
;;            with no acceptance whose watermark is at or after ACCEPT-DEADLINE
;;            (when an acceptance would have been recorded) is complete for
;;            the question (E2) → Violated. Otherwise (no ACCEPT — it may have
;;            been dropped — and no read, or a record not complete through the
;;            deadline) → Indeterminate (E3).
;;  temporal: initiating care is a performance. V's START notice and V's
;;            recorded start are V's reports and are not evidence (E1); only
;;            the independent ATTEST of a start by DEADLINE → Fulfilled. A
;;            negative needs V's record complete (E2) through DEADLINE and not
;;            showing a start → Violated. Otherwise → Indeterminate (E3); in
;;            particular a missing ATTEST is not evidence, as it may be dropped.
(define (hybrid-judge ds)
  (define acc-ok (msg-indices ds 'ACCEPT #:asserted-by ACCEPT-DEADLINE))
  (define acc-late (msg-indices ds 'ACCEPT #:where (λ (d) (> (msg-asserted d) ACCEPT-DEADLINE))))
  (define f (full-of ds))
  (define oat (and f (full-oat f)))
  (define ost (and f (full-ost f)))
  (define wm (and f (full-wm f)))
  (define flow
    (cond [(or (pair? acc-ok) (and oat (<= oat ACCEPT-DEADLINE)))
           (list 'flow 'Fulfilled
                 (append acc-ok (if (and oat (<= oat ACCEPT-DEADLINE)) (rd ds) '())))]
          [(or (pair? acc-late) (and oat (> oat ACCEPT-DEADLINE)))
           (list 'flow 'Violated
                 (append acc-late (if (and oat (> oat ACCEPT-DEADLINE)) (rd ds) '())))]
          [(and f (not oat) (>= wm ACCEPT-DEADLINE))
           (list 'flow 'Violated (rd ds))]
          [else (list 'flow 'Indeterminate '())]))
  (define attests (msg-indices ds 'ATTEST #:asserted-by DEADLINE))
  (define temporal
    (cond [(pair? attests) (list 'temporal 'Fulfilled attests)]
          [(and f (not ost) (>= wm DEADLINE)) (list 'temporal 'Violated (rd ds))]
          [else (list 'temporal 'Indeterminate '())]))
  (claims flow temporal))

;; HYBRID-NOE
;;
;; The same commitments, record and attester as HYBRID, without E1–E3: V's
;; reports count as evidence of what they report, and any successful read-back
;; of V's record is authoritative whatever its watermark.
;;  flow:     an ACCEPT asserted by ACCEPT-DEADLINE, or a recorded acceptance
;;            by the deadline → Fulfilled. Otherwise c0 is not seen discharged
;;            by its deadline → Violated (citing a late ACCEPT or the record).
;;  temporal: ATTEST, V's START notice, or a recorded start by DEADLINE →
;;            Fulfilled. c1 detached (an acceptance seen in a message or the
;;            record) and no start seen → Violated. A record read back showing
;;            no start is authoritative → Violated. With no acceptance seen and
;;            no record, c1 never detached and nothing bears on care →
;;            Indeterminate.
(define (hybrid-noe-judge ds)
  (define acc-ok (msg-indices ds 'ACCEPT #:asserted-by ACCEPT-DEADLINE))
  (define acc-all (msg-indices ds 'ACCEPT))
  (define acc-late (msg-indices ds 'ACCEPT #:where (λ (d) (> (msg-asserted d) ACCEPT-DEADLINE))))
  (define f (full-of ds))
  (define oat (and f (full-oat f)))
  (define ost (and f (full-ost f)))
  (define flow
    (cond [(or (pair? acc-ok) (and oat (<= oat ACCEPT-DEADLINE)))
           (list 'flow 'Fulfilled
                 (append acc-ok (if (and oat (<= oat ACCEPT-DEADLINE)) (rd ds) '())))]
          [else (list 'flow 'Violated (append acc-late (rd ds)))]))
  (define attests (msg-indices ds 'ATTEST #:asserted-by DEADLINE))
  (define starts (msg-indices ds 'START #:asserted-by DEADLINE))
  (define rec-start? (and ost (<= ost DEADLINE)))
  (define temporal
    (cond [(or (pair? attests) (pair? starts) rec-start?)
           (list 'temporal 'Fulfilled (append attests starts (if rec-start? (rd ds) '())))]
          [(or (pair? acc-all) f)
           (list 'temporal 'Violated (append acc-all (rd ds)))]
          [else (list 'temporal 'Indeterminate '())]))
  (claims flow temporal))

;; ---------------------------------------------------------------------------

(define arms
  (list
   (arm 'handoff 'chor (hasheq)
        (hasheq 'notice? #t 'attest? #f 'view 'last-message) chor-judge)
   (arm 'handoff 'fsm (hasheq)
        (hasheq 'notice? #f 'attest? #f 'view 'state) fsm-judge)
   (arm 'handoff 'comm (hasheq)
        (hasheq 'notice? #t 'attest? #f 'view 'ledger) comm-judge)
   (arm 'handoff 'hybrid (hasheq)
        (hasheq 'notice? #t 'attest? #t 'view 'full) hybrid-judge)
   (arm 'handoff 'hybrid-noe (hasheq)
        (hasheq 'notice? #t 'attest? #t 'view 'full) hybrid-noe-judge)))
