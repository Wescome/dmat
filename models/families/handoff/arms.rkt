#lang racket/base
;; Family 1 — information handoff. The five arms. Judges see deliveries only.

(require "../../core/arm.rkt" "../../core/observe.rkt" "terms.rkt")
(provide arms)

;; CHOR — timed session-typed choreography H→V REFER; V→H ACCEPT within
;; ACCEPT-DEADLINE; V→H START within DEADLINE; STATUS read-back returning the
;; last message V recorded as sent. Timed branches fire on arrival at H: an
;; ACCEPT arriving after the bound (late, or slow in transit) or not at all
;; takes the timeout branch, which the session records as V's failure to
;; respond (flow Violated). In the accept branch, a START (message, or V's last
;; recorded message) fulfils temporal and the START timer otherwise fires
;; (Violated). After the accept timeout the session has ended, so care is
;; outside H's projection (Indeterminate).
(define (chor-judge ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (define lm (and v (cadr v)))
  (define acc-ok (msg-indices ds 'ACCEPT #:arrived-by ACCEPT-DEADLINE))
  (define start (append (msg-indices ds 'START #:arrived-by DEADLINE)
                        (if (and (pair? lm) (eq? (car lm) 'START)) (list ri) '())))
  (define after (append (msg-indices ds 'ACCEPT) (if ri (list ri) '())))
  (claims (if (pair? acc-ok) (list 'flow 'Fulfilled acc-ok) (list 'flow 'Violated after))
          (cond [(pair? start) (list 'temporal 'Fulfilled start)]
                [(pair? acc-ok) (list 'temporal 'Violated (append acc-ok (if ri (list ri) '())))]
                [else (list 'temporal 'Indeterminate '())])))

;; FSM — H's machine waits for ACCEPT with a timeout at ACCEPT-DEADLINE on its
;; own clock (arrival): ACCEPT received in time moves H to handed-off (flow
;; Fulfilled); otherwise H's timeout moves it to overdue (Violated). V's state
;; record carries no instants, so it cannot decide the acceptance deadline; it
;; is authoritative for temporal: started, or not.
(define (fsm-judge ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (define S (and v (cadr v)))
  (define acc-in-time (msg-indices ds 'ACCEPT #:arrived-by ACCEPT-DEADLINE))
  (claims (if (pair? acc-in-time)
              (list 'flow 'Fulfilled acc-in-time)
              (list 'flow 'Violated (append (msg-indices ds 'ACCEPT) (if ri (list ri) '()))))
          (cond [(eq? S 'started) (list 'temporal 'Fulfilled (list ri))]
                [S (list 'temporal 'Violated (list ri))]
                [else (list 'temporal 'Indeterminate '())])))

;; COMM — C0 = C(V,H, referred, respond by ACCEPT-DEADLINE); C1 = C(V,H,
;; accepted, initiate care by DEADLINE). ACCEPT discharges C0 at its send
;; instant (late discharge does not cure); START discharges C1. Violated when
;; the deadline passes without a discharge the creditor holds; an expired C1
;; yields no judgment.
(define (comm-judge ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (define c0 (and v (cadr v))) (define c1 (and v (caddr v)))
  (define rc (if ri (list ri) '()))
  (define c0-ok (append (msg-indices ds 'ACCEPT #:asserted-by ACCEPT-DEADLINE) (if (eq? c0 'discharged) rc '())))
  (define accepted (append (msg-indices ds 'ACCEPT) (if (memq c0 '(discharged late-discharged)) rc '())))
  (define c1-ok (append (msg-indices ds 'START #:asserted-by DEADLINE) (if (eq? c1 'discharged) rc '())))
  (claims (if (pair? c0-ok) (list 'flow 'Fulfilled c0-ok) (list 'flow 'Violated (append accepted rc)))
          (cond [(pair? c1-ok) (list 'temporal 'Fulfilled c1-ok)]
                [(pair? accepted) (list 'temporal 'Violated (append accepted rc))]
                [else (list 'temporal 'Indeterminate '())])))

;; HYBRID — interaction of CHOR plus an independent attestation; FSM guards;
;; COMM commitments; evidentiary semantics. Positive judgments need evidence
;; constituting the fact (care initiation: the attestation, since V's notice
;; and record are V's own report). Negative judgments need constitutive
;; evidence (an acceptance sent after the deadline) or an authoritative read:
;; a read whose source is complete through the due instant (watermark ≥ due).
;; HYBRID-NOE: the same, but every read is authoritative, V's own report is
;; evidence of care initiation, and where the hybrid would abstain the
;; commitment rule applies: a commitment the creditor has not seen discharged
;; by its deadline is violated (C0 always; C1 once detached by an acceptance).
(define ((hybrid-judge evidence?) ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (define-values (S oat ost wm)
    (if v (values (list-ref v 1) (list-ref v 2) (list-ref v 3) (list-ref v 6)) (values #f #f #f #f)))
  (define (auth? due) (and v (or (not evidence?) (>= wm due))))
  (define acc-ok (append (msg-indices ds 'ACCEPT #:asserted-by ACCEPT-DEADLINE)
                         (if (and oat (<= oat ACCEPT-DEADLINE)) (list ri) '())))
  (define acc-late (append (msg-indices ds 'ACCEPT #:where (λ (d) (> (list-ref d 3) ACCEPT-DEADLINE)))
                           (if (and oat (> oat ACCEPT-DEADLINE)) (list ri) '())))
  (define accepted (append (msg-indices ds 'ACCEPT) (if oat (list ri) '())))
  (define start (append (msg-indices ds 'ATTEST #:asserted-by DEADLINE)
                        (if evidence? '()
                            (append (msg-indices ds 'START #:asserted-by DEADLINE)
                                    (if (and ost (<= ost DEADLINE)) (list ri) '())))))
  (claims (cond [(pair? acc-ok) (list 'flow 'Fulfilled acc-ok)]
                [(pair? acc-late) (list 'flow 'Violated acc-late)]
                [(and (auth? ACCEPT-DEADLINE) (eq? S 'referred)) (list 'flow 'Violated (list ri))]
                [(not evidence?) (list 'flow 'Violated (if ri (list ri) '()))]          ; C0 not seen discharged
                [else (list 'flow 'Indeterminate '())])
          (cond [(pair? start) (list 'temporal 'Fulfilled start)]
                [(and (auth? DEADLINE) (not (eq? S 'started))) (list 'temporal 'Violated (list ri))]
                [(and (not evidence?) (pair? accepted))                             ; C1 detached, not seen discharged
                 (list 'temporal 'Violated accepted)]
                [else (list 'temporal 'Indeterminate '())])))

(define arms
  (list (arm 'handoff 'chor (hasheq) (hasheq 'notice? #t 'attest? #f 'view 'last-message) chor-judge)
        (arm 'handoff 'fsm (hasheq) (hasheq 'notice? #f 'attest? #f 'view 'state) fsm-judge)
        (arm 'handoff 'comm (hasheq) (hasheq 'notice? #t 'attest? #f 'view 'ledger) comm-judge)
        (arm 'handoff 'hybrid (hasheq) (hasheq 'notice? #t 'attest? #t 'view 'full) (hybrid-judge #t))
        (arm 'handoff 'hybrid-noe (hasheq) (hasheq 'notice? #t 'attest? #t 'view 'full) (hybrid-judge #f))))
