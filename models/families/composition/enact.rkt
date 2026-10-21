#lang racket/base
;; Family 7 — multi-organization composition. Enactment adapter
;; (specs/enactment.md): party agents S (subcontractor, reporting its stage to
;; V), V (provider, delivering to H) and A (attester of S's start); observer H.
;; Interface: the hybrid's staged observation model with attestation.
;;
;; V's case record relays S's reported stage: it holds what the S agent
;; reported (after the system fault of a premature start report by S's
;; system) and whether V delivered (conduct). It has no watermark.

(require racket/list "../../core/enact.rkt" "../../core/family.rkt" "terms.rkt" "world.rkt"
         (submod "world.rkt" internals))
(provide composition-enactment)

(define IFACE (hasheq 'obs 'staged 'attest? #t))

(define S (role-spec 'S "the subcontractor S, which performs the first stage for V"
                     (list (msg-spec 'Decline 'act '() "tell V you decline the subcontract (the instant you declined)")
                           (msg-spec 'Report 'report '() "report to V that you started your stage (the instant you started)"))))
(define V (role-spec 'V "the provider V, which assembles and delivers the result to H"
                     (list (msg-spec 'Delivered 'act '() "deliver the assembled result to H (the instant of delivery)"))))
(define A (role-spec 'A "the attester A, with a trusted clock"
                     (list (msg-spec 'Attest 'report '() "attest to H that S started its stage (the instant S started)"))))

(define (brief w role)
  (define st (s-start w))
  (case role
    [(S) (append
          (list (format "V subcontracted the first stage of H's order to you; you answered at instant ~a." T-COMMIT))
          (case (ref w 's-stage)
            [(declined) (list "You declined the subcontract.")]
            [(committed) (list "You committed to the stage but did not start it.")]
            [else (list (format "You committed to the stage and started it at instant ~a." st))]))]
    [(V) (list (if (delivers? w)
                   (format "You assembled the result and delivered it to H at instant ~a." T-DELIVER)
                   "You did not deliver the assembled result to H."))]
    [(A) (if st (list (format "You witnessed S starting its stage at instant ~a." st))
             (list "You did not witness S starting its stage."))]))

(define (faithful w role)
  (define st (s-start w))
  (case role
    [(S) (append (if (eq? (ref w 's-stage) 'declined) (list (make-ev S 'Decline T-COMMIT)) '())
                 (if st (list (make-ev S 'Report st)) '()))]
    [(V) (if (delivers? w) (list (make-ev V 'Delivered T-DELIVER)) '())]
    [(A) (if st (list (make-ev A 'Attest st)) '())]))

(define (assemble w events)
  (define st (s-start w))
  (define notes '())
  (define dl (for/list ([e (msg-of (evs-of events 'V) 'Delivered)]
                        #:when (or (not (delivers? w)) (eq? (ref w 'delivered-msg) 'delivered)))
               (list 'msg 'DELIVERED (+ 1 (ev-at e)) (ev-at e))))
  (define at (for/list ([e (msg-of (evs-of events 'A) 'Attest)] #:when (or (not st) (eq? (ref w 'attest) 'delivered)))
               (list 'msg 'ATTEST (+ (ev-at e) ATTEST-DELAY) (ev-at e))))
  (define s-evs (evs-of events 'S))
  (define reported
    (cond [(eq? (ref w 's-report) 'premature) (set! notes (list "premature: S's system reports an on-time start")) T-S-ON-TIME]
          [else (let ([ts (map ev-at (msg-of s-evs 'Report))]) (and (pair? ts) (apply min ts)))]))
  (define rd
    (case (ref w 'read)
      [(unavailable) (list 'read-failed T-READ)]
      [else
       (define cs (if (and (delivers? w) (<= T-DELIVER T-READ)) 'closed 'open))
       (define-values (ss ot)
         (cond [(and reported (<= reported T-READ)) (values 'started reported)]
               [(findf (λ (e) (<= (ev-at e) T-READ)) (msg-of s-evs 'Decline)) (values 'declined #f)]
               [else (values 'committed #f)]))
       (list 'read-ok T-READ (list 'staged cs ss ot))]))
  (values (by-arrival (append dl at (list rd))) notes))

(define (truth w ds) (hash-ref ((family-execute composition) (hasheq) IFACE w) 'truth))

(define (render ds)
  (for/list ([d ds] [i (in-naturals)])
    (case (car d)
      [(msg) (if (eq? (cadr d) 'DELIVERED)
                 (format "[~a] arrived at ~a: DELIVERED — V's delivery of the assembled result, made at ~a" i (caddr d) (cadddr d))
                 (format "[~a] arrived at ~a: ATTEST from the attester A, S started its stage at ~a by the trusted clock" i (caddr d) (cadddr d)))]
      [(read-failed) (format "[~a] at ~a: the read-back of V's case record failed" i (cadr d))]
      [(read-ok) (define v (caddr d))
                 (format "[~a] at ~a: read-back of V's case record (no completeness watermark) — case ~a; S's stage as S reported it to V: ~a~a"
                         i (cadr d) (list-ref v 1) (list-ref v 2) (if (list-ref v 3) (format ", start reported at ~a" (list-ref v 3)) ""))])))

(define texts
  (hasheq
   'scenario (format (string-append
                      "You are a client H. You ordered a service from provider V. V subcontracts the first stage to S, a third organization with which you have no protocol; S commits or declines at ~a and starts its stage (on time at ~a, or late). "
                      "V then assembles and delivers to you at ~a. S reports its stage to V, and V's case record relays it to you (staged view); an independent attester A, with a trusted clock, attests S's start. At ~a you read back V's case record.")
                     T-COMMIT T-S-ON-TIME T-DELIVER T-READ)
   'deps (list (cons 'temporal (format "S started its stage by instant ~a (true time)" DEADLINE))
               (cons 'delivery (format "V delivered the assembled result by instant ~a" T-EVAL)))
   'commitments (format "C_t = C(S, H, true, S starts by ~a), relayed to you by V's case record: temporal holds iff C_t is discharged; S's decline cancels it before discharge (Violated). C_d = C(V, H, true, delivery by ~a): delivery holds iff C_d is discharged." DEADLINE T-EVAL)
   'evidence "S's reported start, relayed by V's case record, is S's report of its own performance: it is not evidence of the start, though a reported start after the deadline is S's admission, and S's decline is S's act. ATTEST is a third party's report and is evidence. DELIVERED, which you receive, is the delivery itself. V's closed case is V's report of its own delivery. V's case record has no completeness watermark, so it shows only what it contains, never that something did not happen."
   'render render))

(define composition-enactment
  (enactment 'composition (list S V A) 'H T-EVAL brief faithful assemble truth texts))
