#lang racket/base
;; Family 4 — conditional delegation (Flow, with responsibility continuity).
;;
;; A hospital H refers a patient to provider V; V accepts. When V lacks
;; capacity it delegates to a subcontractor S, which accepts or declines.
;; Whoever is responsible initiates care (or fails to). The arms' protocols
;; differ in what delegation does to V's responsibility: released when V hands
;; off ('release), or retained until S accepts and reactivated if S declines
;; ('retain, the outsourcing pattern).
;;   continuity : at no instant between acceptance and care initiation (or
;;                evaluation) is the obligation owned by nobody
;;   temporal   : care initiated by DEADLINE

(require redex/reduction-semantics "../../core/grammar.rkt")
(provide DELEGATION world? ds?
         T-ACCEPT T-DELEGATE T-S-RESPONSE T-START T-RESUME-START DEADLINE T-READ T-EVAL STALE-AS-OF NOTICE-DELAY ATTEST-DELAY)

(define T-ACCEPT 1)
(define T-DELEGATE 2)
(define T-S-RESPONSE 3)
(define T-START 5)          ; V (with capacity) or S initiates care
(define T-RESUME-START 8)   ; V, having retained responsibility after S declined, initiates care
(define DEADLINE 10)
(define T-READ 11)
(define T-EVAL 12)
(define STALE-AS-OF 2)
(define NOTICE-DELAY 1)
(define ATTEST-DELAY 2)

(define-extended-language DELEGATION DMAT0
  ;; (world capacity s-accepts start delegated-msg notice attest read)
  (fate delivered dropped)
  (read fresh stale unavailable)
  (w (world b b b fate fate fate read))
  (lm ACCEPT DELEGATED START)
  (vs accepted delegating delegated released resumed started sub-started)
  (c1 active pending discharged released)
  (c2 none active declined discharged)
  (stage none committed declined started)
  (view (last-message lm) (state vs) (ledger c1 c2) (full vs c1 c2 stage t))
  (d (msg ACCEPT t t) (msg DELEGATED t t) (msg START t t) (msg ATTEST t t) (read-ok t view) (read-failed t))
  (ds (d ...)))

(define world? (redex-match? DELEGATION w))
(define ds? (redex-match? DELEGATION ds))
