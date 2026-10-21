#lang racket/base
;; Independent arms for family `deadline` — deadline-bound service (Temporal, Flow).
;;
;; Provider V owes H a service by DEADLINE. H (the observer) may receive:
;;   (msg DONE arrival stamp)      V's completion report, stamped on V's own clock
;;   (msg ATTEST arrival stamp)    a trusted third party's attestation, stamped with
;;                                 the true completion instant (only if 'attest? #t)
;;   (read-ok T-READ (record ot))  V's completion record (ot = V's stamp, or #f)
;;   (read-failed T-READ)
;; Dependencies, in order: temporal (completed by DEADLINE), completion (completed
;; by T-EVAL).

(require "../core/arm.rkt"
         "../core/observe.rkt"
         "../families/deadline/terms.rkt")
(provide arms)

;; ---------------------------------------------------------------------------
;; Small helpers over H's deliveries.

;; first (index . delivery) of message kind M, or #f
(define (first-msg ds M)
  (define ms (msgs ds M))
  (and (pair? ms) (car ms)))

;; Index of the read-back delivery, ok or failed, or #f. When nothing else was
;; delivered, it is the delivery that marks H's observation through T-READ with
;; no completion report, and is cited for a negative judgment.
(define (read-delivery-index ds)
  (for/first ([d ds] [i (in-naturals)]
              #:when (memq (car d) '(read-ok read-failed)))
    i))
(define (opt i) (if i (list i) '()))

;; The read-back: (values index ot present?) where present? says whether a
;; read-ok with a well-formed (record ot) view was delivered.
(define (record-of ds)
  (define i (read-index ds))
  (define v (read-view ds))
  (if (and i (pair? v) (eq? (car v) 'record) (pair? (cdr v)))
      (values i (cadr v) #t)
      (values i #f #f)))

;; ---------------------------------------------------------------------------
;; CHOR — global type:  V → H : DONE  within DEADLINE  (else timeout branch).
;; H's projection awaits DONE with a timed branch at DEADLINE. In a choreography
;; a message is the event it names, and a timed branch fires on *arrival*: if
;; DONE arrived by DEADLINE the session took the in-time branch (temporal
;; Fulfilled); if it arrived later, or never, the timeout branch fired at
;; DEADLINE (temporal Violated). Completion: DONE in H's session is completion
;; (Fulfilled). Without DONE, the only other view is the read-back of V's
;; session log at T-READ: a log with no completion message shows V never sent
;; it (Violated); if the read-back failed, whether V completed after the
;; session timed out lies outside H's projection (Indeterminate). V's clock
;; stamp is not a session event and is not used.
(define (chor-judge ds)
  (define done (first-msg ds 'DONE))
  (define-values (ri ot rec?) (record-of ds))
  (define temporal
    (cond [(and done (<= (msg-arrival (cdr done)) DEADLINE))
           (list 'temporal 'Fulfilled (list (car done)))]
          [done (list 'temporal 'Violated (list (car done)))]
          [else (list 'temporal 'Violated (opt (read-delivery-index ds)))]))
  (define completion
    (cond [done (list 'completion 'Fulfilled (list (car done)))]
          [(and rec? (not ot)) (list 'completion 'Violated (list ri))]
          [rec? (list 'completion 'Fulfilled (list ri))]
          [else (list 'completion 'Indeterminate '())]))
  (claims temporal completion))

;; ---------------------------------------------------------------------------
;; FSM — V runs  working --complete/stamp--> done ; H runs
;; awaiting --DONE(stamp)--> received, awaiting --timeout DEADLINE--> overdue.
;; The authoritative fact is V's recorded state, read back at T-READ: state
;; `done` with transition stamp ot ≤ DEADLINE means completed in time
;; (temporal Fulfilled, completion Fulfilled); `done` at ot > DEADLINE means
;; late (temporal Violated, completion Fulfilled); no completion recorded means
;; V is still `working` (both Violated). The record is trusted as current and
;; its stamp as the transition instant. If the read-back failed, H falls back
;; on its own machine: DONE carries V's transition and its stamp, judged the
;; same way; if no DONE was received, H's machine sits in `overdue` and never
;; reached `received` (both Violated).
(define (fsm-judge ds)
  (define done (first-msg ds 'DONE))
  (define-values (ri ot rec?) (record-of ds))
  (define-values (stamp cite)
    (cond [rec? (values ot (list ri))]
          [done (values (msg-asserted (cdr done)) (list (car done)))]
          [else (values #f (opt (read-delivery-index ds)))]))
  (claims
   (list 'temporal (if (and stamp (<= stamp DEADLINE)) 'Fulfilled 'Violated) cite)
   (list 'completion (if stamp 'Fulfilled 'Violated) cite)))

;; ---------------------------------------------------------------------------
;; COMM — V is debtor of two unconditional commitments to creditor H:
;;   C_t(V, H, ⊤, service done by DEADLINE)   and   C_c(V, H, ⊤, service done by T-EVAL).
;; DONE is the social event that discharges them as H holds them. The judgment
;; is the commitment's state from H's side: C_t is discharged only if H saw
;; DONE by DEADLINE (Fulfilled); otherwise H could not see it discharged by its
;; deadline and it is violated (Violated). C_c is discharged by any DONE H
;; received by T-EVAL (Fulfilled), else violated (Violated). V's own ledger,
;; read back at T-READ, can discharge C_c if it records completion; a violation
;; with no DONE at all cites the read-back delivery (H's observation through
;; T-READ with no discharge).
(define (comm-judge ds)
  (define-values (ri ot rec?) (record-of ds))
  (define in-time (msg-indices ds 'DONE #:arrived-by DEADLINE))
  (define by-eval (msg-indices ds 'DONE #:arrived-by T-EVAL))
  (define all-done (msg-indices ds 'DONE))
  (define neg-cite (opt (read-delivery-index ds)))
  (claims
   (if (pair? in-time)
       (list 'temporal 'Fulfilled in-time)
       (list 'temporal 'Violated (if (pair? all-done) all-done neg-cite)))
   (cond [(pair? by-eval) (list 'completion 'Fulfilled by-eval)]
         [(and rec? ot) (list 'completion 'Fulfilled (list ri))]
         [else (list 'completion 'Violated neg-cite)])))

;; ---------------------------------------------------------------------------
;; HYBRID — the COMM commitments C_t, C_c with an FSM record of V, under the
;; evidentiary discipline. The trusted ATTEST is independent evidence (E1): its
;; stamp is the true completion instant, so stamp ≤ DEADLINE discharges C_t
;; (Fulfilled) and stamp > DEADLINE shows C_t violated (Violated); any ATTEST
;; discharges C_c (Fulfilled). DONE and a record showing completion are V's
;; own reports of performance on V's own clock — not evidence (E1), so they
;; never support Fulfilled, and V's stamp cannot place the completion in time.
;; V's record at T-READ *not* showing completion is V's own report not to have
;; performed, which may establish the negative (E1): not completed by T-READ,
;; hence not by DEADLINE (Violated), and — the protocol's last completion and
;; report precede T-READ — not by T-EVAL (Violated). The view carries no
;; completeness watermark (E2), so a record is never used to prove an omission
;; beyond that explicit report. Otherwise (attestation dropped, only V's
;; reports, or no read-back) the truth is open: Indeterminate (E3).
(define (hybrid-judge ds)
  (define att (first-msg ds 'ATTEST))
  (define-values (ri ot rec?) (record-of ds))
  (cond
    [att
     (define s (msg-asserted (cdr att)))
     (claims (list 'temporal (if (<= s DEADLINE) 'Fulfilled 'Violated) (list (car att)))
             (list 'completion (if (<= s T-EVAL) 'Fulfilled 'Violated) (list (car att))))]
    [(and rec? (not ot))
     (claims (list 'temporal 'Violated (list ri))
             (list 'completion 'Violated (list ri)))]
    [else
     (claims (list 'temporal 'Indeterminate '())
             (list 'completion 'Indeterminate '()))]))

;; ---------------------------------------------------------------------------
;; HYBRID-NOE — the same commitments, record and attestation, without E1–E3.
;; Evidence in order of authority: the trusted ATTEST (its stamp is the
;; completion instant); else V's record read back at T-READ, authoritative as
;; read (its stamp is taken as the completion instant; no completion recorded
;; means not done); else V's DONE report, taken at its word (its stamp is the
;; completion instant). Stamp ≤ DEADLINE discharges C_t (Fulfilled), later
;; violates it (Violated); any completion discharges C_c (Fulfilled). With no
;; attestation, no report and no record, H never saw either commitment
;; discharged, so both are violated (Violated), as in COMM.
(define (hybrid-noe-judge ds)
  (define att (first-msg ds 'ATTEST))
  (define done (first-msg ds 'DONE))
  (define-values (ri ot rec?) (record-of ds))
  (define-values (stamp cite)
    (cond [att (values (msg-asserted (cdr att)) (list (car att)))]
          [rec? (values ot (list ri))]
          [done (values (msg-asserted (cdr done)) (list (car done)))]
          [else (values #f (opt (read-delivery-index ds)))]))
  (claims
   (list 'temporal (if (and stamp (<= stamp DEADLINE)) 'Fulfilled 'Violated) cite)
   (list 'completion (if (and stamp (<= stamp T-EVAL)) 'Fulfilled 'Violated) cite)))

;; ---------------------------------------------------------------------------

(define arms
  (list
   (arm 'deadline 'chor       (hasheq) (hasheq 'attest? #f) chor-judge)
   (arm 'deadline 'fsm        (hasheq) (hasheq 'attest? #f) fsm-judge)
   (arm 'deadline 'comm       (hasheq) (hasheq 'attest? #f) comm-judge)
   (arm 'deadline 'hybrid     (hasheq) (hasheq 'attest? #t) hybrid-judge)
   (arm 'deadline 'hybrid-noe (hasheq) (hasheq 'attest? #t) hybrid-noe-judge)))
