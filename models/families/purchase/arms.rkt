#lang racket/base
;; Family 9 — purchase. The arms' judges: claims from the transcript alone.
;; Conduct is in mechanisms.rkt (reference arms) or in the external arm's own
;; process (external arms, whose claims are their own, read from the stored runs).
;;
;; hybrid (E1–E3):
;;   - hold states: the processor's replies to authorize, void, capture and refund
;;     are its own acts on the hold and establish the state they report; an
;;     unknown reply leaves the hold unresolved; a payment record establishes a
;;     seller's hold only when its completeness point covers the last payment
;;     call to that seller before the read (E2);
;;   - amounts: the arm's own authorize calls (every hold comes from one);
;;   - delivery: the carrier's scan (a third party). The seller's delivery report
;;     is the seller's report of its own performance and establishes nothing (E1);
;;     a scan answering "none" shows the goods undelivered at the read;
;;   - otherwise Indeterminate (E3).
;; hybrid-noe: every record is current and every report is fact.

(require racket/list "../../core/arm.rkt" "../../core/observe.rkt" "terms.rkt" "external-cache.rkt")
(provide arms external-arms)

(define PAYMENT-OPS '(authorize void capture refund))

(define (transcript ds) (for/list ([d ds]) (list (list-ref d 4) (list-ref d 5))))

;; → (values states amounts cites): seller → state | 'unknown, seller → amount, seller → cites
(define (holds tr evidential?)
  (define st (make-hasheq)) (define am (make-hasheq)) (define ci (make-hasheq)) (define last-call (make-hasheq))
  (for ([cr tr] [i (in-naturals)])
    (define-values (c r) (values (car cr) (cadr cr)))
    (define n (add1 i))
    (case (car c)
      [(authorize void capture refund)
       (define s (cadr c))
       (when (eq? (car c) 'authorize) (hash-set! am s (caddr c)))
       (hash-set! last-call s n)
       (cond [(and (eq? (car r) 'ok) (symbol? (cadr r)))
              (hash-set! st s (cadr r)) (hash-set! ci s (list i))]
             [(eq? (cadr r) 'STATE-UNCERTAIN) (hash-set! st s 'unknown) (hash-set! ci s '())]
             [else (void)])]                                  ; refused: no effect, state unchanged
      [(payment-record)
       (when (eq? (car r) 'ok)
         (define rec (cadr r)) (define cpt (cadr rec))
         (for ([s SELLERS] #:when (hash-ref last-call s #f))
           (when (or (not evidential?) (and cpt (>= cpt (hash-ref last-call s))))
             (hash-set! st s (cond [(assq s (caddr rec)) => cadr] [else 'NONE]))
             (hash-set! ci s (list i)))))]
      [else (void)]))
  (values st am ci))

(define ((judge evidential?) ds)
  (define tr (transcript ds))
  (define-values (st am ci) (holds tr evidential?))
  (define sellers (hash-keys st))
  (define (is v) (filter (λ (s) (eq? (hash-ref st s) v)) sellers))
  (define unknown (is 'unknown))
  (define (cites-of ss) (append* (map (λ (s) (hash-ref ci s '())) ss)))
  (define all-cites (cites-of sellers))
  ;; funds
  (define funds
    (cond [(pair? (is 'AUTHORIZED)) (list 'funds 'Violated (cites-of (is 'AUTHORIZED)))]
          [(> (length (is 'CAPTURED)) 1) (list 'funds 'Violated (cites-of (is 'CAPTURED)))]
          [(pair? unknown) (list 'funds 'Indeterminate '())]
          [else (list 'funds 'Fulfilled all-cites)]))
  ;; fit: every hold comes from one of the arm's own authorize calls
  (define auth-idx (for/list ([cr tr] [i (in-naturals)] #:when (eq? (car (car cr)) 'authorize)) i))
  (define over (filter (λ (s) (> (hash-ref am s 0) CAP)) (hash-keys am)))
  (define fit
    (cond [(null? over) (list 'fit 'Fulfilled auth-idx)]
          [(ormap (λ (s) (memq (hash-ref st s #f) '(CAPTURED REFUNDED))) over) (list 'fit 'Violated (cites-of over))]
          [(andmap (λ (s) (memq (hash-ref st s #f) '(AUTHORIZED VOIDED NONE))) over) (list 'fit 'Fulfilled (append auth-idx (cites-of over)))]
          [else (list 'fit 'Indeterminate '())]))
  ;; delivery evidence
  (define shipped (for/first ([cr tr] [i (in-naturals)] #:when (and (eq? (car (car cr)) 'ship) (eq? (car (cadr cr)) 'ok)))
                    (cons (cadr (car cr)) i)))
  (define scan (for/last ([cr tr] [i (in-naturals)] #:when (and (eq? (car (car cr)) 'carrier-scan) (eq? (car (cadr cr)) 'ok)))
                 (cons (cadr (cadr (cadr cr))) i)))      ; (t-or-none . index)
  (define report (for/last ([cr tr] [i (in-naturals)] #:when (eq? (car (car cr)) 'deliver))
                   (cons (if (eq? (car (cadr cr)) 'ok) (cadr (cadr (cadr cr))) 'none) i)))
  ;; delivered: (cons instant-or-'none cites), or #f when not established
  (define delivered
    (cond [(not shipped) '(none)]                                     ; nothing was ever in transit: the arm's own acts
          [scan (list (car scan) (cdr scan))]
          [(and (not evidential?) report) (list (car report) (cdr report))]
          [else #f]))
  (define charged (is 'CAPTURED))
  (define flow
    (cond [(and (null? charged) (null? unknown)) (list 'flow 'Fulfilled all-cites)]
          [(and delivered (number? (car delivered)) shipped (andmap (λ (s) (eq? s (car shipped))) charged) (null? unknown))
           (list 'flow 'Fulfilled (append (cites-of charged) (cdr delivered)))]
          [(and delivered (eq? (car delivered) 'none) (pair? charged)) (list 'flow 'Violated (append (cites-of charged) (cdr delivered)))]
          [else (list 'flow 'Indeterminate '())]))
  (define temporal
    (cond [(not delivered) (list 'temporal 'Indeterminate '())]
          [(eq? (car delivered) 'none)
           ;; with nothing shipped the claim rests on the whole transcript: cite its last delivery
           (list 'temporal 'Violated (if shipped (cdr delivered) (list (sub1 (length tr)))))]
          [(<= (car delivered) DEADLINE) (list 'temporal 'Fulfilled (cdr delivered))]
          [else (list 'temporal 'Violated (cdr delivered))]))
  (claims funds fit flow temporal))

(define P (λ (m) (hasheq 'mechanism m)))
(define I (hasheq 'watermark #t))
(define arms
  (list (arm 'purchase 'hybrid (P 'hybrid) I (judge #t))
        (arm 'purchase 'hybrid-noe (P 'hybrid-noe) I (judge #f))))

;; external arms: their own claims, as stored with their runs
(define ((external-judge name) ds)
  (define t (transcript->claims-table name))
  (hash-ref t (transcript ds)
            (λ () (for/list ([d '(funds fit flow temporal)]) (list 'claim d 'Indeterminate '())))))
(define external-arms
  (for/list ([name EXTERNAL-ARMS])
    (arm 'purchase name (hasheq 'mechanism 'external 'arm name) I (external-judge name))))
