#lang racket/base
;; Family 7 — multi-organization composition. The five arms. Judges accept
;; either observation model, so P2 can run any arm under either.

(require "../../core/arm.rkt" "../../core/observe.rkt" "terms.rkt")
(provide arms)

(define (case-status v) (and v (cadr v)))
(define (s-stage v) (and v (eq? (car v) 'staged) (caddr v)))
(define (s-start v) (and v (eq? (car v) 'staged) (cadddr v)))

;; Delivery for CHOR, FSM, COMM and HYBRID-NOE: DELIVERED received, or V's case
;; closed (Fulfilled); case open at the read (Violated); with neither, H's wait
;; for DELIVERED timed out — the creditor has not seen the delivery by T-EVAL
;; (Violated).
(define (delivery-claim ds)
  (define dl (msg-indices ds 'DELIVERED)) (define ri (read-index ds)) (define v (read-view ds))
  (cond [(pair? dl) (list 'delivery 'Fulfilled dl)]
        [(eq? (case-status v) 'closed) (list 'delivery 'Fulfilled (list ri))]
        [(eq? (case-status v) 'open) (list 'delivery 'Violated (list ri))]
        [else (list 'delivery 'Violated '())]))

;; CHOR — the global type H→V ORDER; V→S SUB; S→V ACK; V→H DELIVERED projects
;; to H as ORDER; DELIVERED. S's stage is outside H's projection: temporal is
;; Indeterminate unless V's record shows it.
(define (chor-judge ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (claims (cond [(and (eq? (s-stage v) 'started) (<= (s-start v) DEADLINE)) (list 'temporal 'Fulfilled (list ri))]
                [(s-stage v) (list 'temporal 'Violated (list ri))]
                [else (list 'temporal 'Indeterminate '())])
          (delivery-claim ds)))

;; FSM — V's case machine: open → subcontracted → assembled → closed. The
;; subcontract stage is internal to V's machine; reaching 'closed' implies the
;; stage completed, and the machine's timing guard is taken to have held.
(define (fsm-judge ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (define dl (msg-indices ds 'DELIVERED))
  (claims (cond [(and (eq? (s-stage v) 'started) (<= (s-start v) DEADLINE)) (list 'temporal 'Fulfilled (list ri))]
                [(s-stage v) (list 'temporal 'Violated (list ri))]
                [(or (pair? dl) (eq? (case-status v) 'closed)) (list 'temporal 'Fulfilled (append dl (if v (list ri) '())))]
                [else (list 'temporal 'Indeterminate '())])
          (delivery-claim ds)))

;; COMM — V retains C(V,H, ordered, stage initiated by DEADLINE) and
;; C(V,H, ordered, delivered). Discharge requires the creditor to hold
;; evidence by the deadline; nothing V sends H before T-DELIVER, so without a
;; staged record the timing commitment is violated from H's side.
(define (comm-judge ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (claims (cond [(and (eq? (s-stage v) 'started) (<= (s-start v) DEADLINE)) (list 'temporal 'Fulfilled (list ri))]
                [v (list 'temporal 'Violated (list ri))]
                [else (list 'temporal 'Violated '())])
          (delivery-claim ds)))

;; HYBRID — staged observation, retained commitment, and S's start attested by
;; a trusted clock. S's own report relayed by V is a report: it establishes a
;; negative (S reports it declined, or started after the deadline) but not an
;; on-time start (E1). V's case record has no completeness watermark, so it
;; proves only what it contains (E2): 'committed' or 'open' is no negative. V's
;; closed case is V's report of its own delivery (E1); DELIVERED, received by
;; H, is H's own observation of the flow.
;; HYBRID-NOE: the relayed report is evidence of the start, every read is
;; authoritative, and delivery follows the creditor rule.
(define ((hybrid-judge evidence?) ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (define att (for/first ([i (msg-indices ds 'ATTEST)]) (cons i (msg-asserted (list-ref ds i)))))
  (define dl (msg-indices ds 'DELIVERED))
  (define st (s-stage v)) (define ot (s-start v))
  (if evidence?
      (claims (cond [att (list 'temporal (if (<= (cdr att) DEADLINE) 'Fulfilled 'Violated) (list (car att)))]
                    [(eq? st 'declined) (list 'temporal 'Violated (list ri))]
                    [(and (eq? st 'started) (> ot DEADLINE)) (list 'temporal 'Violated (list ri))]
                    [else (list 'temporal 'Indeterminate '())])
              (if (pair? dl) (list 'delivery 'Fulfilled dl) (list 'delivery 'Indeterminate '())))
      (claims (cond [att (list 'temporal (if (<= (cdr att) DEADLINE) 'Fulfilled 'Violated) (list (car att)))]
                    [(memq st '(committed declined)) (list 'temporal 'Violated (list ri))]
                    [(eq? st 'started) (list 'temporal (if (<= ot DEADLINE) 'Fulfilled 'Violated) (list ri))]
                    [else (list 'temporal 'Indeterminate '())])
              (delivery-claim ds))))

(define arms
  (list (arm 'composition 'chor (hasheq) (hasheq 'obs 'coarse 'attest? #f) chor-judge)
        (arm 'composition 'fsm (hasheq) (hasheq 'obs 'coarse 'attest? #f) fsm-judge)
        (arm 'composition 'comm (hasheq) (hasheq 'obs 'coarse 'attest? #f) comm-judge)
        (arm 'composition 'hybrid (hasheq) (hasheq 'obs 'staged 'attest? #t) (hybrid-judge #t))
        (arm 'composition 'hybrid-noe (hasheq) (hasheq 'obs 'staged 'attest? #t) (hybrid-judge #f))))
