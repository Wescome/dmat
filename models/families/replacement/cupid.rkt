#lang racket/base
;; Family 8 — dynamic participant replacement. Commitment arms over the
;; hospital H's information base (core/cupid.rkt), with the hybrid's protocol:
;; V retains the role until V2 accepts, and resumes it if V2 declines.
;;
;;   C = C(role, H, ⊤, START by DEADLINE)          → temporal
;;       The debtor is the role, held by V and, after an assignment, by V2. A
;;       START counts only from the party responsible at its instant: V2 from
;;       T-V2; V without a withdrawal, before T-V2, when the registry shows V
;;       holding after T-V2 (V2 declined), or at T-RESUME. If V holds the role
;;       after its withdrawal, the protocol schedules care at T-RESUME, after
;;       the deadline: Violated.
;;   continuity: Fulfilled (the role is retained or assigned, never released)
;;       unless the registry shows it vacant.
;;
;; Information: ACCEPT and WITHDRAW are V's acts; a START notice is the role
;; holder's report of its own performance; ATTEST, naming the performer, is a
;; third party's report; the registry (holder, and whether care started, with
;; no instant) is a coverage of START through its as-of instant, except when it
;; shows care started, since a record reporting the event cannot show its
;; absence. The registry's untimed `started` flag is no START event: a query
;; for START by the deadline needs an instant.
;; cupid: closed-world reading, every registry read authoritative.
;; cupid-e: E1–E3.

(require racket/list "../../core/arm.rkt" "../../core/observe.rkt" "../../core/cupid.rkt" "terms.rkt")
(provide cupid-arms)

(define (sender d) (car (msg-payload d)))

(define ((judge ev) ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (define-values (holder started wm) (if v (values (list-ref v 1) (list-ref v 2) (list-ref v 3)) (values #f #f #f)))
  (define (auth? due) (and v (or (not ev) (>= wm due))))
  (define wd (msg-indices ds 'WITHDRAW))
  (define holder-after-v2 (and (auth? T-V2) holder))
  (define (responsible? who t)
    (case who
      [(V2) (>= t T-V2)]
      [(V) (or (null? wd) (< t T-V2) (eq? holder-after-v2 'V) (>= t T-RESUME))]
      [else #f]))
  (define facts
    (append
     (for/list ([i (msg-indices ds 'START)] #:when (responsible? (sender (list-ref ds i)) (msg-asserted (list-ref ds i))))
       (fact 'START 'role 'performance (msg-asserted (list-ref ds i)) (list (sender (list-ref ds i))) i))
     (for/list ([i (msg-indices ds 'ATTEST)] #:when (responsible? (sender (list-ref ds i)) (msg-asserted (list-ref ds i))))
       (fact 'START 'attester 'performance (msg-asserted (list-ref ds i)) (list (sender (list-ref ds i))) i))))
  (define covs (if (and v (not started)) (list (coverage 'registry wm '(START) ri)) '()))
  (define C (commitment 'C 'role 'H 'true 0 (λ (f) (eq? (fact-event f) 'START)) DEADLINE))
  (define-values (st cites) (commitment-state C facts covs #:evidential? ev #:a-kinds '() #:c-kinds '(START)))
  (define rc (if ri (list ri) '()))
  (claims (if (and v (eq? holder 'none))
              (dep-claim 'continuity 'Violated rc)
              (dep-claim 'continuity 'Fulfilled (append (msg-indices ds 'ACCEPT) (if (auth? T-V2) rc '()))))
          (cond [(memq st '(discharged violated)) (dep-claim 'temporal (state->judgment st) cites)]
                [(and (pair? wd) (eq? holder-after-v2 'V)) (dep-claim 'temporal 'Violated (append rc wd))]
                [else (dep-claim 'temporal (state->judgment st) cites)])))

(define P (hasheq 'on-withdraw 'retain))
(define I (hasheq 'attest? #t 'view 'full))
(define cupid-arms
  (list (arm 'replacement 'cupid P I (judge #f))
        (arm 'replacement 'cupid-e P I (judge #t))))
