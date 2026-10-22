#lang racket/base
;; Family 9 — purchase. Environment, interactive execution, truth, deliveries.
;; specs/purchase.md. The arm's protocol names its mechanism: a reference
;; mechanism (mechanisms.rkt) or an external arm (external.rkt), whose calls
;; are replayed here against the providers, so the providers stay the only
;; source of replies and of truth.

(require racket/list "../../core/family.rkt" "terms.rkt" "providers.rkt" "mechanisms.rkt" "external.rkt")
(provide purchase run-transcript START)

(define SLOTS '(stock alt auth void read capture deliver report scan))
(define BASE (hash 'stock '((kept . 1)) 'alt '((within . 1)) 'auth '((replied . 1)) 'void '((replied . 1))
                   'read '((fresh . 1)) 'capture '((replied . 1)) 'deliver '((on-time . 1)) 'report '((honest . 1)) 'scan '((recorded . 1))))
(define (all . vs) (for/list ([v vs]) (cons v 1)))
(define PROFILES
  (list (cons 'reliable (hash))
        (cons 'stockout (hash 'stock '((kept . 1) (lost . 3)) 'alt (all 'within 'over 'none)))
        (cons 'unknown-outcome (hash 'auth (all 'replied 'lost) 'capture (all 'replied 'lost) 'read (all 'fresh 'stale 'unavailable)))
        (cons 'stale-release (hash 'stock '((lost . 1)) 'void (all 'replied 'lost 'timeout) 'read (all 'fresh 'stale 'unavailable)))
        (cons 'carrier (hash 'deliver (all 'on-time 'late 'never) 'report (all 'honest 'premature) 'scan (all 'recorded 'dropped)))
        (cons 'adversarial (hash 'stock (all 'kept 'lost) 'alt (all 'within 'over 'none) 'auth (all 'replied 'lost)
                                 'void (all 'replied 'lost 'timeout) 'read (all 'fresh 'stale 'unavailable)
                                 'capture (all 'replied 'lost) 'deliver (all 'on-time 'late 'never)
                                 'report (all 'honest 'premature) 'scan (all 'recorded 'dropped)))))

;; what every mechanism is told at the start (the external arms receive the same)
(define START (hasheq 'cap CAP 'seller 'A 'price PRICE-A))

(struct stopped ())

;; → (values transcript truth); transcript: list of (call reply)
(define cache (make-hash))
(define (run-transcript protocol iface w)
  (define r
   (hash-ref! cache (list protocol iface w)
             (λ ()
               (define p (new-providers w iface))
               (define calls 0)
               (define (call c)
                 (set! calls (add1 calls))
                 (when (> calls CALL-LIMIT) (raise (stopped)))
                 (provider-call! p c))
               (define mech (hash-ref protocol 'mechanism))
               (with-handlers ([stopped? void])
                 (case mech
                   [(external) (replay-external (hash-ref protocol 'arm) w call)]
                   [else ((hash-ref MECHANISMS mech) call START)]))
               (cons (provider-calls p) (provider-truth p)))))
  (values (car r) (cdr r)))

(define (execute protocol iface w)
  (define-values (tr truth) (run-transcript protocol iface w))
  (hasheq 'truth truth 'gap 0 'required 0))

(define (deliveries protocol iface w)
  (define-values (tr truth) (run-transcript protocol iface w))
  (for/list ([cr tr] [i (in-naturals 1)])
    (list 'msg 'REPLY i i (car cr) (cadr cr))))

(define purchase
  (family 'purchase
          (list (dependency 'funds 'Sharing) (dependency 'fit 'Fit) (dependency 'flow 'Flow) (dependency 'temporal 'Temporal))
          SLOTS BASE PROFILES values execute deliveries world? ds?))
