#lang racket/base
;; Family 2 — resource reservation. Commitment arms over the auditor's
;; information base (core/cupid.rkt), with the hybrid's protocol: expiry with
;; fencing tokens.
;;
;;   C2 = C(V, h2, ⊤, granted(h2) by D2)                → temporal
;;        granted(h2) is evidenced by V's GRANT entry (V's report of its own
;;        performance), by the resource's USE by h2, or by the resource's
;;        REJECT of h1 (a superseded token is refused only once h2 holds one)
;;   M  = maintenance commitment of V to both holders: no instant with two
;;        effective users                              → sharing
;;
;; Information: V's log (GRANT, RELEASE, EXPIRE) and the resource's access log
;; (USE, REJECT), each a coverage through the read's as-of instant.
;; cupid: closed world — sharing violated if the uses overlap, or if V's own
;; entries show h2 granted before h1's tenure ended; otherwise fulfilled.
;; cupid-e: only the resource's uses can show an overlap; the fencing tokens
;; the resource checks are evidence that none occurred.

(require racket/list "../../core/arm.rkt" "../../core/observe.rkt" "../../core/cupid.rkt" "terms.rkt")
(provide cupid-arms)

(define (info ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (cond
    [(not v) (values '() '() #f)]
    [else
     (define as-of (cadr v))
     (define facts
       (for/list ([e (cddr v)])
         (case (car e)
           [(GRANT) (fact 'GRANT 'V 'performance (caddr e) (list (cadr e)) ri)]
           [(RELEASE) (fact 'RELEASE 'h1 'act (cadr e) '() ri)]
           [(EXPIRE) (fact 'EXPIRE 'V 'act (cadr e) '() ri)]
           [(USE) (fact 'USE 'resource 'performance (caddr e) (list (cadr e) (caddr e) (cadddr e)) ri)]
           [(REJECT) (fact 'REJECT 'resource 'act (caddr e) (list (cadr e)) ri)])))
     (values facts
             (list (coverage 'V as-of '(GRANT RELEASE EXPIRE) ri)
                   (coverage 'resource as-of '(USE REJECT) ri))
             ri)]))

(define (granted-h2? f)
  (or (and (eq? (fact-event f) 'GRANT) (eq? (car (fact-attrs f)) 'h2))
      (and (eq? (fact-event f) 'USE) (eq? (car (fact-attrs f)) 'h2))
      (and (eq? (fact-event f) 'REJECT) (eq? (car (fact-attrs f)) 'h1))))
(define C2 (commitment 'C2 'V 'h2 'true 0 granted-h2? D2))

(define (overlap? facts)
  (define uses (filter (λ (f) (eq? (fact-event f) 'USE)) facts))
  (for*/or ([a uses] [b uses] #:unless (eq? (car (fact-attrs a)) (car (fact-attrs b))))
    (define-values (fa ta) (values (cadr (fact-attrs a)) (caddr (fact-attrs a))))
    (define-values (fb tb) (values (cadr (fact-attrs b)) (caddr (fact-attrs b))))
    (and (< fa tb) (< fb ta))))

(define (first-time facts ev [who #f])
  (for/first ([f (sort facts < #:key fact-time)]
              #:when (and (eq? (fact-event f) ev) (or (not who) (eq? (car (fact-attrs f)) who))))
    (fact-time f)))

(define ((judge ev) ds)
  (define-values (facts covs ri) (info ds))
  (define-values (s2 c2) (commitment-state C2 facts covs #:evidential? ev #:a-kinds '() #:c-kinds '(GRANT USE REJECT)))
  (define cites (if ri (list ri) '()))
  (define sharing
    (cond
      [(overlap? facts) 'Violated]
      [ev (if ri 'Fulfilled 'Indeterminate)]
      [else
       ;; closed world over V's entries: h2's grant must follow h1's release or expiry
       (define g2 (first-time facts 'GRANT 'h2))
       (define ends (filter values (list (first-time facts 'RELEASE) (first-time facts 'EXPIRE))))
       (if (and g2 (or (null? ends) (> (apply min ends) g2))) 'Violated 'Fulfilled)]))
  (claims (dep-claim 'sharing sharing cites)
          (dep-claim 'temporal (state->judgment s2) c2)))

(define P (hasheq 'regrant 'expiry-fenced))
(define I (hasheq 'records '(GRANT RELEASE EXPIRE USE REJECT)))
(define cupid-arms
  (list (arm 'reservation 'cupid P I (judge #f))
        (arm 'reservation 'cupid-e P I (judge #t))))
