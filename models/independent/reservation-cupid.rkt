#lang racket/base
;; Independent commitment arms (cupid, cupid-e) for family `reservation`.
;; Written from specs/commitments/reservation.md, specs/reservation.md,
;; specs/bspl/reservation.bspl and specs/commitments/README.md only.
;;
;; Information base (observer: auditor U), from (read-ok 11 (log as-of e ...)):
;;   (GRANT who t)        -> GRANT,  V,        performance, t,  (who)
;;   (RELEASE t)          -> RELEASE, h1,      act,         t
;;   (EXPIRE t)           -> EXPIRE, V,        act,         t
;;   (USE who from to)    -> USE,    resource, performance, to, (who from to)
;;   (REJECT who t)       -> REJECT, resource, act,         t,  (who)
;;   coverages: V through as-of for GRANT RELEASE EXPIRE;
;;              resource through as-of for USE REJECT.
;; Commitments:
;;   C2 = C(V, h2, T, granted(h2) by D2), granted(h2) = GRANT to h2 | USE by h2
;;        | REJECT of h1.
;;   M  = maintenance (side rule below).
;; Judgments:
;;   sharing: Violated on two overlapping USE facts of different holders;
;;            else cupid-e: Fulfilled iff the log was read; cupid: Violated iff
;;            a GRANT to h2 and no RELEASE/EXPIRE, or the earliest of them is
;;            strictly after that grant; else Fulfilled.
;;   temporal <- C2.
;;
;; AMBIGUITY: "cite the read" for `sharing` — cites the read-ok delivery. With
;; read-failed, `cupid` judges sharing Fulfilled (closed world over an empty
;; base) and cites nothing, since a failed read carries no information (this
;; matches the evaluator, which cites only coverages for an absence).
;; AMBIGUITY: with several GRANTs to h2, the cupid sharing rule uses the
;; earliest GRANT to h2.
;; AMBIGUITY: "earliest of them after that grant" is read strictly (>): a
;; RELEASE/EXPIRE at the grant instant does not make the grant an overcommit.

(require racket/list
         "../core/arm.rkt" "../core/observe.rkt" "../core/cupid.rkt"
         "../families/reservation/terms.rkt")
(provide cupid-arms)

(define (info-base ds)
  (define i (read-index ds))
  (define v (read-view ds))
  (cond
    [(and i (pair? v) (eq? (car v) 'log))
     (define as-of (cadr v))
     (define facts
       (for/list ([e (cddr v)])
         (case (car e)
           [(GRANT) (fact 'GRANT 'V 'performance (caddr e) (list (cadr e)) i)]
           [(RELEASE) (fact 'RELEASE 'h1 'act (cadr e) '() i)]
           [(EXPIRE) (fact 'EXPIRE 'V 'act (cadr e) '() i)]
           [(USE) (fact 'USE 'resource 'performance (cadddr e) (list (cadr e) (caddr e) (cadddr e)) i)]
           [(REJECT) (fact 'REJECT 'resource 'act (caddr e) (list (cadr e)) i)])))
     (values facts
             (list (coverage 'V as-of '(GRANT RELEASE EXPIRE) i)
                   (coverage 'resource as-of '(USE REJECT) i))
             i)]
    [else (values '() '() #f)]))

(define (granted-h2? f)
  (define a (fact-attrs f))
  (case (fact-event f)
    [(GRANT USE) (and (pair? a) (eq? (car a) 'h2))]
    [(REJECT) (and (pair? a) (eq? (car a) 'h1))]
    [else #f]))

(define C2 (commitment 'C2 'V 'h2 'true 0 granted-h2? D2))

(define (overlap? facts)
  (define uses (filter (λ (f) (eq? (fact-event f) 'USE)) facts))
  (for*/or ([a uses] [b uses])
    (define aa (fact-attrs a))
    (define ba (fact-attrs b))
    (and (not (eq? (car aa) (car ba)))
         (< (cadr aa) (caddr ba))
         (< (cadr ba) (caddr aa)))))

(define (cupid-overcommit? facts)
  (define g2 (filter (λ (f) (and (eq? (fact-event f) 'GRANT) (eq? (car (fact-attrs f)) 'h2))) facts))
  (and (pair? g2)
       (let* ([tg (apply min (map fact-time g2))]
              [ends (filter (λ (f) (memq (fact-event f) '(RELEASE EXPIRE))) facts)])
         (or (null? ends)
             (> (apply min (map fact-time ends)) tg)))))

(define ((judge evidential?) ds)
  (define-values (facts covs ri) (info-base ds))
  (define rc (if ri (list ri) '()))
  (define sharing
    (cond
      [(overlap? facts) (dep-claim 'sharing 'Violated rc)]
      [evidential?
       (if ri (dep-claim 'sharing 'Fulfilled rc) (dep-claim 'sharing 'Indeterminate '()))]
      [(cupid-overcommit? facts) (dep-claim 'sharing 'Violated rc)]
      [else (dep-claim 'sharing 'Fulfilled rc)]))
  (define-values (s2 c2) (commitment-state C2 facts covs #:evidential? evidential?
                                           #:a-kinds '() #:c-kinds '(GRANT USE REJECT)))
  (claims sharing
          (dep-claim 'temporal (state->judgment s2) c2)))

(define PROTOCOL (hasheq 'regrant 'expiry-fenced))
(define INTERFACE (hasheq 'records '(GRANT RELEASE EXPIRE USE REJECT)))

(define cupid-arms
  (list (arm 'reservation 'cupid PROTOCOL INTERFACE (judge #f))
        (arm 'reservation 'cupid-e PROTOCOL INTERFACE (judge #t))))
