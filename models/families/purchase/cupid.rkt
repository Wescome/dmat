#lang racket/base
;; Family 9 — purchase. Commitment arms over the control plane's information
;; base (core/cupid.rkt), judging the hybrid mechanism's transcript.
;; specs/commitments/purchase.md.
;;
;;   C_S = C(S, P, CHARGED S by T-LATE, DELIVERED by DEADLINE)  → temporal, flow
;;   funds, fit: hold states read as the hybrid judge reads them, closed world
;;   (cupid) or with completeness points (cupid-e).

(require racket/list "../../core/arm.rkt" "../../core/observe.rkt" "../../core/cupid.rkt" "terms.rkt")
(provide cupid-arms)

(define (transcript ds) (for/list ([d ds]) (list (list-ref d 4) (list-ref d 5))))
(define (ok-sym? r v) (and (eq? (car r) 'ok) (eq? (cadr r) v)))

;; hold states, as the hybrid judge reads them
(define (holds tr evidential?)
  (define st (make-hasheq)) (define am (make-hasheq)) (define ci (make-hasheq)) (define last-call (make-hasheq))
  (for ([cr tr] [i (in-naturals)])
    (define-values (c r) (values (car cr) (cadr cr)))
    (case (car c)
      [(authorize void capture refund)
       (define s (cadr c))
       (when (eq? (car c) 'authorize) (hash-set! am s (caddr c)))
       (hash-set! last-call s (add1 i))
       (cond [(and (eq? (car r) 'ok) (symbol? (cadr r))) (hash-set! st s (cadr r)) (hash-set! ci s (list i))]
             [(eq? (cadr r) 'STATE-UNCERTAIN) (hash-set! st s 'unknown) (hash-set! ci s '())]
             [else (void)])]
      [(payment-record)
       (when (eq? (car r) 'ok)
         (define rec (cadr r)) (define cpt (cadr rec))
         (for ([s SELLERS] #:when (hash-ref last-call s #f))
           (when (or (not evidential?) (and cpt (>= cpt (hash-ref last-call s))))
             (hash-set! st s (cond [(assq s (caddr rec)) => cadr] [else 'NONE]))
             (hash-set! ci s (list i)))))]
      [else (void)]))
  (values st am ci))

(define ((judge ev) ds)
  (define tr (transcript ds))
  (define-values (st am ci) (holds tr ev))
  (define sellers (hash-keys st))
  (define (is v) (filter (λ (s) (eq? (hash-ref st s) v)) sellers))
  (define (cites-of ss) (append* (map (λ (s) (hash-ref ci s '())) ss)))
  (define funds
    (cond [(pair? (is 'AUTHORIZED)) (list 'funds 'Violated (cites-of (is 'AUTHORIZED)))]
          [(> (length (is 'CAPTURED)) 1) (list 'funds 'Violated (cites-of (is 'CAPTURED)))]
          [(pair? (is 'unknown)) (list 'funds 'Indeterminate '())]
          [else (list 'funds 'Fulfilled (cites-of sellers))]))
  (define auth-idx (for/list ([cr tr] [i (in-naturals)] #:when (eq? (car (car cr)) 'authorize)) i))
  (define over (filter (λ (s) (> (hash-ref am s 0) CAP)) (hash-keys am)))
  (define fit
    (cond [(null? over) (list 'fit 'Fulfilled auth-idx)]
          [(ormap (λ (s) (memq (hash-ref st s #f) '(CAPTURED REFUNDED))) over) (list 'fit 'Violated (cites-of over))]
          [(andmap (λ (s) (memq (hash-ref st s #f) '(AUTHORIZED VOIDED NONE))) over) (list 'fit 'Fulfilled (append auth-idx (cites-of over)))]
          [else (list 'fit 'Indeterminate '())]))
  ;; the information base for C_S
  (define facts
    (append*
     (for/list ([cr tr] [i (in-naturals)])
       (define-values (c r) (values (car cr) (cadr cr)))
       (case (car c)
         [(capture) (if (ok-sym? r 'CAPTURED) (list (fact 'CHARGED 'X 'act (add1 i) (list (cadr c)) i)) '())]
         [(refund) (if (ok-sym? r 'REFUNDED) (list (fact 'REFUNDED 'X 'act (add1 i) (list (cadr c)) i)) '())]
         [(deliver) (if (and (eq? (car r) 'ok) (number? (cadr (cadr r))))
                        (list (fact 'DELIVERED (cadr c) 'performance (cadr (cadr r)) (list (cadr c)) i)) '())]
         [(carrier-scan) (if (and (eq? (car r) 'ok) (number? (cadr (cadr r))))
                             (list (fact 'DELIVERED 'carrier 'performance (cadr (cadr r)) '() i)) '())]
         [else '()]))))
  (define covs
    (for/list ([cr tr] [i (in-naturals)] #:when (and (eq? (car (car cr)) 'carrier-scan) (eq? (car (cadr cr)) 'ok)))
      (coverage 'carrier T-LATE '(DELIVERED) i)))
  (define charges (filter (λ (f) (eq? (fact-event f) 'CHARGED)) facts))
  (define last-charged (and (pair? charges) (car (fact-attrs (last charges)))))
  (define (is-ev e) (λ (f) (eq? (fact-event f) e)))
  (define temporal+flow
    (cond
      [(not last-charged)
       (list (list 'flow 'Fulfilled (cites-of sellers))
             (list 'temporal 'Violated (list (sub1 (length tr)))))]
      [else
       (define C (commitment 'C_S last-charged 'P
                             (λ (f) (and (eq? (fact-event f) 'CHARGED) (eq? (car (fact-attrs f)) last-charged))) T-LATE
                             (is-ev 'DELIVERED) DEADLINE))
       (define-values (state cites) (commitment-state C facts covs #:evidential? ev #:a-kinds '(CHARGED) #:c-kinds '(DELIVERED)))
       (define-values (any-status any-cites)
         (event-status facts covs (is-ev 'DELIVERED) T-LATE #:evidential? ev #:debtor last-charged #:kinds '(DELIVERED)))
       (define refunded? (ormap (λ (f) (and (eq? (fact-event f) 'REFUNDED) (eq? (car (fact-attrs f)) last-charged))) facts))
       (list (cond [refunded? (dep-claim 'flow 'Fulfilled (map fact-index (filter (is-ev 'REFUNDED) facts)))]
                   [(memq any-status '(held late)) (dep-claim 'flow 'Fulfilled any-cites)]
                   [(eq? any-status 'absent) (dep-claim 'flow 'Violated any-cites)]
                   [else (dep-claim 'flow 'Indeterminate '())])
             (dep-claim 'temporal (state->judgment state #:expired 'Violated) cites))]))
  (claims funds fit (car temporal+flow) (cadr temporal+flow)))

(define P (hasheq 'mechanism 'hybrid))
(define I (hasheq 'watermark #t))
(define cupid-arms
  (list (arm 'purchase 'cupid P I (judge #f))
        (arm 'purchase 'cupid-e P I (judge #t))))
