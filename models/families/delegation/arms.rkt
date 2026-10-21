#lang racket/base
;; Family 4 — conditional delegation. The five arms.

(require "../../core/arm.rkt" "../../core/observe.rkt" "terms.rkt")
(provide arms)

(define (accept-i ds) (msg-indices ds 'ACCEPT))

;; CHOR — two binary sessions: H–V (REFER; ACCEPT; DELEGATED | START) and V–S.
;; V's session with H completes when V reports DELEGATED; V is then released.
;; H sees only its own session. Continuity: no DELEGATED (message or V's last
;; recorded message) means V's session never ended (Fulfilled); after
;; DELEGATED, S is outside H's session: Indeterminate. Temporal: a START
;; arriving by the deadline (or V's last recorded message START); otherwise the
;; session's START timer fired: Violated.
(define (chor-judge ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (define lm (and v (cadr v)))
  (define delegated (or (pair? (msg-indices ds 'DELEGATED)) (eq? lm 'DELEGATED)))
  (define start (append (msg-indices ds 'START #:arrived-by DEADLINE) (if (eq? lm 'START) (list ri) '())))
  (claims (cond [delegated (list 'continuity 'Indeterminate '())]
                [v (list 'continuity 'Fulfilled (cons ri (accept-i ds)))]
                [else (list 'continuity 'Indeterminate '())])
          (if (pair? start) (list 'temporal 'Fulfilled start) (list 'temporal 'Violated (accept-i ds)))))

;; FSM — V: accepted → delegating → (delegated | resumed) → started; the
;; guard keeps V responsible until S accepts. V's state record is
;; authoritative: 'released' is a break in continuity; a state without care
;; initiated is a violation of temporal. With no read, the guard is taken to
;; have held (continuity Fulfilled) and temporal is unknown.
(define (fsm-judge ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (define vs (and v (cadr v)))
  (claims (cond [(eq? vs 'released) (list 'continuity 'Violated (list ri))]
                [vs (list 'continuity 'Fulfilled (list ri))]
                [else (list 'continuity 'Fulfilled (accept-i ds))])
          (cond [(memq vs '(started sub-started)) (list 'temporal 'Fulfilled (list ri))]
                [vs (list 'temporal 'Violated (list ri))]
                [else (list 'temporal 'Indeterminate '())])))

;; COMM — C1 = C(V,H, accepted, initiate care by DEADLINE). Delegation creates
;; C2 = C(S,V, delegated, initiate care); C1 is pending while C2 is active and
;; reactivated if C2 is declined (outsourcing). Continuity: C1, created by
;; V's ACCEPT, is never released under this protocol; it is broken only if V's
;; ledger shows it released, or pending with no active or discharged C2
;; covering it. Temporal: C1 discharged (START, or the ledger), else violated.
(define (comm-judge ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (define c1 (and v (cadr v)))
  (define start (append (msg-indices ds 'START #:asserted-by DEADLINE) (if (eq? c1 'discharged) (list ri) '())))
  (define c2 (and v (caddr v)))
  (claims (cond [(or (eq? c1 'released) (and (eq? c1 'pending) (not (memq c2 '(active discharged)))))
                 (list 'continuity 'Violated (list ri))]
                [c1 (list 'continuity 'Fulfilled (list ri))]
                [else (list 'continuity 'Fulfilled (accept-i ds))])
          (if (pair? start) (list 'temporal 'Fulfilled start)
              (list 'temporal 'Violated (append (accept-i ds) (if ri (list ri) '()))))))

;; HYBRID — COMM's retained responsibility, FSM guards, the subcontractor's
;; stage relayed in V's record, and an independent attestation of care
;; initiation. Continuity is a property of the commitment structure, not a
;; report of performance: C1 is created by V's ACCEPT and is retained until S
;; accepts and reactivated if S declines, so it holds unless V's record shows
;; C1 released (a record proves what it contains, whatever its watermark).
;; Evidence for temporal: Fulfilled on the attestation, Violated only on a
;; record complete through the deadline.
;; HYBRID-NOE: every read authoritative; START and V's record count as
;; evidence of care initiation; where the hybrid would abstain, C1 not seen
;; discharged by the deadline is violated.
(define ((hybrid-judge evidence?) ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (define-values (vs c1 wm) (if v (values (list-ref v 1) (list-ref v 2) (list-ref v 5)) (values #f #f #f)))
  (define (auth? due) (and v (or (not evidence?) (>= wm due))))
  (define start (append (msg-indices ds 'ATTEST #:asserted-by DEADLINE)
                        (if evidence? '()
                            (append (msg-indices ds 'START #:asserted-by DEADLINE)
                                    (if (memq vs '(started sub-started)) (list ri) '())))))
  (claims (cond [(eq? c1 'released) (list 'continuity 'Violated (list ri))]
                [else (list 'continuity 'Fulfilled (append (accept-i ds) (if (auth? T-S-RESPONSE) (list ri) '())))])
          (cond [(pair? start) (list 'temporal 'Fulfilled start)]
                [(and (auth? DEADLINE) (not (memq vs '(started sub-started)))) (list 'temporal 'Violated (list ri))]
                [(not evidence?) (list 'temporal 'Violated (append (accept-i ds) (if ri (list ri) '())))]
                [else (list 'temporal 'Indeterminate '())])))

(define arms
  (list (arm 'delegation 'chor (hasheq 'on-delegate 'release) (hasheq 'notice? #t 'attest? #f 'view 'last-message) chor-judge)
        (arm 'delegation 'fsm (hasheq 'on-delegate 'retain) (hasheq 'notice? #f 'attest? #f 'view 'state) fsm-judge)
        (arm 'delegation 'comm (hasheq 'on-delegate 'retain) (hasheq 'notice? #t 'attest? #f 'view 'ledger) comm-judge)
        (arm 'delegation 'hybrid (hasheq 'on-delegate 'retain) (hasheq 'notice? #t 'attest? #t 'view 'full) (hybrid-judge #t))
        (arm 'delegation 'hybrid-noe (hasheq 'on-delegate 'retain) (hasheq 'notice? #t 'attest? #t 'view 'full) (hybrid-judge #f))))
