#lang racket/base
;; Independent commitment arms (cupid, cupid-e) for family `composition`.
;; Written from specs/commitments/composition.md, specs/composition.md,
;; specs/bspl/composition.bspl and specs/commitments/README.md only.
;;
;; Information base (observer H); no coverages (V's case record has no watermark):
;;   (msg ATTEST a t)         -> START, attester A, performance, t
;;   (msg DELIVERED a t)      -> DELIVERED, V, act, t
;;   (read-ok 16 (staged cs ss ot))
;;                            -> ss = started: START, S, performance, ot;
;;                               ss = declined: DECLINE, S, act, T-COMMIT;
;;                               cs = closed: DELIVERED, V, performance, T-DELIVER
;; Commitments: C_t = C(S, H, T, START by DEADLINE); C_d = C(V, H, T, DELIVERED by T-EVAL).
;; Judgments:
;;   temporal: a DECLINE fact => Violated (cite it) unless C_t discharged;
;;             otherwise <- C_t.
;;   delivery <- C_d.
;;
;; AMBIGUITY: the coarse view `(case cs)` (the family requires judges to accept
;; both view forms) is read like the cs part of the staged view: cs = closed
;; yields DELIVERED, V, performance, T-DELIVER; nothing about S.
;; AMBIGUITY: a staged view with ss = started and ot = #f (not produced by the
;; family, but not excluded by the grammar) yields no START fact, since the
;; START query needs an instant.

(require racket/list
         "../core/arm.rkt" "../core/observe.rkt" "../core/cupid.rkt"
         "../families/composition/terms.rkt")
(provide cupid-arms)

(define (info-base ds)
  (define facts '())
  (define (add! f) (set! facts (cons f facts)))
  (for ([d ds] [i (in-naturals)])
    (case (car d)
      [(msg)
       (define t (msg-asserted d))
       (case (cadr d)
         [(ATTEST) (add! (fact 'START 'A 'performance t '() i))]
         [(DELIVERED) (add! (fact 'DELIVERED 'V 'act t '() i))]
         [else (void)])]
      [(read-ok)
       (define v (caddr d))
       (when (pair? v)
         (case (car v)
           [(staged)
            (define cs (list-ref v 1))
            (define ss (list-ref v 2))
            (define ot (list-ref v 3))
            (when (and (eq? ss 'started) ot) (add! (fact 'START 'S 'performance ot '() i)))
            (when (eq? ss 'declined) (add! (fact 'DECLINE 'S 'act T-COMMIT '() i)))
            (when (eq? cs 'closed) (add! (fact 'DELIVERED 'V 'performance T-DELIVER '() i)))]
           [(case)
            (when (eq? (cadr v) 'closed) (add! (fact 'DELIVERED 'V 'performance T-DELIVER '() i)))]
           [else (void)]))]
      [else (void)]))
  (reverse facts))

(define (ev? e) (λ (f) (eq? (fact-event f) e)))
(define C_t (commitment 'C_t 'S 'H 'true 0 (ev? 'START) DEADLINE))
(define C_d (commitment 'C_d 'V 'H 'true 0 (ev? 'DELIVERED) T-EVAL))

(define ((judge evidential?) ds)
  (define facts (info-base ds))
  (define-values (st ct) (commitment-state C_t facts '() #:evidential? evidential?
                                           #:a-kinds '() #:c-kinds '(START)))
  (define-values (sd cd) (commitment-state C_d facts '() #:evidential? evidential?
                                           #:a-kinds '() #:c-kinds '(DELIVERED)))
  (define declines (map fact-index (filter (ev? 'DECLINE) facts)))
  (claims (if (and (pair? declines) (not (eq? st 'discharged)))
              (dep-claim 'temporal 'Violated declines)
              (dep-claim 'temporal (state->judgment st) ct))
          (dep-claim 'delivery (state->judgment sd) cd)))

(define PROTOCOL (hasheq))
(define INTERFACE (hasheq 'obs 'staged 'attest? #t))

(define cupid-arms
  (list (arm 'composition 'cupid PROTOCOL INTERFACE (judge #f))
        (arm 'composition 'cupid-e PROTOCOL INTERFACE (judge #t))))
