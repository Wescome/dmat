#lang racket/base
;; Family 3 — multi-party agreement (Fit, Flow). Shared terms.
;;
;; A buyer B proposes terms to a seller S. S accepts, with the proposed terms
;; or with altered terms that do not fit B's requirement. B confirms (or
;; rejects); S binds on receiving the confirmation and acknowledges. S may
;; revoke its offer concurrently with B's confirmation: the two messages
;; cross, and the order in which S processes them is a world choice
;; (interleaving).
;;   fit    : no party is bound to terms that do not fit B's requirement
;;   mutual : B and S agree on whether they are bound (neither bound alone)

(require redex/reduction-semantics "../../core/grammar.rkt")
(provide AGREEMENT world? ds?
         T-ACCEPT-SENT T-ACCEPT-ARR T-CONFIRM T-S-PROCESS T-ACK-ARR T-READ T-EVAL STALE-AS-OF)

(define T-ACCEPT-SENT 1)
(define T-ACCEPT-ARR 2)
(define T-CONFIRM 2)       ; B confirms or rejects on receipt of the acceptance
(define T-S-PROCESS 3)     ; S processes the confirmation (and its own revocation)
(define T-ACK-ARR 4)
(define T-READ 11)
(define T-EVAL 12)
(define STALE-AS-OF 1)

(define-extended-language AGREEMENT DMAT0
  ;; (world terms revoke order confirm ack read)
  (terms as-proposed altered)
  (order confirm-first revoke-first)
  (fate delivered dropped)
  (read fresh stale unavailable)
  (w (world terms b order fate fate read))
  (ss offered bound revoked)
  (lm ACCEPT ACK REVOKE)
  (cs none active released)
  (view (last-message lm) (state ss) (ledger cs) (full ss terms t))
  (d (msg ACCEPT t t terms) (msg CONFIRM t t) (msg REJECT t t) (msg REVOKE t t) (msg ACK t t)
     (read-ok t view) (read-failed t))
  (ds (d ...)))

(define world? (redex-match? AGREEMENT w))
(define ds? (redex-match? AGREEMENT ds))
