#lang racket/base
;; Family 5 — deadline-bound service. The five arms.

(require "../../core/arm.rkt" "../../core/observe.rkt" "terms.rkt")
(provide arms)

(define (record-stamp ds) (let ([v (read-view ds)]) (and v (cadr v))))

;; CHOR — timed choreography: V→H DONE within DEADLINE, else the timeout
;; branch. The timeout is a protocol event, judged by arrival at H. Temporal:
;; DONE arrived by the deadline (Fulfilled), DONE after it or no DONE (the
;; timeout branch fired: Violated). Completion: a DONE message or V's message
;; log showing DONE; otherwise the session's wait for DONE timed out at
;; T-EVAL (Violated).
(define (chor-judge ds)
  (define ri (read-index ds))
  (define in-time (msg-indices ds 'DONE #:arrived-by DEADLINE))
  (define any-done (msg-indices ds 'DONE))
  (define logged (if (record-stamp ds) (list ri) '()))
  (claims (if (pair? in-time) (list 'temporal 'Fulfilled in-time) (list 'temporal 'Violated any-done))
          (if (pair? (append any-done logged)) (list 'completion 'Fulfilled (append any-done logged))
              (list 'completion 'Violated (if ri (list ri) '())))))

;; FSM — V's state machine records the completion transition with V's clock;
;; the record is authoritative (and, without a read, the DONE message's stamp).
;; With neither, H's own machine has timed out waiting for DONE: overdue.
(define (fsm-judge ds)
  (define ri (read-index ds))
  (define stamp (or (record-stamp ds)
                    (for/first ([i (msg-indices ds 'DONE)]) (msg-asserted (list-ref ds i)))))
  (define cites (append (if ri (list ri) '()) (msg-indices ds 'DONE)))
  (cond [stamp (claims (list 'temporal (if (<= stamp DEADLINE) 'Fulfilled 'Violated) cites)
                       (list 'completion 'Fulfilled cites))]
        [else (let ([c (if ri (list ri) '())])
                (claims (list 'temporal 'Violated c) (list 'completion 'Violated c)))]))

;; COMM — C(V,H, ordered, service by DEADLINE), discharged by the debtor's DONE
;; when the creditor holds it: held by the deadline, Fulfilled; otherwise
;; violated. Completion: DONE held (message or V's ledger) by T-EVAL.
(define (comm-judge ds)
  (define ri (read-index ds))
  (define held (msg-indices ds 'DONE #:arrived-by DEADLINE))
  (define ever (append (msg-indices ds 'DONE) (if (record-stamp ds) (list ri) '())))
  (claims (if (pair? held) (list 'temporal 'Fulfilled held) (list 'temporal 'Violated (if ri (list ri) '())))
          (if (pair? ever) (list 'completion 'Fulfilled ever) (list 'completion 'Violated (if ri (list ri) '())))))

;; HYBRID — the attestation's trusted-clock stamp decides temporal and
;; constitutes completion. V's own record and DONE stamp are V's report: they
;; may only establish a negative (V's record shows no completion at the read).
;; HYBRID-NOE: V's stamps are evidence too, and where the hybrid would abstain
;; the commitment rule applies: service not seen completed is violated.
(define ((hybrid-judge evidence?) ds)
  (define ri (read-index ds))
  (define att (for/first ([i (msg-indices ds 'ATTEST)]) (cons i (msg-asserted (list-ref ds i)))))
  (define stamp (or (record-stamp ds) (for/first ([i (msg-indices ds 'DONE)]) (msg-asserted (list-ref ds i)))))
  (define v-cites (append (if (and ri (record-stamp ds)) (list ri) '()) (msg-indices ds 'DONE)))
  (cond
    [att (claims (list 'temporal (if (<= (cdr att) DEADLINE) 'Fulfilled 'Violated) (list (car att)))
                 (list 'completion 'Fulfilled (list (car att))))]
    [(and ri (not (record-stamp ds)) (null? (msg-indices ds 'DONE)))
     (claims (list 'temporal 'Violated (list ri)) (list 'completion 'Violated (list ri)))]
    [(and (not evidence?) stamp)
     (claims (list 'temporal (if (<= stamp DEADLINE) 'Fulfilled 'Violated) v-cites)
             (list 'completion 'Fulfilled v-cites))]
    [(not evidence?) (let ([c (if ri (list ri) '())])
                       (claims (list 'temporal 'Violated c) (list 'completion 'Violated c)))]
    [else (claims (list 'temporal 'Indeterminate '()) (list 'completion 'Indeterminate '()))]))

(define arms
  (list (arm 'deadline 'chor (hasheq) (hasheq 'attest? #f) chor-judge)
        (arm 'deadline 'fsm (hasheq) (hasheq 'attest? #f) fsm-judge)
        (arm 'deadline 'comm (hasheq) (hasheq 'attest? #f) comm-judge)
        (arm 'deadline 'hybrid (hasheq) (hasheq 'attest? #t) (hybrid-judge #t))
        (arm 'deadline 'hybrid-noe (hasheq) (hasheq 'attest? #t) (hybrid-judge #f))))
