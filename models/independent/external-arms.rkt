#lang racket/base
;; Family `external` — partial external execution (Flow, Flow).
;; Independent arms: chor, fsm, comm, hybrid, hybrid-noe.
;;
;; H (the observer) orders a two-part service from V. V performs part A itself
;; (T-A); at T-DISPATCH it dispatches part B to an external executor X that is
;; not a participant in the H–V protocol. V sends DONE (conditioned on A only,
;; or premature). Where the interface defines it, X's signed outcome reaches H
;; as RECEIPT and V's record relays it in a `full` view with a watermark.
;;   internal : part A performed
;;   external : part B performed in full (partial counts as violated)

(require racket/list
         "../core/arm.rkt"
         "../core/observe.rkt"
         "../families/external/terms.rkt")
(provide arms)

;; ---------------------------------------------------------------------------
;; Shared accessors over H's deliveries.

;; DONE messages that arrived by the evaluation instant.
(define (done-indices ds) (msg-indices ds 'DONE #:arrived-by T-EVAL))

;; RECEIPT messages reporting outcome xs.
(define (receipt-indices ds xs)
  (msg-indices ds 'RECEIPT #:arrived-by T-EVAL
               #:where (λ (d) (equal? (msg-payload d) (list xs)))))

;; index of the read-back delivery, successful or failed (or #f).
(define (read-any-index ds)
  (for/first ([d ds] [i (in-naturals)]
              #:when (memq (car d) '(read-ok read-failed)))
    i))

(define (cites-of . xs) (filter values (flatten xs)))

;; View destructuring. Views: (record as) or (full as xs wm).
(define (view-as v)
  (and (pair? v) (memq (car v) '(record full)) (pair? (cdr v)) (cadr v)))
(define (full-xs v)
  (and (pair? v) (eq? (car v) 'full) (= (length v) 4) (caddr v)))
(define (full-wm v)
  (and (pair? v) (eq? (car v) 'full) (= (length v) 4) (cadddr v)))

;; ---------------------------------------------------------------------------
;; CHOR.
;; The global type is H→V ORDER; V→H DONE, with a timed branch on DONE. X is
;; not a role of the global type, so the dispatch to X and X's work lie
;; outside every projection, and H's projection contains no message about B.
;; H's local session is just the DONE message (the read-back of V's session
;; log adds nothing the session does not already say: the paradigm has no
;; notion of V's internal state beyond its messages).
;; - internal: DONE is the event it names — V's part A is done — so DONE
;;   arriving makes internal Fulfilled. If DONE has not arrived by the bound
;;   (T-EVAL), the session's timeout branch fires: the session ended without
;;   A, so internal is Violated (cited against the read-back delivery, the
;;   observer's latest event past the bound).
;; - external: part B is outside H's projection: Indeterminate.
(define (chor-judge ds)
  (define done (done-indices ds))
  (claims
   (if (pair? done)
       (list 'internal 'Fulfilled done)
       (list 'internal 'Violated (cites-of (read-any-index ds))))
   (list 'external 'Indeterminate '())))

;; ---------------------------------------------------------------------------
;; FSM.
;; V runs a machine ordered → A-done → (DONE sent); H's machine moves to
;; done-received on DONE or to timed-out on its own clock. H reads V's state
;; record at T-READ; the record is authoritative — V is in the state it
;; records. The record kind `record` holds only A's state; X has no machine
;; in this protocol and V's record carries no state for B.
;; - internal: record `done` → Fulfilled; record `pending` at T-READ, long
;;   after A was due → Violated. If the read fails, H falls back on its own
;;   machine: done-received → Fulfilled; timed-out (no DONE) → Violated.
;; - external: no machine state anywhere describes B: Indeterminate.
(define (fsm-judge ds)
  (define v (read-view ds))
  (define ri (read-index ds))
  (define done (done-indices ds))
  (claims
   (case (view-as v)
     [(done) (list 'internal 'Fulfilled (list ri))]
     [(pending) (list 'internal 'Violated (list ri))]
     [else
      (if (pair? done)
          (list 'internal 'Fulfilled done)
          (list 'internal 'Violated (cites-of (read-any-index ds))))])
   (list 'external 'Indeterminate '())))

;; ---------------------------------------------------------------------------
;; COMM.
;; The order creates two commitments with V as debtor and H as creditor:
;;   C_A = C(V, H, ordered, A performed)   C_B = C(V, H, ordered, B performed)
;; Both are detached by the order. V's dispatch to X is not a delegation
;; event in the H–V protocol (X is not a participant), so V remains debtor of
;; C_B. DONE is V's social act discharging C_A (it is conditioned on A). The
;; read-back returns V's ledger, which records C_A's state only.
;; Judgment is each commitment's state as the creditor H holds it:
;; - internal: C_A is discharged if H has seen DONE or V's ledger shows A
;;   done → Fulfilled; otherwise it is undischarged at its deadline → Violated.
;; - external: no message or ledger entry H holds discharges C_B, so at its
;;   deadline C_B is violated from H's point of view → Violated.
(define (comm-judge ds)
  (define v (read-view ds))
  (define ri (read-index ds))
  (define done (done-indices ds))
  (define ledger-done? (eq? (view-as v) 'done))
  (define rd (cites-of (read-any-index ds)))
  (claims
   (if (or (pair? done) ledger-done?)
       (list 'internal 'Fulfilled (cites-of done (and ledger-done? ri)))
       (list 'internal 'Violated rd))
   (list 'external 'Violated (if (null? rd) done rd))))

;; ---------------------------------------------------------------------------
;; HYBRID.
;; Commitments as in COMM (V retains responsibility for B; nothing is
;; dropped), V's state record with the `full` view (A's status, X's signed
;; outcome relayed into V's record, completeness watermark wm), X's signed
;; RECEIPT, and the evidentiary rules:
;; - internal: V's DONE and V's own record entry `done` are V's reports of
;;   its own performance; by E1 they are not evidence that A was performed,
;;   and nothing independent attests A → no Fulfilled. V's record not showing
;;   A when complete through T-A (wm ≥ T-A, E2) establishes the negative →
;;   Violated. Otherwise (record shows done, read failed, or record not
;;   complete through T-A) → Indeterminate (E3).
;; - external: X's signed outcome is an attestation from a party other than
;;   V, the debtor reporting to H, so it is independent evidence (E1) whether
;;   it arrives as RECEIPT or relayed in V's record: `complete` → Fulfilled,
;;   `partial` → Violated (B not performed in full). A relayed `none` proves
;;   X sent no outcome only if wm ≥ T-RECEIPT, the instant by which X's
;;   outcome would have been relayed (E2) → Violated; under a lagging record
;;   it proves nothing. With no receipt and no authoritative record → Indeterminate.
(define (hybrid-judge ds)
  (define v (read-view ds))
  (define ri (read-index ds))
  (define wm (full-wm v))
  (define xs (full-xs v))
  (define r-complete (receipt-indices ds 'complete))
  (define r-partial (receipt-indices ds 'partial))
  (claims
   (cond
     [(and (eq? (view-as v) 'pending) wm (>= wm T-A))
      (list 'internal 'Violated (list ri))]
     [else (list 'internal 'Indeterminate '())])
   (cond
     [(or (pair? r-complete) (eq? xs 'complete))
      (list 'external 'Fulfilled (cites-of r-complete (and (eq? xs 'complete) ri)))]
     [(or (pair? r-partial) (eq? xs 'partial))
      (list 'external 'Violated (cites-of r-partial (and (eq? xs 'partial) ri)))]
     [(and (eq? xs 'none) wm (>= wm T-RECEIPT))
      (list 'external 'Violated (list ri))]
     [else (list 'external 'Indeterminate '())])))

;; ---------------------------------------------------------------------------
;; HYBRID-NOE.
;; The same commitments, records, receipt and `full` view as HYBRID, with
;; E1–E3 removed: V's reports count as evidence of what they report, and
;; every successful read-back is authoritative, whatever its watermark.
;; The record, being authoritative and read last, decides when it is read;
;; otherwise the messages decide, and a commitment the creditor H cannot see
;; discharged by its deadline is violated (COMM).
;; - internal: record `done` → Fulfilled, `pending` → Violated. Read failed:
;;   DONE (V's report) → Fulfilled; no DONE → Violated.
;; - external: record relays `complete` → Fulfilled; `partial` or `none` →
;;   Violated (the record is taken as complete). Read failed: RECEIPT
;;   `complete` → Fulfilled, `partial` → Violated; no receipt → C_B
;;   undischarged → Violated.
(define (hybrid-noe-judge ds)
  (define v (read-view ds))
  (define ri (read-index ds))
  (define as (view-as v))
  (define xs (full-xs v))
  (define done (done-indices ds))
  (define r-complete (receipt-indices ds 'complete))
  (define r-partial (receipt-indices ds 'partial))
  (define rd (cites-of (read-any-index ds)))
  (claims
   (cond
     [(eq? as 'done) (list 'internal 'Fulfilled (cites-of ri done))]
     [(eq? as 'pending) (list 'internal 'Violated (list ri))]
     [(pair? done) (list 'internal 'Fulfilled done)]
     [else (list 'internal 'Violated rd)])
   (cond
     [(eq? xs 'complete) (list 'external 'Fulfilled (cites-of ri r-complete))]
     [(memq xs '(partial none)) (list 'external 'Violated (cites-of ri r-partial))]
     [(pair? r-complete) (list 'external 'Fulfilled r-complete)]
     [(pair? r-partial) (list 'external 'Violated r-partial)]
     [else (list 'external 'Violated rd)])))

;; ---------------------------------------------------------------------------

(define (mk name iface judge)
  (arm 'external name (hasheq) iface judge))

(define arms
  (list
   (mk 'chor       (hasheq 'receipt? #f 'view 'record) chor-judge)
   (mk 'fsm        (hasheq 'receipt? #f 'view 'record) fsm-judge)
   (mk 'comm       (hasheq 'receipt? #f 'view 'record) comm-judge)
   (mk 'hybrid     (hasheq 'receipt? #t 'view 'full)   hybrid-judge)
   (mk 'hybrid-noe (hasheq 'receipt? #t 'view 'full)   hybrid-noe-judge)))
