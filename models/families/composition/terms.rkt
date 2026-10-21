#lang racket/base
;; Family 7 — multi-organization composition (Flow, Temporal). Shared terms.
;;
;; H orders a service from V; V subcontracts the first stage to S, a third
;; organization, then assembles and delivers. H has no protocol with S.
;;   temporal : S initiated its stage by DEADLINE (true time) — H's dependency
;;              on a party it does not observe
;;   delivery : V delivered the assembled result by T-EVAL
;; S self-reports its stage to V (honestly, or prematurely claiming an on-time
;; start); V's case record relays it under the staged observation model only.
;; Observation models of V's case available to H (interface 'obs):
;;   coarse : (case open|closed) — open until V delivers
;;   staged : (staged closed? s-stage s-start) — S's stage as S reported it to V
;; An independent attestation of S's start exists for protocols that define one.

(require redex/reduction-semantics "../../core/grammar.rkt")
(provide COMPOSITION world? ds?
         T-COMMIT T-S-ON-TIME T-S-LATE DEADLINE T-DELIVER T-READ T-EVAL ATTEST-DELAY)

(define T-COMMIT 2)
(define T-S-ON-TIME 6)
(define T-S-LATE 12)
(define DEADLINE 10)
(define T-DELIVER 14)
(define ATTEST-DELAY 2)
(define T-READ 16)
(define T-EVAL 17)

(define-extended-language COMPOSITION DMAT0
  ;; (world s-stage s-report assemble delivered-msg attest read)
  (stage on-time late committed declined)
  (report honest premature)
  (fate delivered dropped)
  (read fresh unavailable)
  (w (world stage report boolean fate fate read))
  (cs open closed)
  (ss none committed declined started)
  (ot #f t)
  (view (case cs) (staged cs ss ot))
  (d (msg DELIVERED t t) (msg ATTEST t t) (read-ok t view) (read-failed t))
  (ds (d ...)))

(define world? (redex-match? COMPOSITION w))
(define ds? (redex-match? COMPOSITION ds))
