#lang racket/base
;; Pure helpers an arm uses over its own deliveries. No access to the world.

(require racket/list "grammar.rkt")
(provide msgs msg-indices read-index read-view msg-arrival msg-asserted msg-payload
         claims claim-of)

;; (index . delivery) pairs for messages of kind M satisfying pred
(define (msgs ds M [pred (λ (d) #t)])
  (for/list ([d ds] [i (in-naturals)]
             #:when (and (eq? (car d) 'msg) (eq? (cadr d) M) (pred d)))
    (cons i d)))

;; indices of messages of kind M whose asserted instant is ≤ by and that satisfy pred
(define (msg-indices ds M #:asserted-by [by +inf.0] #:arrived-by [arr +inf.0] #:where [pred (λ (d) #t)])
  (map car (msgs ds M (λ (d) (and (<= (msg-asserted d) by) (<= (msg-arrival d) arr) (pred d))))))

(define (msg-arrival d) (list-ref d 2))
(define (msg-asserted d) (list-ref d 3))
(define (msg-payload d) (list-tail d 4))

(define (read-index ds)
  (for/first ([d ds] [i (in-naturals)] #:when (eq? (car d) 'read-ok)) i))
(define (read-view ds)
  (define i (read-index ds))
  (and i (list-ref (list-ref ds i) 2)))

;; (claims (dep judgment cites) ...) → a claims term, citations sorted and unique
(define (claims . entries)
  (define cls
    (for/list ([e entries])
      (list 'claim (car e) (cadr e) (sort (remove-duplicates (caddr e)) <))))
  (unless (claims-term? cls) (error 'claims "not a claims term: ~s" cls))
  cls)

(define (claim-of cls dep) (findf (λ (c) (eq? (cadr c) dep)) cls))
