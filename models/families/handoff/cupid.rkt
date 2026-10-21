#lang racket/base
;; Family 1 — information handoff. Commitment arms in the information-protocol
;; style: the creditor H's information base is built from its deliveries, and
;; commitment states are queries over it (core/cupid.rkt).
;;
;;   C0 = C(V, H, ⊤, ACCEPT by ACCEPT-DEADLINE)          → flow
;;   C1 = C(V, H, ACCEPT by DEADLINE, START by DEADLINE) → temporal
;;        (expired: V never accepted, so care was never initiated → Violated)
;;
;; Information: ACCEPT is V's act; START (notice, or V's record) is V's report
;; of its own performance; ATTEST is the attester's report of V's performance;
;; V's record is a coverage of ACCEPT and START through its watermark.
;; cupid: closed-world reading. cupid-e: E1–E3.

(require racket/list "../../core/arm.rkt" "../../core/observe.rkt" "../../core/cupid.rkt" "terms.rkt")
(provide cupid-arms)

(define (info ds)
  (define facts
    (append
     (for/list ([i (msg-indices ds 'ACCEPT)]) (fact 'ACCEPT 'V 'act (msg-asserted (list-ref ds i)) '() i))
     (for/list ([i (msg-indices ds 'START)]) (fact 'START 'V 'performance (msg-asserted (list-ref ds i)) '() i))
     (for/list ([i (msg-indices ds 'ATTEST)]) (fact 'START 'attester 'performance (msg-asserted (list-ref ds i)) '() i))
     (let ([v (read-view ds)] [ri (read-index ds)])
       (if v
           (append (if (list-ref v 2) (list (fact 'ACCEPT 'V 'act (list-ref v 2) '() ri)) '())
                   (if (list-ref v 3) (list (fact 'START 'V 'performance (list-ref v 3) '() ri)) '()))
           '()))))
  (define covs
    (let ([v (read-view ds)] [ri (read-index ds)])
      (if v (list (coverage 'V (list-ref v 6) '(ACCEPT START) ri)) '())))
  (values facts covs))

(define (is e) (λ (f) (eq? (fact-event f) e)))
(define C0 (commitment 'C0 'V 'H 'true 0 (is 'ACCEPT) ACCEPT-DEADLINE))
(define C1 (commitment 'C1 'V 'H (is 'ACCEPT) DEADLINE (is 'START) DEADLINE))

(define ((judge ev) ds)
  (define-values (facts covs) (info ds))
  (define-values (s0 c0) (commitment-state C0 facts covs #:evidential? ev #:a-kinds '() #:c-kinds '(ACCEPT)))
  (define-values (s1 c1) (commitment-state C1 facts covs #:evidential? ev #:a-kinds '(ACCEPT) #:c-kinds '(START)))
  (claims (dep-claim 'flow (state->judgment s0) c0)
          (dep-claim 'temporal (state->judgment s1 #:expired 'Violated) c1)))

(define cupid-arms
  (list (arm 'handoff 'cupid (hasheq) (hasheq 'notice? #t 'attest? #t 'view 'full) (judge #f))
        (arm 'handoff 'cupid-e (hasheq) (hasheq 'notice? #t 'attest? #t 'view 'full) (judge #t))))
