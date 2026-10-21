#lang racket/base
;; Family 2 — resource reservation (Sharing, Temporal). Shared terms.
;;
;; An allocator V holds one exclusive resource. V grants it to H1 at
;; T-GRANT1 with a lease until LEASE-END; H2 requests it at T-REQ2.
;;   sharing  : no instant at which two holders effectively use the resource
;;   temporal : H2 is granted the resource by D2
;; H1's conduct varies: it releases early, overruns its lease (slow), or dies.
;; The arms' protocols decide when V regrants: on H1's release only, on lease
;; expiry, or on lease expiry with fencing tokens checked by the resource.

(require redex/reduction-semantics "../../core/grammar.rkt")
(provide RESERVATION world? ds?
         T-GRANT1 T-REQ2 LEASE-END T-RELEASE T-SLOW-RELEASE T-DEAD D2 T-READ T-EVAL STALE-AS-OF H2-USE)

(define T-GRANT1 1)
(define T-REQ2 2)
(define T-DEAD 2)          ; a dead H1 stops using the resource here and never releases
(define T-RELEASE 3)       ; H1 releases (when it releases on time)
(define LEASE-END 5)
(define D2 7)
(define T-SLOW-RELEASE 8)  ; an overrunning H1 uses the resource until here, then releases
(define H2-USE 2)          ; H2 uses the resource for this long once granted
(define T-READ 11)
(define T-EVAL 12)
(define STALE-AS-OF 4)

(define-extended-language RESERVATION DMAT0
  ;; (world h1 release read)
  (conduct releases slow dead)
  (fate delivered dropped)
  (read fresh stale unavailable)
  (w (world conduct fate read))
  (who h1 h2)
  (e (GRANT who t) (RELEASE t) (EXPIRE t) (USE who t t) (REJECT who t))
  (view (log t e ...))
  (d (read-ok t view) (read-failed t))
  (ds (d ...)))

(define world? (redex-match? RESERVATION w))
(define ds? (redex-match? RESERVATION ds))
