#lang racket/base
;; Family 1 — information handoff (Flow, Temporal). Shared terms.
;;
;; A hospital H refers a patient to a home-care provider V.
;;   flow     : V accepted by ACCEPT-DEADLINE (responsibility transferred in time)
;;   temporal : care was initiated by DEADLINE
;; Timing varies per run: V may accept on time or late; the acceptance reply
;; may be fast or slow, so it can arrive after the start notice (reordering).

(require redex/reduction-semantics "../../core/grammar.rkt")
(provide HANDOFF world? view? ds?
         T-ON-TIME T-LATE ACCEPT-DEADLINE T-START T-NOTICE T-ATTEST DEADLINE T-READ T-EVAL
         STALE-AS-OF LAG-WATERMARK FAST SLOW)

(define T-ON-TIME 1)        ; V accepts on time
(define T-LATE 4)           ; V accepts late
(define ACCEPT-DEADLINE 3)
(define FAST 1)             ; reply transit when fast
(define SLOW 4)             ; reply transit when slow
(define T-START 5)          ; V initiates care (when it does)
(define T-NOTICE 6)         ; the start notice arrives
(define T-ATTEST 7)         ; the independent attestation arrives
(define DEADLINE 10)
(define T-READ 11)
(define T-EVAL 12)
(define STALE-AS-OF 0)
(define LAG-WATERMARK 3)    ; under record lag, V's record is complete only through 3

(define-extended-language HANDOFF DMAT0
  ;; (world accept start crash report reply reply-delay notice attest read record)
  (accept on-time late no)
  (report honest premature)
  (reply delivered dropped duplicated)
  (delay fast slow)
  (fate delivered dropped)
  (read fresh stale unavailable)
  (record complete lag)
  (w (world accept b b report reply delay fate fate read record))
  (S referred accepted started)
  (ot #f t)
  (c0 none discharged late-discharged)
  (c1 none detached discharged)
  (lm none (ACCEPT t) (START t))
  (view (last-message lm) (state S) (ledger c0 c1) (full S ot ot c0 c1 t))
  (d (msg ACCEPT t t) (msg START t t) (msg ATTEST t t) (read-ok t view) (read-failed t))
  (ds (d ...)))

(define world? (redex-match? HANDOFF w))
(define view? (redex-match? HANDOFF view))
(define ds? (redex-match? HANDOFF ds))
