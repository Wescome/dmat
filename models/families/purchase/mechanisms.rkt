#lang racket/base
;; Family 9 — the reference mechanisms (conduct). specs/purchase.md §9.
;;
;; A mechanism is (λ (call start) ...): `call` sends one call term and returns
;; its reply term; `start` is the hasheq the external arms receive (cap,
;; primary seller and price). A mechanism sees nothing else: no world, no truth.
;; It returns when it has finished acting; its claims are given by its judge
;; (arms.rkt), which reads its transcript.
;;
;; hybrid — acts only on established state:
;;   - authorise; on an unknown outcome read the payment record (evidence), then
;;     resend with the same key, whose reply the processor answers from its
;;     idempotency record;
;;   - when the primary seller cannot supply: release its hold before anything
;;     else. A void's outcome is established by the processor's reply to the void,
;;     or by a payment record whose completeness point covers the void; a record
;;     that does not cover it establishes nothing, and the void is resent with the
;;     same key. Reroute only once the release is established;
;;   - reroute only to an offer within the principal's limit;
;;   - capture with the same key until the outcome is established;
;;   - ship and deliver; refund when the carrier's record shows the goods undelivered
;;     (the seller's delivery report is the seller's own account and decides nothing);
;;   - end with a payment record and the carrier's scan, as evidence for the judge.
;; hybrid-noe — the same conduct, but any payment record is taken as current and the
;;   seller's delivery report as fact.

(require racket/list "terms.rkt")
(provide MECHANISMS)

(define ATTEMPTS 3)

(define ((mechanism evidential?) call start)
  (define cap (hash-ref start 'cap))
  (define n 0)
  (define (send c) (set! n (add1 n)) (call c))
  (define (ok? r) (eq? (car r) 'ok))
  (define (unknown? r) (and (eq? (car r) 'failed) (eq? (cadr r) 'STATE-UNCERTAIN)))

  ;; the state of seller s's hold in a record read as call `at`, if the record
  ;; establishes it for an effect caused by call `after`; else #f
  (define (record-state s after)
    (define r (send '(payment-record)))
    (and (ok? r)
         (let* ([rec (cadr r)] [c (cadr rec)])
           (and (or (not evidential?) (and c (>= c after)))
                (cond [(assq s (caddr rec)) => cadr] [else 'NONE])))))

  ;; authorise seller s at price; → #t when the hold is established
  (define (authorize s price)
    (define key (format "auth-~a" s))
    (let loop ([k 0] [r (send (list 'authorize s price key))])
      (cond [(ok? r) #t]
            [(and (unknown? r) (< k ATTEMPTS))
             (define seq n)
             (record-state s seq)                       ; read before resend (evidence only)
             (loop (add1 k) (send (list 'authorize s price key)))]
            [else #f])))

  ;; release seller s's hold; → #t when the release is established
  (define (release s)
    (define key (format "void-~a" s))
    (let loop ([k 0] [r (send (list 'void s key))])
      (cond [(and (ok? r) (memq (cadr r) '(VOIDED NONE))) #t]
            [(ok? r) #f]                                  ; the hold is captured or refunded: not releasable
            [(< k ATTEMPTS)
             (define seq n)
             (define st (record-state s seq))
             (if (memq st '(VOIDED NONE)) #t (loop (add1 k) (send (list 'void s key))))]
            [else #f])))

  (define (capture s)
    (define key (format "capture-~a" s))
    (let loop ([k 0] [r (send (list 'capture s key))])
      (cond [(ok? r) #t]
            [(and (unknown? r) (< k ATTEMPTS))
             (record-state s n)
             (loop (add1 k) (send (list 'capture s key)))]
            [else #f])))

  (define (buy s price)
    (cond
      [(not (ok? (send (list 'reserve s)))) 'no-offer]
      [(> price cap) 'over-limit]
      [(not (authorize s price)) 'not-authorized]
      [(equal? (send (list 'confirm s)) '(ok lost)) (if (release s) 'lost-released 'lost-held)]
      [(not (ok? (send (list 'accept s (format "accept-~a" s)))))
       (if (release s) 'refused-released 'refused-held)]
      [(not (capture s)) 'not-captured]
      [(not (ok? (send (list 'ship s (format "ship-~a" s))))) 'not-shipped]
      [else
       (define d (send (list 'deliver s (format "deliver-~a" s))))
       ;; hybrid decides on the carrier's record (the seller's report is the seller's own
       ;; account of its performance); hybrid-noe on the seller's report
       (define undelivered?
         (if evidential?
             (equal? (send '(carrier-scan)) '(ok (at none)))
             (not (ok? d))))
       (when undelivered? (send (list 'refund s (format "refund-~a" s))))
       'done]))

  (define first-outcome (buy 'A (hash-ref start 'price)))
  (define outcome
    (cond
      [(memq first-outcome '(lost-released refused-released))
       (define alts (send '(alternatives)))
       (define offers (if (ok? alts) (cdr (cadr alts)) '()))
       (define within (filter (λ (o) (<= (cadr o) cap)) offers))
       (if (pair? within) (buy (car (car within)) (cadr (car within))) 'no-route)]
      [else first-outcome]))
  ;; evidence for the judge
  (send '(payment-record))
  (send '(carrier-scan))
  outcome)

(define MECHANISMS
  (hasheq 'hybrid (mechanism #t)
          'hybrid-noe (mechanism #f)))
