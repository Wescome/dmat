#lang racket/base
;; The registry of scenario families and their arms. The benchmark, the
;; propositions and the tests reach families only through this module.

(require racket/list "core/family.rkt" "core/arm.rkt"
         (only-in "families/handoff/world.rkt" handoff)
         (rename-in (only-in "families/handoff/arms.rkt" arms) [arms handoff-arms])
         (only-in "families/reservation/world.rkt" reservation)
         (rename-in (only-in "families/reservation/arms.rkt" arms) [arms reservation-arms])
         (only-in "families/agreement/world.rkt" agreement)
         (rename-in (only-in "families/agreement/arms.rkt" arms) [arms agreement-arms])
         (only-in "families/delegation/world.rkt" delegation)
         (rename-in (only-in "families/delegation/arms.rkt" arms) [arms delegation-arms])
         (only-in "families/deadline/world.rkt" deadline)
         (rename-in (only-in "families/deadline/arms.rkt" arms) [arms deadline-arms])
         (only-in "families/external/world.rkt" external)
         (rename-in (only-in "families/external/arms.rkt" arms) [arms external-arms])
         (only-in "families/composition/world.rkt" composition)
         (rename-in (only-in "families/composition/arms.rkt" arms) [arms composition-arms])
         (only-in "families/replacement/world.rkt" replacement)
         (rename-in (only-in "families/replacement/arms.rkt" arms) [arms replacement-arms])
         (rename-in (only-in "families/handoff/cupid.rkt" cupid-arms) [cupid-arms handoff-cupid-arms])
         (rename-in (only-in "families/reservation/cupid.rkt" cupid-arms) [cupid-arms reservation-cupid-arms])
         (rename-in (only-in "families/agreement/cupid.rkt" cupid-arms) [cupid-arms agreement-cupid-arms])
         (rename-in (only-in "families/delegation/cupid.rkt" cupid-arms) [cupid-arms delegation-cupid-arms])
         (rename-in (only-in "families/deadline/cupid.rkt" cupid-arms) [cupid-arms deadline-cupid-arms])
         (rename-in (only-in "families/external/cupid.rkt" cupid-arms) [cupid-arms external-cupid-arms])
         (rename-in (only-in "families/composition/cupid.rkt" cupid-arms) [cupid-arms composition-cupid-arms])
         (rename-in (only-in "families/replacement/cupid.rkt" cupid-arms) [cupid-arms replacement-cupid-arms])
         (only-in "families/purchase/world.rkt" purchase)
         (rename-in (only-in "families/purchase/arms.rkt" arms external-arms)
                    [arms purchase-arms] [external-arms purchase-external-arms])
         (rename-in (only-in "families/purchase/cupid.rkt" cupid-arms) [cupid-arms purchase-cupid-arms]))
(provide FAMILIES family-names family-by-name arms-of arm-of ARM-NAMES
         CUPID-NAMES cupid-arms-of all-arms-of
         COMPOSITE composite-arms composite-arm PURCHASE-ARM-NAMES)

;; DMBench's eight scenario families, in benchmark order
(define FAMILIES
  (list (cons handoff handoff-arms)
        (cons reservation reservation-arms)
        (cons agreement agreement-arms)
        (cons delegation delegation-arms)
        (cons deadline deadline-arms)
        (cons external external-arms)
        (cons composition composition-arms)
        (cons replacement replacement-arms)))

(define ARM-NAMES '(chor fsm comm hybrid hybrid-noe))

;; The commitment arms (phase 3, instance I-3): a commitment evaluator over the
;; observer's information base, without (cupid) and with (cupid-e) the
;; evidential layer. They are registered apart from the five arms of the hub
;; paper, whose tables and results they leave unchanged.
(define CUPID-NAMES '(cupid cupid-e))
(define CUPID
  (list (cons 'handoff handoff-cupid-arms) (cons 'reservation reservation-cupid-arms)
        (cons 'agreement agreement-cupid-arms) (cons 'delegation delegation-cupid-arms)
        (cons 'deadline deadline-cupid-arms) (cons 'external external-cupid-arms)
        (cons 'composition composition-cupid-arms) (cons 'replacement replacement-cupid-arms)))
(define (cupid-arms-of n) (cdr (or (assq n CUPID) (error 'families "no family ~a" n))))
(define (all-arms-of n) (append (arms-of n) (cupid-arms-of n)))

(define family-names (map (λ (p) (family-name (car p))) FAMILIES))
(define (entry n) (or (findf (λ (p) (eq? (family-name (car p)) n)) FAMILIES)
                      (error 'families "no family ~a" n)))
(define (family-by-name n) (car (entry n)))
(define (arms-of n) (cdr (entry n)))
(define (arm-of fname aname)
  (or (findf (λ (a) (eq? (arm-name a) aname)) (all-arms-of fname))
      (error 'families "~a has no arm ~a" fname aname)))

(for ([p FAMILIES])
  (unless (equal? (map arm-name (cdr p)) ARM-NAMES)
    (error 'families "~a: arms ~s" (family-name (car p)) (map arm-name (cdr p))))
  (for ([a (cdr p)])
    (unless (eq? (arm-family a) (family-name (car p)))
      (error 'families "~a: arm ~a is written for ~a" (family-name (car p)) (arm-name a) (arm-family a)))))

(for ([p FAMILIES])
  (define n (family-name (car p)))
  (unless (equal? (map arm-name (cupid-arms-of n)) CUPID-NAMES)
    (error 'families "~a: commitment arms ~s" n (map arm-name (cupid-arms-of n))))
  (for ([a (cupid-arms-of n)])
    (unless (eq? (arm-family a) n)
      (error 'families "~a: arm ~a is written for ~a" n (arm-name a) (arm-family a)))))

;; The composite family (phase 3, step 3.7; specs/purchase.md): interactive, with
;; its own arm set — the reference mechanisms, the commitment arms judging the
;; hybrid's transcript, and the external (product) arms. Kept apart from the eight
;; families so that every result of the hub is unchanged.
(define PURCHASE-ARM-NAMES '(hybrid hybrid-noe cupid cupid-e product-r product-o product-r2 product-o2))
(define COMPOSITE (list (cons purchase (append purchase-arms purchase-cupid-arms purchase-external-arms))))
(define (composite-arms) (cdr (car COMPOSITE)))
(define (composite-arm name)
  (or (findf (λ (a) (eq? (arm-name a) name)) (composite-arms)) (error 'families "purchase has no arm ~a" name)))
(unless (equal? (map arm-name (composite-arms)) PURCHASE-ARM-NAMES)
  (error 'families "purchase: arms ~s" (map arm-name (composite-arms))))
