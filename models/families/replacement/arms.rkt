#lang racket/base
;; Family 8 — dynamic participant replacement. The five arms.

(require "../../core/arm.rkt" "../../core/observe.rkt" "terms.rkt")
(provide arms)

(define (sender d) (car (msg-payload d)))
(define (starts ds [from #f])
  (msg-indices ds 'START #:asserted-by DEADLINE #:where (λ (d) (or (not from) (eq? (sender d) from)))))

;; CHOR — one binary session per provider. Under the releasing protocol V's
;; WITHDRAW closes V's session and V2's session opens only on V2's acceptance,
;; at T-V2 at the earliest: the role is vacant in between, so a WITHDRAW in the
;; session is a continuity violation; without one V held the role throughout.
;; Temporal: H's projection waits for START from the provider of the current
;; session — V without a withdrawal, V2 after one — arriving by the deadline;
;; a START from a party outside that branch (a withdrawn V) is not part of the
;; session. Otherwise the START timer fired: Violated.
(define (chor-judge ds)
  (define wd (msg-indices ds 'WITHDRAW))
  (define who (if (null? wd) 'V 'V2))
  (define st (msg-indices ds 'START #:arrived-by DEADLINE #:where (λ (d) (eq? (sender d) who))))
  (claims (if (null? wd)
              (list 'continuity 'Fulfilled (msg-indices ds 'ACCEPT))
              (list 'continuity 'Violated wd))
          (if (pair? st) (list 'temporal 'Fulfilled st) (list 'temporal 'Violated (append (msg-indices ds 'ACCEPT) wd)))))

;; FSM — a role machine: held(V) → held(V2), or held(V) throughout under the
;; retaining protocol, with V resuming at T-RESUME when V2 declines. The
;; registry is authoritative: a vacant role is a break; a role with no care
;; started at the read is a violation; care started by V after a withdrawal is
;; the resume transition, which fires after the deadline (Violated).
(define (fsm-judge ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (define wd (msg-indices ds 'WITHDRAW))
  (cond [v (claims (if (eq? (cadr v) 'none) (list 'continuity 'Violated (list ri)) (list 'continuity 'Fulfilled (list ri)))
                   (cond [(not (caddr v)) (list 'temporal 'Violated (list ri))]
                         [(and (eq? (cadr v) 'V) (pair? wd)) (list 'temporal 'Violated (cons ri wd))]
                         [else (list 'temporal 'Fulfilled (list ri))]))]
        [else (claims (list 'continuity 'Indeterminate '()) (list 'temporal 'Indeterminate '()))]))

;; COMM — C(V,H, accepted, initiate care by DEADLINE) is assigned to V2 with
;; V2's acceptance; until then V remains the debtor, and V resumes it if V2
;; declines. The commitment is never released, so continuity holds. Temporal:
;; discharged by a START, asserted by the deadline, from the party that was the
;; debtor at the START's instant: V before T-V2; from T-V2, V2 if H has seen the
;; assignment (registry holder V2, or any START from V2), else V.
(define (comm-judge ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (define assigned (or (and v (eq? (cadr v) 'V2)) (pair? (msg-indices ds 'START #:where (λ (d) (eq? (sender d) 'V2))))))
  (define (debtor t) (if (and assigned (>= t T-V2)) 'V2 'V))
  (define st (msg-indices ds 'START #:asserted-by DEADLINE #:where (λ (d) (eq? (sender d) (debtor (msg-asserted d))))))
  (claims (list 'continuity 'Fulfilled (append (msg-indices ds 'ACCEPT) (if ri (list ri) '())))
          (if (pair? st) (list 'temporal 'Fulfilled st)
              (list 'temporal 'Violated (if ri (list ri) (msg-indices ds 'ACCEPT))))))

;; HYBRID — COMM's assignment, FSM's role machine with retention, and an
;; attestation of care naming the performer. Continuity is a property of the
;; commitment structure (retained or assigned, never released): Fulfilled,
;; unless a registry shows the role vacant. A performance counts only from the
;; party responsible at its instant: V2 from T-V2; V without a withdrawal,
;; before T-V2, when the registry (authoritative through T-V2) shows V still
;; holding, or in the resume transition at T-RESUME. Temporal: Fulfilled on
;; such an attestation by the deadline; Violated on one stamped after it (care
;; is initiated once), on a registry complete through the deadline showing no
;; care, or on a registry complete through T-V2 showing V holding after its
;; withdrawal (V2 declined; V resumes only after the deadline). START notices
;; and the registry's `started` flag are performers' reports (E1); the registry
;; is authoritative only up to its watermark (E2).
;; HYBRID-NOE: START notices count as performance, every read is authoritative,
;; a registry showing care started by V2 (or by V without a withdrawal) is
;; Fulfilled, and where the hybrid would abstain the commitment rule applies
;; (care not seen initiated by the deadline: Violated).
(define ((hybrid-judge evidence?) ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (define-values (holder started wm) (if v (values (list-ref v 1) (list-ref v 2) (list-ref v 3)) (values #f #f #f)))
  (define (auth? due) (and v (or (not evidence?) (>= wm due))))
  (define wd (msg-indices ds 'WITHDRAW))
  (define holder-after-v2 (and (auth? T-V2) holder))
  (define (responsible? d)
    (define t (msg-asserted d))
    (case (sender d)
      [(V2) (>= t T-V2)]
      [(V) (or (null? wd) (< t T-V2) (eq? holder-after-v2 'V) (>= t T-RESUME))]
      [else #f]))
  (define kinds (if evidence? '(ATTEST) '(ATTEST START)))
  (define (perf pred)
    (sort (apply append (for/list ([k kinds])
                          (msg-indices ds k #:where (λ (d) (and (responsible? d) (pred (msg-asserted d)))))))
          <))
  (define in-time (perf (λ (t) (<= t DEADLINE))))
  (define late (perf (λ (t) (> t DEADLINE))))
  (define rc (if ri (list ri) '()))
  (claims (cond [(and v (eq? holder 'none)) (list 'continuity 'Violated rc)]
                [else (list 'continuity 'Fulfilled (append (msg-indices ds 'ACCEPT) (if (auth? T-V2) rc '())))])
          (cond [(pair? in-time) (list 'temporal 'Fulfilled in-time)]
                [(pair? late) (list 'temporal 'Violated late)]
                [(and (auth? DEADLINE) (not started)) (list 'temporal 'Violated rc)]
                [(and (pair? wd) (eq? holder-after-v2 'V)) (list 'temporal 'Violated (append rc wd))]
                [(and (not evidence?) v started (or (eq? holder 'V2) (and (eq? holder 'V) (null? wd))))
                 (list 'temporal 'Fulfilled rc)]
                [(not evidence?) (list 'temporal 'Violated (append (msg-indices ds 'ACCEPT) rc))]
                [else (list 'temporal 'Indeterminate '())])))

(define arms
  (list (arm 'replacement 'chor (hasheq 'on-withdraw 'release) (hasheq 'attest? #f 'view 'registry) chor-judge)
        (arm 'replacement 'fsm (hasheq 'on-withdraw 'retain) (hasheq 'attest? #f 'view 'registry) fsm-judge)
        (arm 'replacement 'comm (hasheq 'on-withdraw 'retain) (hasheq 'attest? #f 'view 'registry) comm-judge)
        (arm 'replacement 'hybrid (hasheq 'on-withdraw 'retain) (hasheq 'attest? #t 'view 'full) (hybrid-judge #t))
        (arm 'replacement 'hybrid-noe (hasheq 'on-withdraw 'retain) (hasheq 'attest? #t 'view 'full) (hybrid-judge #f))))
