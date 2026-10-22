#lang racket/base
;; Family 9 — the providers: payment processor X, sellers A and B, carrier.
;; specs/purchase.md §3–§5. Oracle side: holds the providers' state.
;;
;; (new-providers w iface) gives a provider state for world w; (provider-call! p call)
;; answers one call and applies its effect; (provider-truth p) is the truth of the
;; four dependencies at the end of the run.

(require racket/list "terms.rkt")
(provide new-providers provider-call! provider-truth provider-calls)

(define SLOTS '(stock alt auth void read capture deliver report scan))
(define (slot w s) (list-ref w (add1 (index-of SLOTS s))))

; hld: a hold's state, amount, authorize keys used, ever captured?
(struct hld (state amount keys captured?) #:mutable #:transparent)

(struct providers (w watermark? [n #:mutable] holds orders
                   [ship-state #:mutable] [ship-from #:mutable] [delivered-at #:mutable]
                   [effects #:mutable] [firsts #:mutable] [calls #:mutable])
  #:transparent)

(define (new-providers w iface)
  (providers w (hash-ref iface 'watermark #f) 0 (make-hasheq) (make-hasheq)
             'NONE #f #f '() '() '()))

(define (provider-calls p) (reverse (providers-calls p)))

(define (price-of p s)
  (case s
    [(A) PRICE-A]
    [(B) (case (slot (providers-w p) 'alt) [(within) PRICE-B-WITHIN] [(over) PRICE-B-OVER] [else #f])]))

(define (b-exists? p) (not (eq? (slot (providers-w p) 'alt) 'none)))
(define (seller-ok? p s) (or (eq? s 'A) (and (eq? s 'B) (b-exists? p))))

;; the first call of an operation (faults on auth, void, capture apply to it only)
(define (first-call! p op)
  (cond [(memq op (providers-firsts p)) #f]
        [else (set-providers-firsts! p (cons op (providers-firsts p))) #t]))

(define (hold-state p s) (let ([h (hash-ref (providers-holds p) s #f)]) (if h (hld-state h) 'NONE)))

;; a payment effect: the hold of seller s takes state st, stamped with call n
(define (pay-effect! p s st)
  (set-providers-effects! p (cons (list (providers-n p) s st) (providers-effects p))))

(define UNKNOWN '(failed STATE-UNCERTAIN no-reply))

;; the payment record as of completeness point c
(define (record-as-of p c)
  (define st (make-hasheq)) (define am (make-hasheq))
  (for ([e (reverse (providers-effects p))] #:when (<= (car e) c))
    (hash-set! st (cadr e) (caddr e)))
  (for ([(s h) (providers-holds p)]) (hash-set! am s (hld-amount h)))
  (list 'record (and (providers-watermark? p) c)
        (for/list ([s SELLERS] #:when (hash-ref st s #f))
          (list s (hash-ref st s) (hash-ref am s)))))

(define (payment-record p)
  (define n (providers-n p))
  (case (slot (providers-w p) 'read)
    [(unavailable) #f]
    [(fresh) (record-as-of p (sub1 n))]
    [(stale) (define effs (providers-effects p))
             (record-as-of p (if (null? effs) (sub1 n) (sub1 (car (car effs)))))]))

(define (delivered-at-scan p)
  (if (eq? (providers-ship-state p) 'DELIVERED) (list 'at (providers-delivered-at p)) '(at none)))

;; answer call c (a call term) and apply its effect; → reply term
(define (provider-call! p c)
  (set-providers-n! p (add1 (providers-n p)))
  (define reply (answer! p c))
  (set-providers-calls! p (cons (list c reply) (providers-calls p)))
  reply)

(define (answer! p c)
  (define w (providers-w p))
  (define (bad) '(failed BUSINESS-REJECTION bad-call))
  (case (car c)
    [(reserve)
     (define s (cadr c))
     (if (seller-ok? p s) '(ok reserved) '(failed RESOURCE-UNAVAILABLE no-offer))]
    [(alternatives)
     (if (b-exists? p) (list 'ok (list 'offers (list 'B (price-of p 'B)))) '(ok (offers)))]
    [(authorize)
     (define-values (s amount key) (values (cadr c) (caddr c) (cadddr c)))
     (define first? (first-call! p 'authorize))
     (define h (hash-ref (providers-holds p) s #f))
     (cond
       [(not (seller-ok? p s)) '(failed RESOURCE-UNAVAILABLE no-offer)]
       [(and h (member key (hld-keys h))) '(ok AUTHORIZED)]   ; idempotent replay of the original reply
       [(or (not h) (eq? (hld-state h) 'VOIDED))
        (hash-set! (providers-holds p) s (hld 'AUTHORIZED amount (cons key (if h (hld-keys h) '())) (and h (hld-captured? h))))
        (pay-effect! p s 'AUTHORIZED)
        (if (and first? (eq? (slot w 'auth) 'lost)) UNKNOWN '(ok AUTHORIZED))]
       [else '(failed BUSINESS-REJECTION hold-exists)])]
    [(confirm)
     (define s (cadr c))
     (cond [(not (seller-ok? p s)) (bad)]
           [(and (eq? s 'A) (eq? (slot w 'stock) 'lost)) '(ok lost)]
           [else '(ok available)])]
    [(accept)
     (define s (cadr c))
     (cond [(not (seller-ok? p s)) (bad)]
           [(and (eq? s 'A) (eq? (slot w 'stock) 'lost)) '(failed BUSINESS-REJECTION out-of-stock)]
           [else (hash-set! (providers-orders p) s 'ACCEPTED) '(ok ACCEPTED)])]
    [(void)
     (define s (cadr c))
     (define first? (first-call! p 'void))
     (define mode (if first? (slot w 'void) 'replied))
     (define h (hash-ref (providers-holds p) s #f))
     (cond
       [(eq? mode 'timeout) UNKNOWN]
       [else
        (when (and h (eq? (hld-state h) 'AUTHORIZED))
          (set-hld-state! h 'VOIDED) (pay-effect! p s 'VOIDED))
        (if (eq? mode 'lost) UNKNOWN (list 'ok (hold-state p s)))])]
    [(capture)
     (define s (cadr c))
     (define first? (first-call! p 'capture))
     (define h (hash-ref (providers-holds p) s #f))
     (cond
       [(and h (eq? (hld-state h) 'AUTHORIZED))
        (set-hld-state! h 'CAPTURED) (set-hld-captured?! h #t) (pay-effect! p s 'CAPTURED)
        (if (and first? (eq? (slot w 'capture) 'lost)) UNKNOWN '(ok CAPTURED))]
       [(and h (eq? (hld-state h) 'CAPTURED)) '(ok CAPTURED)]
       [else '(failed BUSINESS-REJECTION not-authorized)])]
    [(refund)
     (define s (cadr c))
     (define h (hash-ref (providers-holds p) s #f))
     (when (and h (eq? (hld-state h) 'CAPTURED))
       (set-hld-state! h 'REFUNDED) (pay-effect! p s 'REFUNDED))
     (list 'ok (hold-state p s))]
    [(cancel)
     (define s (cadr c))
     (cond [(and (eq? (hash-ref (providers-orders p) s 'NONE) 'ACCEPTED) (eq? (providers-ship-state p) 'NONE))
            (hash-set! (providers-orders p) s 'CANCELLED) '(ok CANCELLED)]
           [else '(failed BUSINESS-REJECTION not-cancellable)])]
    [(ship)
     (define s (cadr c))
     ;; M6 (2026-10-22): an authorised hold suffices, so when to capture is the mechanism's choice
     (cond [(and (eq? (hash-ref (providers-orders p) s 'NONE) 'ACCEPTED) (memq (hold-state p s) '(AUTHORIZED CAPTURED))
                 (eq? (providers-ship-state p) 'NONE))
            (set-providers-ship-state! p 'IN-TRANSIT) (set-providers-ship-from! p s) '(ok IN-TRANSIT)]
           [else '(failed BUSINESS-REJECTION not-shippable)])]
    [(deliver)
     ;; the carrier's conduct, the same on every call (specs/purchase.md §4)
     (define s (cadr c))
     (cond
       [(not (and (eq? (providers-ship-from p) s) (memq (providers-ship-state p) '(IN-TRANSIT DELIVERED))))
        '(failed BUSINESS-REJECTION nothing-in-transit)]
       [else
        (when (eq? (providers-ship-state p) 'IN-TRANSIT)
          (case (slot w 'deliver)
            [(on-time) (set-providers-ship-state! p 'DELIVERED) (set-providers-delivered-at! p T-ON-TIME)]
            [(late) (set-providers-ship-state! p 'DELIVERED) (set-providers-delivered-at! p T-LATE)]
            [else (void)]))
        (cond
          ;; a premature report: the seller reports an on-time delivery that has not happened on time
          [(and (eq? (slot w 'report) 'premature)
                (not (and (eq? (providers-ship-state p) 'DELIVERED) (<= (providers-delivered-at p) DEADLINE))))
           (list 'ok (list 'at T-ON-TIME))]
          [(eq? (providers-ship-state p) 'DELIVERED) (list 'ok (list 'at (providers-delivered-at p)))]
          [else '(failed DEADLINE-BREACH not-delivered)])])]
    [(payment-record)
     (define r (payment-record p))
     (if r (list 'ok r) '(failed DEPENDENCY-FAILURE record-unavailable))]
    [(order-state)
     (define s (cadr c))
     (if (seller-ok? p s) (list 'ok (hash-ref (providers-orders p) s 'NONE)) (bad))]
    [(shipment-state) (list 'ok (providers-ship-state p))]
    [(carrier-scan)
     (if (eq? (slot w 'scan) 'dropped) '(failed DEPENDENCY-FAILURE scan-unavailable) (list 'ok (delivered-at-scan p)))]
    [(reconcile)
     (define r (payment-record p))
     (cond [(not r) '(failed DEPENDENCY-FAILURE record-unavailable)]
           [else
            (list 'ok (list 'report r
                            (cons 'orders (for/list ([s SELLERS]) (list s (hash-ref (providers-orders p) s 'NONE))))
                            (providers-ship-state p)
                            (count (λ (h) (eq? (cadr h) 'CAPTURED)) (caddr r))))])]
    [else (bad)]))

;; truth at the end of the run (specs/purchase.md §2)
(define (provider-truth p)
  (define hs (hash-values (providers-holds p)))
  (define (st h) (hld-state h))
  (define delivered? (eq? (providers-ship-state p) 'DELIVERED))
  (hasheq 'funds (if (and (not (ormap (λ (h) (eq? (st h) 'AUTHORIZED)) hs))
                          (<= (count (λ (h) (eq? (st h) 'CAPTURED)) hs) 1))
                     'Fulfilled 'Violated)
          'fit (if (andmap (λ (h) (or (not (hld-captured? h)) (<= (hld-amount h) CAP))) hs) 'Fulfilled 'Violated)
          'flow (if (for/and ([(s h) (providers-holds p)])
                      (or (not (eq? (st h) 'CAPTURED)) (and delivered? (eq? (providers-ship-from p) s))))
                    'Fulfilled 'Violated)
          'temporal (if (and delivered? (<= (providers-delivered-at p) DEADLINE)) 'Fulfilled 'Violated)))
