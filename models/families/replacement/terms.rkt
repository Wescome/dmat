#lang racket/base
;; Family 8 — dynamic participant replacement (Flow, Temporal). Shared terms.
;;
;; V accepts H's order and may withdraw at T-WITHDRAW; a replacement V2 is
;; then offered the role and accepts or declines at T-V2. The responsible
;; party initiates care: V at T-V-START if V never withdrew, V2 at
;; T-V2-START if V2 took over, and — under a retaining protocol — V at
;; T-RESUME if V2 declined. A withdrawn V may still emit a stale START from its
;; outbound queue (a ghost): a message from a party that is no longer
;; responsible, about care that did not happen.
;;   continuity : some party was responsible at every instant from acceptance
;;   temporal   : the responsible party initiated care by DEADLINE

(require redex/reduction-semantics "../../core/grammar.rkt")
(provide REPLACEMENT world? ds?
         T-ACCEPT T-WITHDRAW T-V2 T-V-START T-V2-START T-RESUME DEADLINE T-READ T-EVAL
         STALE-AS-OF NOTICE-DELAY ATTEST-DELAY)

(define T-ACCEPT 1)
(define T-WITHDRAW 3)
(define T-V2 5)
(define T-V-START 6)
(define T-V2-START 8)
(define T-RESUME 11)
(define DEADLINE 10)
(define T-READ 12)
(define T-EVAL 13)
(define STALE-AS-OF 4)
(define NOTICE-DELAY 1)
(define ATTEST-DELAY 2)

(define-extended-language REPLACEMENT DMAT0
  ;; (world withdraw v2-accepts start ghost notice attest read)
  (fate delivered dropped)
  (read fresh stale unavailable)
  (w (world boolean boolean boolean boolean fate fate read))
  (who V V2)
  (holder V V2 none)
  (view (registry holder boolean) (full holder boolean t))
  (d (msg ACCEPT t t) (msg WITHDRAW t t) (msg START t t who) (msg ATTEST t t who)
     (read-ok t view) (read-failed t))
  (ds (d ...)))

(define world? (redex-match? REPLACEMENT w))
(define ds? (redex-match? REPLACEMENT ds))
