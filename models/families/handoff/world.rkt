#lang racket/base
;; Family 1 — information handoff. Environment, oracle truth, deliveries.
;; V's conduct is exogenous here: the arms differ in what their protocols make
;; observable and in how they judge, not in how V acts.

(require racket/list "../../core/family.rkt" "terms.rkt")
(provide handoff)

(define SLOTS '(accept start crash report reply reply-delay notice attest read record))
(define (ref w s) (list-ref w (+ 1 (index-of SLOTS s))))

(define (accepted? w) (memq (ref w 'accept) '(on-time late)))
(define (accept-at w) (case (ref w 'accept) [(on-time) T-ON-TIME] [(late) T-LATE] [else #f]))
(define (started? w) (and (accepted? w) (ref w 'start) (not (ref w 'crash))))
(define (reported-start? w)
  (or (started? w) (and (accepted? w) (not (ref w 'crash)) (eq? (ref w 'report) 'premature))))

(define (canonical w)
  (define acc (accepted? w))
  (define crash (and acc (ref w 'crash)))
  (define start (and acc (not crash) (ref w 'start)))
  (define report (if (and acc (not crash) (not start)) (ref w 'report) 'honest))
  (define reply (if acc (ref w 'reply) 'dropped))
  (define rdelay (if (and acc (not (eq? reply 'dropped))) (ref w 'reply-delay) 'fast))
  (define attest (if start (ref w 'attest) 'dropped))
  (list 'world (ref w 'accept) start crash report reply rdelay (ref w 'notice) attest (ref w 'read) (ref w 'record)))

(define BASE
  (hash 'accept '((on-time . 4) (late . 0) (no . 1))
        'start '((#t . 3) (#f . 1))
        'crash '((#f . 1))
        'report '((honest . 1))
        'reply '((delivered . 1))
        'reply-delay '((fast . 1))
        'notice '((delivered . 1))
        'attest '((delivered . 1))
        'read '((fresh . 1))
        'record '((complete . 1))))

(define PROFILES
  (list
   (cons 'reliable (hash))
   (cons 'lossy (hash 'reply '((delivered . 1) (dropped . 1) (duplicated . 1))
                      'notice '((delivered . 1) (dropped . 1))))
   (cons 'timing (hash 'accept '((on-time . 3) (late . 1) (no . 1))
                       'reply-delay '((fast . 1) (slow . 1))
                       'read '((fresh . 2) (unavailable . 1))))
   (cons 'stale-read (hash 'reply '((delivered . 1) (dropped . 1))
                           'notice '((delivered . 1) (dropped . 1))
                           'read '((fresh . 1) (stale . 1) (unavailable . 1))))
   (cons 'record-lag (hash 'notice '((delivered . 1) (dropped . 1))
                           'record '((complete . 1) (lag . 1))))
   (cons 'evidence-contradiction (hash 'report '((honest . 1) (premature . 1))
                                       'attest '((delivered . 3) (dropped . 1))))
   (cons 'adversarial (hash 'accept '((on-time . 3) (late . 1) (no . 1))
                            'crash '((#f . 2) (#t . 1))
                            'report '((honest . 1) (premature . 1))
                            'reply '((delivered . 1) (dropped . 1) (duplicated . 1))
                            'reply-delay '((fast . 1) (slow . 1))
                            'notice '((delivered . 1) (dropped . 1))
                            'attest '((delivered . 3) (dropped . 1))
                            'read '((fresh . 1) (stale . 1) (unavailable . 1))
                            'record '((complete . 1) (lag . 1))))))

;; V's record, as a read sees it
(define (record-view w kind)
  (define as-of (if (eq? (ref w 'read) 'stale) STALE-AS-OF T-READ))
  (define lag? (eq? (ref w 'record) 'lag))
  (define oat (and (accepted? w) (<= (accept-at w) as-of) (accept-at w)))
  (define start-recorded (if lag? (+ T-EVAL 1) T-START))
  (define ost (and (reported-start? w) (<= start-recorded as-of) T-START))
  (define wm (if lag? (min as-of LAG-WATERMARK) as-of))
  (define S (cond [ost 'started] [oat 'accepted] [else 'referred]))
  (define c0 (cond [(not oat) 'none] [(<= oat ACCEPT-DEADLINE) 'discharged] [else 'late-discharged]))
  (define c1 (cond [ost 'discharged] [oat 'detached] [else 'none]))
  (case kind
    [(last-message) (list 'last-message (cond [ost (list 'START ost)] [oat (list 'ACCEPT oat)] [else 'none]))]
    [(state) (list 'state S)]
    [(ledger) (list 'ledger c0 c1)]
    [(full) (list 'full S oat ost c0 c1 wm)]))

(define (deliveries protocol iface w)
  (define at (accept-at w))
  (define arrive (and at (+ at (if (eq? (ref w 'reply-delay) 'slow) SLOW FAST))))
  (define acc (if at
                  (case (ref w 'reply)
                    [(delivered) (list (list 'msg 'ACCEPT arrive at))]
                    [(duplicated) (list (list 'msg 'ACCEPT arrive at) (list 'msg 'ACCEPT arrive at))]
                    [else '()])
                  '()))
  (define notice (if (and (hash-ref iface 'notice? #f) (reported-start? w) (eq? (ref w 'notice) 'delivered))
                     (list (list 'msg 'START T-NOTICE T-START)) '()))
  (define attest (if (and (hash-ref iface 'attest? #f) (started? w) (eq? (ref w 'attest) 'delivered))
                     (list (list 'msg 'ATTEST T-ATTEST T-START)) '()))
  (define rd (if (eq? (ref w 'read) 'unavailable)
                 (list (list 'read-failed T-READ))
                 (list (list 'read-ok T-READ (record-view w (hash-ref iface 'view))))))
  ;; time order of arrival; ties keep declaration order
  (sort (append acc notice attest rd) < #:key (λ (d) (if (eq? (car d) 'msg) (caddr d) (cadr d)))))

;; Responsibility gap: from V's acceptance until H holds evidence of it.
(define (execute protocol iface w)
  (define truth (hasheq 'flow (if (eq? (ref w 'accept) 'on-time) 'Fulfilled 'Violated)
                        'temporal (if (started? w) 'Fulfilled 'Violated)))
  (define at (accept-at w))
  (define-values (gap required)
    (if at
        (let* ([ds (deliveries protocol iface w)]
               [learn (for/first ([d ds]
                                  #:when (or (and (eq? (car d) 'msg) (memq (cadr d) '(ACCEPT ATTEST)))
                                             (and (eq? (car d) 'read-ok)
                                                  (let ([v (caddr d)])
                                                    (case (car v)
                                                      [(last-message) (pair? (cadr v))]
                                                      [(state) (memq (cadr v) '(accepted started))]
                                                      [(ledger) (not (eq? (cadr v) 'none))]
                                                      [(full) (memq (cadr v) '(accepted started))])))))
                        (if (eq? (car d) 'msg) (caddr d) (cadr d)))])
          (values (- (or learn T-EVAL) at) (- T-EVAL at)))
        (values 0 0)))
  (hasheq 'truth truth 'gap gap 'required required))

(define handoff
  (family 'handoff
          (list (dependency 'flow 'Flow) (dependency 'temporal 'Temporal))
          SLOTS BASE PROFILES canonical execute deliveries world? ds?))
