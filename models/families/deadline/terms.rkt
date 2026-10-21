#lang racket/base
;; Family 5 — deadline-bound service (Temporal). Shared terms.
;;
;; A provider V owes a service by DEADLINE. V reports completion with a DONE
;; message stamped by V's own clock; the report's transit may be short or
;; long, and V's clock may run ahead or behind. A third-party attestation,
;; stamped by a trusted clock, exists for protocols that define one.
;;   temporal   : the service was completed by DEADLINE (true time)
;;   completion : the service was completed at all by T-EVAL

(require redex/reduction-semantics "../../core/grammar.rkt")
(provide DEADLINE-SERVICE world? ds?
         T-ON-TIME T-LATE DEADLINE SHORT LONG SKEW ATTEST-DELAY T-READ T-EVAL)

(define T-ON-TIME 8)
(define T-LATE 12)
(define DEADLINE 10)
(define SHORT 1)
(define LONG 5)
(define SKEW 3)
(define ATTEST-DELAY 2)
(define T-READ 19)
(define T-EVAL 20)

(define-extended-language DEADLINE-SERVICE DMAT0
  ;; (world done delay skew attest read)
  (done on-time late never)
  (delay short long)
  (skew none ahead behind)
  (fate delivered dropped)
  (read fresh unavailable)
  (w (world done delay skew fate read))
  (ot #f t)
  (view (record ot))
  (d (msg DONE t t) (msg ATTEST t t) (read-ok t view) (read-failed t))
  (ds (d ...)))

(define world? (redex-match? DEADLINE-SERVICE w))
(define ds? (redex-match? DEADLINE-SERVICE ds))
