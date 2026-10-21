#lang racket/base
;; Family 6 — partial external execution (Flow). Shared terms.
;;
;; H orders a two-part service from V. V performs part A itself; part B is
;; dispatched to an external executor X that is not a protocol participant.
;; X may complete B, complete it partially, or not perform it. V reports DONE
;; to H when A is done (honest) or regardless of A (premature); V cannot
;; observe B's outcome. Protocols that define an external receipt get X's
;; signed outcome; the hybrid's record relays it, subject to record lag.
;;   internal : part A performed
;;   external : part B performed in full

(require redex/reduction-semantics "../../core/grammar.rkt")
(provide EXTERNAL world? ds?
         T-A T-DISPATCH T-DONE T-X T-RECEIPT T-READ T-EVAL LAG-WATERMARK)

(define T-A 4)
(define T-DISPATCH 5)
(define T-DONE 6)           ; V's DONE arrives
(define T-X 7)              ; X performs (when it does)
(define T-RECEIPT 8)        ; X's receipt arrives
(define T-READ 11)
(define T-EVAL 12)
(define LAG-WATERMARK 6)    ; under lag, V's record is complete only through 6

(define-extended-language EXTERNAL DMAT0
  ;; (world a-done b-outcome report receipt read)
  (outcome complete partial none)
  (report honest premature)
  (fate delivered dropped)
  (read fresh lag unavailable)
  (w (world boolean outcome report fate read))
  (as done pending)
  (xs none partial complete)
  (view (record as) (full as xs t))
  (d (msg DONE t t) (msg RECEIPT t t xs) (read-ok t view) (read-failed t))
  (ds (d ...)))

(define world? (redex-match? EXTERNAL w))
(define ds? (redex-match? EXTERNAL ds))
