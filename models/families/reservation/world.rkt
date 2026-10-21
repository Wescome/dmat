#lang racket/base
;; Family 2 — resource reservation. Environment, execution, deliveries.
;; The arm's protocol decides V's regrant rule ('regrant: on-release | expiry
;; | expiry-fenced), so truth depends on the arm.

(require racket/list "../../core/family.rkt" "terms.rkt")
(provide reservation)

(define SLOTS '(h1 release read))
(define (ref w s) (list-ref w (+ 1 (index-of SLOTS s))))
(define (canonical w)
  (define rel (if (eq? (ref w 'h1) 'dead) 'dropped (ref w 'release)))   ; a dead H1 sends nothing
  (list 'world (ref w 'h1) rel (ref w 'read)))

(define BASE (hash 'h1 '((releases . 3) (slow . 1) (dead . 1))
                   'release '((delivered . 1))
                   'read '((fresh . 1))))
(define PROFILES
  (list (cons 'reliable (hash))
        (cons 'lossy-release (hash 'release '((delivered . 1) (dropped . 1))))
        (cons 'stale-read (hash 'read '((fresh . 1) (stale . 1) (unavailable . 1))))
        (cons 'adversarial (hash 'release '((delivered . 1) (dropped . 1))
                                 'read '((fresh . 1) (stale . 1) (unavailable . 1))))))

;; The run: every event with its instant
(define (run protocol w)
  (define regrant (hash-ref protocol 'regrant))
  (define h1 (ref w 'h1))
  (define raw-end (case h1 [(releases) T-RELEASE] [(slow) T-SLOW-RELEASE] [(dead) T-DEAD]))
  (define rel-at (and (eq? (ref w 'release) 'delivered) (memq h1 '(releases slow)) raw-end))
  (define g2 (case regrant
               [(on-release) rel-at]
               [else (if rel-at (min rel-at LEASE-END) LEASE-END)]))
  (define expired? (and (memq regrant '(expiry expiry-fenced)) (not (and rel-at (<= rel-at LEASE-END)))))
  (define fenced? (eq? regrant 'expiry-fenced))
  (define eff-end (if (and fenced? g2) (min raw-end g2) raw-end))
  (define events
    (append (list (list 'GRANT 'h1 T-GRANT1))
            (if rel-at (list (list 'RELEASE rel-at)) '())
            (if expired? (list (list 'EXPIRE LEASE-END)) '())
            (if g2 (list (list 'GRANT 'h2 g2)) '())
            (list (list 'USE 'h1 T-GRANT1 eff-end))
            (if (and fenced? g2 (> raw-end g2)) (list (list 'REJECT 'h1 g2)) '())
            (if g2 (list (list 'USE 'h2 g2 (+ g2 H2-USE))) '())))
  (values events g2 (and g2 (> eff-end g2))))

(define (event-time e) (case (car e) [(GRANT) (caddr e)] [(USE) (cadddr e)] [(REJECT) (caddr e)] [else (cadr e)]))

(define (execute protocol iface w)
  (define-values (events g2 overcommit?) (run protocol w))
  (hasheq 'truth (hasheq 'sharing (if overcommit? 'Violated 'Fulfilled)
                         'temporal (if (and g2 (<= g2 D2)) 'Fulfilled 'Violated))
          'trace events 'gap 0 'required 0))

(define (deliveries protocol iface w)
  (define-values (events g2 overcommit?) (run protocol w))
  (case (ref w 'read)
    [(unavailable) (list (list 'read-failed T-READ))]
    [else
     (define as-of (if (eq? (ref w 'read) 'stale) STALE-AS-OF T-READ))
     (define kinds (hash-ref iface 'records))
     (define visible (filter (λ (e) (and (memq (car e) kinds) (<= (event-time e) as-of))) events))
     (list (list 'read-ok T-READ (list* 'log as-of (sort visible < #:key event-time))))]))

(define reservation
  (family 'reservation
          (list (dependency 'sharing 'Sharing) (dependency 'temporal 'Temporal))
          SLOTS BASE PROFILES canonical execute deliveries world? ds?))
