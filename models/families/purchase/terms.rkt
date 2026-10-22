#lang racket/base
;; Family 9 — purchase on a principal's behalf (Sharing, Fit, Flow, Temporal).
;; Shared terms: the language of worlds, calls, replies and transcripts, and the
;; constants of specs/purchase.md §6.
;;
;; The world is interactive: an arm acts by calling the providers through the
;; provider interface and receives one reply per call. Its deliveries are its
;; transcript, (msg REPLY n n call reply) for the n-th call.
;;
;; Names written with an underscore in the specification and in the external
;; arms' JSON (IN_TRANSIT, STATE_UNCERTAIN, ...) are written with a hyphen in
;; these terms, since Redex reserves the underscore.

(require redex/reduction-semantics "../../core/grammar.rkt")
(provide PURCHASE world? ds? call? reply?
         CAP PRICE-A PRICE-B-WITHIN PRICE-B-OVER T-ON-TIME DEADLINE T-LATE CALL-LIMIT
         SELLERS FAILURE-CLASSES)

(define CAP 180)
(define PRICE-A 150)
(define PRICE-B-WITHIN 170)
(define PRICE-B-OVER 200)
(define T-ON-TIME 10)
(define DEADLINE 12)
(define T-LATE 14)
(define CALL-LIMIT 60)
(define SELLERS '(A B))
(define FAILURE-CLASSES '(STATE-UNCERTAIN BUSINESS-REJECTION RESOURCE-UNAVAILABLE DEPENDENCY-FAILURE DEADLINE-BREACH))

(define-extended-language PURCHASE DMAT0
  ;; (world stock alt auth void read capture deliver report scan)
  (stock kept lost)
  (alt within over none)
  (lostable replied lost)
  (voidf replied lost timeout)
  (readf fresh stale unavailable)
  (deliverf on-time late never)
  (reportf honest premature)
  (scanf recorded dropped)
  (w (world stock alt lostable voidf readf lostable deliverf reportf scanf))
  (S A B)
  (key string)
  (amount natural)
  (hs NONE AUTHORIZED VOIDED CAPTURED REFUNDED)
  (os NONE ACCEPTED CANCELLED)
  (ss NONE IN-TRANSIT DELIVERED)
  (call (reserve S) (alternatives) (authorize S amount key) (confirm S) (accept S key)
        (void S key) (capture S key) (refund S key) (cancel S key) (ship S key) (deliver S key)
        (payment-record) (order-state S) (shipment-state) (carrier-scan) (reconcile) (invalid))
  (hold (S hs amount))
  (rec (record c (hold ...)))
  (c natural #f)
  (value reserved available lost hs os ss
         (offers (S natural) ...)
         (at natural) (at none)
         rec
         (report rec (orders (S os) ...) ss natural))
  (class STATE-UNCERTAIN BUSINESS-REJECTION RESOURCE-UNAVAILABLE DEPENDENCY-FAILURE DEADLINE-BREACH)
  (reply (ok value) (failed class variable))
  (d (msg REPLY t t call reply))
  (ds (d ...)))

(define world? (redex-match? PURCHASE w))
(define ds? (redex-match? PURCHASE ds))
(define call? (redex-match? PURCHASE call))
(define reply? (redex-match? PURCHASE reply))
