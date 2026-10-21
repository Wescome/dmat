#lang racket/base
;; Independent commitment arms (cupid, cupid-e) for family `replacement`.
;; Written from specs/commitments/replacement.md, specs/replacement.md,
;; specs/bspl/replacement.bspl and specs/commitments/README.md only.
;;
;; Registry authority after T-V2: a read (full holder started as-of) is
;; authoritative there in cupid-e iff as-of >= T-V2, in cupid for any read.
;; A START/ATTEST naming `who` at t is from the responsible party iff
;;   who = V2 and t >= T-V2; or
;;   who = V and (no WITHDRAW delivered, or t < T-V2, or the authoritative
;;   registry shows holder = V, or t >= T-RESUME).
;; Information base (observer H):
;;   responsible (msg START a t who)  -> START, role, performance, t, (who)
;;   responsible (msg ATTEST a t who) -> START, attester A, performance, t, (who)
;;   (read-ok 12 (full holder #f as-of)) -> coverage registry through as-of for START
;;   (started = #t yields no fact and no coverage; non-responsible messages nothing)
;; Commitment: C = C(role, H, T, START by DEADLINE).
;; Judgments:
;;   continuity: Violated if a read shows holder = none (cite it); else Fulfilled
;;               (cite the ACCEPT, and the read when authoritative after T-V2).
;;   temporal: discharged -> Fulfilled; violated -> Violated (state's cites);
;;             else, WITHDRAW delivered and authoritative registry shows
;;             holder = V -> Violated (cite read and WITHDRAW); else Indeterminate.
;;
;; AMBIGUITY: the `registry` view form `(registry holder started)` (other arms'
;; interface) is accepted as a read without an as-of: authoritative after
;; T-V2 in `cupid` (any read), never in `cupid-e`; it yields no coverage since
;; it has no completeness instant. `holder = none` in it still makes
;; continuity Violated.
;; AMBIGUITY: "a WITHDRAW was delivered" means any (msg WITHDRAW ...) delivery,
;; regardless of its instants.

(require racket/list
         "../core/arm.rkt" "../core/observe.rkt" "../core/cupid.rkt"
         "../families/replacement/terms.rkt")
(provide cupid-arms)

;; → (values holder-or-#f started as-of-or-#f read-index-or-#f)
(define (registry ds)
  (define i (read-index ds))
  (define v (read-view ds))
  (cond
    [(and i (pair? v) (eq? (car v) 'full)) (values (cadr v) (caddr v) (cadddr v) i)]
    [(and i (pair? v) (eq? (car v) 'registry)) (values (cadr v) (caddr v) #f i)]
    [else (values #f #f #f #f)]))

(define ((judge evidential?) ds)
  (define-values (holder started as-of ri) (registry ds))
  (define authoritative?
    (and ri (if evidential? (and as-of (>= as-of T-V2)) #t)))
  (define withdraws (map car (msgs ds 'WITHDRAW)))
  (define (responsible? who t)
    (case who
      [(V2) (>= t T-V2)]
      [(V) (or (null? withdraws)
               (< t T-V2)
               (and authoritative? (eq? holder 'V))
               (>= t T-RESUME))]
      [else #f]))
  (define facts
    (for/list ([d ds] [i (in-naturals)]
               #:when (and (eq? (car d) 'msg) (memq (cadr d) '(START ATTEST))
                           (pair? (msg-payload d))
                           (responsible? (car (msg-payload d)) (msg-asserted d))))
      (fact 'START (if (eq? (cadr d) 'START) 'role 'A) 'performance
            (msg-asserted d) (list (car (msg-payload d))) i)))
  (define covs
    (if (and ri as-of (not started))
        (list (coverage 'registry as-of '(START) ri))
        '()))
  (define C (commitment 'C 'role 'H 'true 0 (λ (f) (eq? (fact-event f) 'START)) DEADLINE))
  (define-values (st sc) (commitment-state C facts covs #:evidential? evidential?
                                           #:a-kinds '() #:c-kinds '(START)))
  (define accepts (map car (msgs ds 'ACCEPT)))
  (define continuity
    (if (and ri (eq? holder 'none))
        (dep-claim 'continuity 'Violated (list ri))
        (dep-claim 'continuity 'Fulfilled (append accepts (if authoritative? (list ri) '())))))
  (define temporal
    (case st
      [(discharged) (dep-claim 'temporal 'Fulfilled sc)]
      [(violated) (dep-claim 'temporal 'Violated sc)]
      [else
       (if (and (pair? withdraws) authoritative? (eq? holder 'V))
           (dep-claim 'temporal 'Violated (cons ri withdraws))
           (dep-claim 'temporal 'Indeterminate '()))]))
  (claims continuity temporal))

(define PROTOCOL (hasheq 'on-withdraw 'retain))
(define INTERFACE (hasheq 'attest? #t 'view 'full))

(define cupid-arms
  (list (arm 'replacement 'cupid PROTOCOL INTERFACE (judge #f))
        (arm 'replacement 'cupid-e PROTOCOL INTERFACE (judge #t))))
