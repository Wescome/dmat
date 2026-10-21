#lang racket/base
;; Family 5 — deadline-bound service. Commitment arms over the client H's
;; information base (core/cupid.rkt), with the hybrid's protocol: a
;; third-party attestation stamped by a trusted clock.
;;
;;   C_t = C(V, H, ⊤, DONE by DEADLINE)   → temporal
;;   C_c = C(V, H, ⊤, DONE by T-EVAL)     → completion
;;
;; Information: V's DONE message and V's record are V's reports of its own
;; performance, timed by V's clock; the attestation is a third party's report,
;; timed by the trusted clock; V's record, read at T-READ, is a coverage of
;; DONE through T-READ. V's clock may be skewed, so V's stamps admit nothing
;; (#:debtor-clock? #f).
;; cupid: closed-world reading, V's stamp taken as the instant. cupid-e: E1–E3.

(require racket/list "../../core/arm.rkt" "../../core/observe.rkt" "../../core/cupid.rkt" "terms.rkt")
(provide cupid-arms)

(define (info ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (define facts
    (append
     (for/list ([i (msg-indices ds 'DONE)]) (fact 'DONE 'V 'performance (msg-asserted (list-ref ds i)) '() i))
     (for/list ([i (msg-indices ds 'ATTEST)]) (fact 'DONE 'attester 'performance (msg-asserted (list-ref ds i)) '() i))
     (if (and v (cadr v)) (list (fact 'DONE 'V 'performance (cadr v) '() ri)) '())))
  (define covs (if v (list (coverage 'V T-READ '(DONE) ri)) '()))
  (values facts covs))

(define (is e) (λ (f) (eq? (fact-event f) e)))
(define C-t (commitment 'C-t 'V 'H 'true 0 (is 'DONE) DEADLINE))
(define C-c (commitment 'C-c 'V 'H 'true 0 (is 'DONE) T-EVAL))

(define ((judge ev) ds)
  (define-values (facts covs) (info ds))
  (define (state c)
    (commitment-state c facts covs #:evidential? ev #:a-kinds '() #:c-kinds '(DONE) #:debtor-clock? #f))
  (define-values (st ct) (state C-t))
  (define-values (sc cc) (state C-c))
  (claims (dep-claim 'temporal (state->judgment st) ct)
          (dep-claim 'completion (state->judgment sc) cc)))

(define P (hasheq))
(define I (hasheq 'attest? #t))
(define cupid-arms
  (list (arm 'deadline 'cupid P I (judge #f))
        (arm 'deadline 'cupid-e P I (judge #t))))
