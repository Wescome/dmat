#lang racket/base
;; Family `composition` — independent arms (chor, fsm, comm, hybrid, hybrid-noe).
;;
;; H (the observer) orders a service from V; V subcontracts the first stage to
;; S and then assembles and delivers to H. Dependencies, in family order:
;;   temporal : S initiated its stage by DEADLINE (true time)
;;   delivery : V delivered the assembled result by T-EVAL
;; Deliveries to H: (msg DELIVERED 15 14), (msg ATTEST s+2 s) where the
;; interface defines an attestation, and a read-back of V's case record at
;; T-READ, whose view is (case cs) or (staged cs ss ot).

(require "../core/arm.rkt"
         "../core/observe.rkt"
         "../families/composition/terms.rkt")
(provide arms)

;; ---------------------------------------------------------------------------
;; Shared reading of deliveries (no inference, only parsing)

;; index of the read-back delivery (read-ok or read-failed), or #f
(define (any-read-index ds)
  (for/first ([d ds] [i (in-naturals)]
              #:when (memq (car d) '(read-ok read-failed)))
    i))

;; case status from either view form: 'open, 'closed, or #f
(define (view-case v)
  (and (pair? v)
       (case (car v)
         [(case staged) (and (pair? (cdr v)) (memq (cadr v) '(open closed)) (cadr v))]
         [else #f])))

;; S's stage as relayed by V (staged view only): (cons ss ot), or #f
(define (view-stage v)
  (and (pair? v) (eq? (car v) 'staged) (= (length v) 4)
       (cons (caddr v) (cadddr v))))

;; first DELIVERED message that arrived by T-EVAL
(define (delivered-index ds)
  (let ([is (msg-indices ds 'DELIVERED #:arrived-by T-EVAL)])
    (and (pair? is) (car is))))

;; first ATTEST message that arrived by T-EVAL, and the start instant it attests
(define (attest-index ds)
  (let ([is (msg-indices ds 'ATTEST #:arrived-by T-EVAL)])
    (and (pair? is) (car is))))
(define (attested-start ds i) (msg-asserted (list-ref ds i)))

(define (cite i) (if i (list i) '()))

;; ---------------------------------------------------------------------------
;; CHOR
;; The global type: H→V order; V→S subcontract; S→V start; V→H DELIVERED,
;; with a timed branch on H's side if DELIVERED has not arrived by T-EVAL; and,
;; where the global type defines it, an ATTEST message to H naming S's start.
;; H's local session is the projection on H: DELIVERED, ATTEST (if any), and
;; the read-back of V's session log toward H — the case status, V's last word
;; to H (closed = V sent DELIVERED, open = it did not).
;; temporal: S's start is an event of the V–S session, outside H's projection.
;;   The S-stage fields of a staged record are V's log of that other session,
;;   so H's projection does not contain them. Only an ATTEST message in H's
;;   own session names the start: a message is the event it names, so its
;;   asserted instant ≤ DEADLINE is Fulfilled, later is Violated. With no
;;   ATTEST, Indeterminate.
;; delivery: DELIVERED arrived → Fulfilled. Else the counterpart's log says
;;   closed → V sent DELIVERED → Fulfilled. Else the awaited message has not
;;   arrived by T-EVAL, so H's session takes the timed branch → Violated
;;   (the session has no notion of a lost message versus one never sent).
(define (chor-judge ds)
  (define ai (attest-index ds))
  (define temporal
    (if ai
        (list 'temporal
              (if (<= (attested-start ds ai) DEADLINE) 'Fulfilled 'Violated)
              (list ai))
        (list 'temporal 'Indeterminate '())))
  (define di (delivered-index ds))
  (define ri (any-read-index ds))
  (define cs (view-case (read-view ds)))
  (define delivery
    (cond [di (list 'delivery 'Fulfilled (list di))]
          [(eq? cs 'closed) (list 'delivery 'Fulfilled (list (read-index ds)))]
          [else (list 'delivery 'Violated (cite ri))]))
  (claims temporal delivery))

;; ---------------------------------------------------------------------------
;; FSM
;; V runs a case machine OPEN → CLOSED (on delivery); where V's record is
;; staged, it also holds S's stage machine as last set by S's reports:
;; NONE → COMMITTED → STARTED@ot, or DECLINED. H runs ORDERED → RECEIVED on
;; DELIVERED, ORDERED → OVERDUE on its own timeout at T-EVAL, and may track
;; S-STARTED@s on an ATTEST message where one is defined.
;; The read record is authoritative and current: the machine is in the state
;; it records.
;; temporal: record STARTED with ot ≤ DEADLINE → Fulfilled; STARTED later,
;;   DECLINED, COMMITTED or NONE (at T-READ, after DEADLINE) → S's machine did
;;   not reach STARTED by DEADLINE → Violated. With no S state in the record
;;   (coarse view or failed read), H's own machine: S-STARTED@s from ATTEST
;;   → by s; otherwise H holds no state of S → Indeterminate.
;; delivery: record CLOSED → Fulfilled; OPEN → Violated. Failed read: H's own
;;   machine — RECEIVED (DELIVERED arrived) → Fulfilled; else the timeout on
;;   H's clock moves it to OVERDUE → Violated.
(define (fsm-judge ds)
  (define ri (read-index ds))
  (define v (read-view ds))
  (define stage (view-stage v))
  (define ai (attest-index ds))
  (define temporal
    (cond [stage
           (define ss (car stage))
           (define ot (cdr stage))
           (if (and (eq? ss 'started) (exact-nonnegative-integer? ot) (<= ot DEADLINE))
               (list 'temporal 'Fulfilled (list ri))
               (list 'temporal 'Violated (list ri)))]
          [ai (list 'temporal
                    (if (<= (attested-start ds ai) DEADLINE) 'Fulfilled 'Violated)
                    (list ai))]
          [else (list 'temporal 'Indeterminate '())]))
  (define cs (view-case v))
  (define di (delivered-index ds))
  (define delivery
    (cond [(eq? cs 'closed) (list 'delivery 'Fulfilled (list ri))]
          [(eq? cs 'open) (list 'delivery 'Violated (list ri))]
          [di (list 'delivery 'Fulfilled (list di))]
          [else (list 'delivery 'Violated (cite (any-read-index ds)))]))
  (claims temporal delivery))

;; ---------------------------------------------------------------------------
;; COMM
;; Commitments: C(V, H, ordered, delivered by T-EVAL), held by H as creditor;
;; and C(S, V, subcontracted, started by DEADLINE), held by V as creditor and
;; visible to H only through V's ledger (the staged view) or through an ATTEST
;; message, a social event that records the discharge of S's commitment.
;; temporal: ATTEST at s → discharged at s: s ≤ DEADLINE → Fulfilled, later →
;;   violated (deadline passed undischarged). Else V's ledger: started with
;;   ot ≤ DEADLINE → discharged → Fulfilled; started later, committed or none
;;   at T-READ → its creditor V does not see it discharged by DEADLINE →
;;   Violated; declined → the stage was never undertaken → Violated. With no
;;   ledger entry for S (coarse view or failed read), H holds no commitment
;;   about S's start → Indeterminate.
;; delivery: DELIVERED arrived → H sees C(V,H,…) discharged → Fulfilled; the
;;   ledger shows closed (discharged) → Fulfilled. Otherwise H, the creditor,
;;   cannot see it discharged by T-EVAL → Violated.
(define (comm-judge ds)
  (define ri (read-index ds))
  (define v (read-view ds))
  (define stage (view-stage v))
  (define ai (attest-index ds))
  (define temporal
    (cond [ai (list 'temporal
                    (if (<= (attested-start ds ai) DEADLINE) 'Fulfilled 'Violated)
                    (list ai))]
          [stage
           (define ss (car stage))
           (define ot (cdr stage))
           (if (and (eq? ss 'started) (exact-nonnegative-integer? ot) (<= ot DEADLINE))
               (list 'temporal 'Fulfilled (list ri))
               (list 'temporal 'Violated (list ri)))]
          [else (list 'temporal 'Indeterminate '())]))
  (define di (delivered-index ds))
  (define cs (view-case v))
  (define delivery
    (cond [di (list 'delivery 'Fulfilled (list di))]
          [(eq? cs 'closed) (list 'delivery 'Fulfilled (list ri))]
          [else (list 'delivery 'Violated (cite (any-read-index ds)))]))
  (claims temporal delivery))

;; ---------------------------------------------------------------------------
;; HYBRID
;; COMM's commitments with V retaining responsibility to H for the whole
;; service (S's stage is V's subcontract, not a commitment H holds of S), FSM
;; records for V's case and S's stage, and the evidentiary rules E1–E3.
;; Evidence available to H: ATTEST — an independent attestation of S's start
;; by a party other than S; DELIVERED — the delivery arriving at H, which H
;; itself receives (H's own receipt, not a report about a remote event).
;; V's case record and S's relayed stage are self-reports (V's record of its
;; own case; S's report of its own stage). The view carries no completeness
;; watermark, so under E2 the record proves only what it contains, not what
;; it omits.
;; temporal: ATTEST at s → s ≤ DEADLINE Fulfilled, else Violated (independent
;;   evidence either way). Without it: S's report started@ot ≤ DEADLINE is S's
;;   report of its own performance — not evidence (E1) → Indeterminate. S's
;;   report started@ot > DEADLINE or declined is S's own report NOT to have
;;   performed by the deadline → establishes the negative → Violated. A record
;;   still at none/committed shows no start, but with no watermark it cannot
;;   prove the omission (E2) → Indeterminate. A missing ATTEST may be a drop,
;;   so its absence proves nothing (E3).
;; delivery: DELIVERED received by H → Fulfilled. Else V's record closed is
;;   V's own entry asserting its performance → not evidence (E1); open is the
;;   absence of a closing entry in a record without a watermark → not proof of
;;   non-delivery (E2); failed read or missing DELIVERED (may be dropped)
;;   → Indeterminate (E3).
(define (hybrid-judge ds)
  (define ri (read-index ds))
  (define stage (view-stage (read-view ds)))
  (define ai (attest-index ds))
  (define temporal
    (cond [ai (list 'temporal
                    (if (<= (attested-start ds ai) DEADLINE) 'Fulfilled 'Violated)
                    (list ai))]
          [stage
           (define ss (car stage))
           (define ot (cdr stage))
           (cond [(eq? ss 'declined) (list 'temporal 'Violated (list ri))]
                 [(and (eq? ss 'started) (exact-nonnegative-integer? ot) (> ot DEADLINE))
                  (list 'temporal 'Violated (list ri))]
                 [else (list 'temporal 'Indeterminate '())])]
          [else (list 'temporal 'Indeterminate '())]))
  (define di (delivered-index ds))
  (define delivery
    (if di
        (list 'delivery 'Fulfilled (list di))
        (list 'delivery 'Indeterminate '())))
  (claims temporal delivery))

;; ---------------------------------------------------------------------------
;; HYBRID-NOE
;; The same commitments, records and messages as HYBRID, with E1–E3 removed:
;; S's and V's reports count as evidence of what they report, and a successful
;; read-back is authoritative. COMM's creditor rule is back in force for the
;; commitment H holds (V's delivery).
;; temporal: ATTEST at s → by s (checked first, as in HYBRID). Else V's record
;;   of S's stage, taken as true: started with ot ≤ DEADLINE → Fulfilled;
;;   started later, declined, committed or none at T-READ → Violated. With no
;;   S stage in the record (coarse view or failed read) → nothing about S's
;;   start → Indeterminate.
;; delivery: DELIVERED → Fulfilled; record closed → Fulfilled; record open →
;;   Violated. Failed read and no DELIVERED → H, the creditor, cannot see the
;;   commitment discharged by T-EVAL → Violated.
(define (hybrid-noe-judge ds)
  (define ri (read-index ds))
  (define v (read-view ds))
  (define stage (view-stage v))
  (define ai (attest-index ds))
  (define temporal
    (cond [ai (list 'temporal
                    (if (<= (attested-start ds ai) DEADLINE) 'Fulfilled 'Violated)
                    (list ai))]
          [stage
           (define ss (car stage))
           (define ot (cdr stage))
           (if (and (eq? ss 'started) (exact-nonnegative-integer? ot) (<= ot DEADLINE))
               (list 'temporal 'Fulfilled (list ri))
               (list 'temporal 'Violated (list ri)))]
          [else (list 'temporal 'Indeterminate '())]))
  (define di (delivered-index ds))
  (define cs (view-case v))
  (define delivery
    (cond [di (list 'delivery 'Fulfilled (list di))]
          [(eq? cs 'closed) (list 'delivery 'Fulfilled (list ri))]
          [(eq? cs 'open) (list 'delivery 'Violated (list ri))]
          [else (list 'delivery 'Violated (cite (any-read-index ds)))]))
  (claims temporal delivery))

;; ---------------------------------------------------------------------------

(define arms
  (list
   (arm 'composition 'chor (hasheq) (hasheq 'obs 'coarse 'attest? #f) chor-judge)
   (arm 'composition 'fsm (hasheq) (hasheq 'obs 'coarse 'attest? #f) fsm-judge)
   (arm 'composition 'comm (hasheq) (hasheq 'obs 'coarse 'attest? #f) comm-judge)
   (arm 'composition 'hybrid (hasheq) (hasheq 'obs 'staged 'attest? #t) hybrid-judge)
   (arm 'composition 'hybrid-noe (hasheq) (hasheq 'obs 'staged 'attest? #t) hybrid-noe-judge)))
