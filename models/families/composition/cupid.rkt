#lang racket/base
;; Family 7 — multi-organization composition. Commitment arms over the client
;; H's information base (core/cupid.rkt), with the hybrid's protocol and
;; interface: the staged observation model of V's case record, and an
;; attestation of S's start by a trusted clock.
;;
;;   C_t = C(S, H, ⊤, START by DEADLINE)      → temporal
;;         S's commitment, which V's case record relays to H; S's DECLINE
;;         cancels it before discharge: Violated
;;   C_d = C(V, H, ⊤, DELIVERED by T-EVAL)    → delivery
;;
;; Information: S's stage as V's staged record relays it — started at an
;; instant (S's report of its own performance), declined (S's act), committed
;; (nothing); the attestation (a third party's report of S's start); DELIVERED,
;; received by H (the delivery itself, which H observes); V's closed case (V's
;; report of its own delivery). V's case record has no completeness watermark,
;; so it is no coverage.
;; cupid: closed-world reading. cupid-e: E1–E3.

(require racket/list "../../core/arm.rkt" "../../core/observe.rkt" "../../core/cupid.rkt" "terms.rkt")
(provide cupid-arms)

(define (info ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (define staged (and v (eq? (car v) 'staged) v))
  (define facts
    (append
     (for/list ([i (msg-indices ds 'ATTEST)]) (fact 'START 'attester 'performance (msg-asserted (list-ref ds i)) '() i))
     (for/list ([i (msg-indices ds 'DELIVERED)]) (fact 'DELIVERED 'V 'act (msg-asserted (list-ref ds i)) '() i))
     (if (and staged (eq? (list-ref staged 2) 'started)) (list (fact 'START 'S 'performance (list-ref staged 3) '() ri)) '())
     (if (and staged (eq? (list-ref staged 2) 'declined)) (list (fact 'DECLINE 'S 'act T-COMMIT '() ri)) '())
     (if (and v (eq? (cadr v) 'closed)) (list (fact 'DELIVERED 'V 'performance T-DELIVER '() ri)) '())))
  facts)

(define (is e) (λ (f) (eq? (fact-event f) e)))
(define C-t (commitment 'C-t 'S 'H 'true 0 (is 'START) DEADLINE))
(define C-d (commitment 'C-d 'V 'H 'true 0 (is 'DELIVERED) T-EVAL))

(define ((judge ev) ds)
  (define facts (info ds))
  (define-values (st ct) (commitment-state C-t facts '() #:evidential? ev #:a-kinds '() #:c-kinds '(START)))
  (define-values (sd cd) (commitment-state C-d facts '() #:evidential? ev #:a-kinds '() #:c-kinds '(DELIVERED)))
  (define declines (map fact-index (filter (is 'DECLINE) facts)))
  (claims (if (and (pair? declines) (not (eq? st 'discharged)))
              (dep-claim 'temporal 'Violated declines)
              (dep-claim 'temporal (state->judgment st) ct))
          (dep-claim 'delivery (state->judgment sd) cd)))

(define P (hasheq))
(define I (hasheq 'obs 'staged 'attest? #t))
(define cupid-arms
  (list (arm 'composition 'cupid P I (judge #f))
        (arm 'composition 'cupid-e P I (judge #t))))
