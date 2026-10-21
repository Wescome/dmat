#lang racket/base
;; Family 6 — partial external execution. Enactment adapter
;; (specs/enactment.md): party agents V (provider) and X (external executor,
;; signing receipts); observer H. System fault on V's stream: a premature DONE
;; by V's system. V's record (A's state, the relayed receipt, the watermark)
;; is V's system of record.

(require racket/list "../../core/enact.rkt" "../../core/family.rkt" "terms.rkt" "world.rkt"
         (submod "world.rkt" internals))
(provide external-enactment)

(define IFACE (hasheq 'receipt? #t 'view 'full))

(define V (role-spec 'V "the provider V"
                     (list (msg-spec 'Done 'report '() "report to H that the service is done: you performed part A and dispatched part B (the instant you report)"))))
(define X (role-spec 'X "the external executor X, which signs a receipt for part B's outcome"
                     (list (msg-spec 'Receipt 'report '((outcome complete partial)) "send H your signed receipt for part B (the instant you performed it, and its outcome)"))))

(define (brief w role)
  (define b (ref w 'b-outcome))
  (case role
    [(V) (list (if (ref w 'a-done) (format "You performed part A at instant ~a." T-A) "You did not perform part A.")
               (format "You dispatched part B to the external executor X at instant ~a. You cannot observe B's outcome." T-DISPATCH)
               (format "Under the protocol you report DONE to H at instant ~a once part A is done." T-DISPATCH))]
    [(X) (list (format "V dispatched part B of a service to you at instant ~a." T-DISPATCH)
               (case b
                 [(complete) (format "You performed part B completely at instant ~a." T-X)]
                 [(partial) (format "You performed part B only partially at instant ~a." T-X)]
                 [else "You did not perform part B."]))]))

(define (faithful w role)
  (define b (ref w 'b-outcome))
  (case role
    [(V) (if (ref w 'a-done) (list (make-ev V 'Done T-DISPATCH)) '())]
    [(X) (if (eq? b 'none) '() (list (make-ev X 'Receipt T-X 'outcome b)))]))

(define (assemble w events)
  (define notes '())
  (define dones
    (cond [(and (not (ref w 'a-done)) (eq? (ref w 'report) 'premature))
           (set! notes (list "premature: V's system reports DONE")) (list T-DISPATCH)]
          [else (map ev-at (msg-of (evs-of events 'V) 'Done))]))
  (define done (for/list ([t dones]) (list 'msg 'DONE (+ t (- T-DONE T-DISPATCH)) t)))
  (define planned-receipt (not (eq? (ref w 'b-outcome) 'none)))
  (define rc (for/list ([e (msg-of (evs-of events 'X) 'Receipt)]
                        #:when (or (not planned-receipt) (eq? (ref w 'receipt) 'delivered)))
               (list 'msg 'RECEIPT (+ (ev-at e) (- T-RECEIPT T-X)) (ev-at e) (ev-field e 'outcome))))
  (define rd
    (case (ref w 'read)
      [(unavailable) (list 'read-failed T-READ)]
      [else (define wm (if (eq? (ref w 'read) 'lag) LAG-WATERMARK T-READ))
            (define as (if (and (ref w 'a-done) (<= T-A wm)) 'done 'pending))
            (define xs (if (<= T-X wm) (ref w 'b-outcome) 'none))
            (list 'read-ok T-READ (list 'full as xs wm))]))
  (values (by-arrival (append done rc (list rd))) notes))

(define (truth w ds) (hash-ref ((family-execute external) (hasheq) IFACE w) 'truth))

(define (render ds)
  (for/list ([d ds] [i (in-naturals)])
    (case (car d)
      [(msg) (if (eq? (cadr d) 'DONE)
                 (format "[~a] arrived at ~a: DONE from V, sent at ~a" i (caddr d) (cadddr d))
                 (format "[~a] arrived at ~a: RECEIPT signed by X, part B performed at ~a, outcome ~a" i (caddr d) (cadddr d) (list-ref d 4)))]
      [(read-failed) (format "[~a] at ~a: the read-back of V's record failed" i (cadr d))]
      [(read-ok) (define v (caddr d))
                 (format "[~a] at ~a: read-back of V's record, complete through instant ~a — part A ~a; X's relayed outcome for part B: ~a"
                         i (cadr d) (list-ref v 3) (list-ref v 1) (list-ref v 2))])))

(define texts
  (hasheq
   'scenario (format (string-append
                      "You are a client H. You ordered a two-part service from provider V. V performs part A itself (at ~a) and dispatches part B at ~a to an external executor X, which is not a protocol participant and may complete B, complete it partially, or not perform it (at ~a). "
                      "V reports DONE to you; V cannot observe B's outcome. X sends you a signed receipt for B's outcome. At ~a you read back V's record, which relays X's receipt and may lag.")
                     T-A T-DISPATCH T-X T-READ)
   'deps (list (cons 'internal "part A was performed")
               (cons 'external "part B was performed in full"))
   'commitments (format "V owes the whole service. C_A = C(V, H, true, part A by ~a): internal holds iff C_A is discharged. C_B = C(V, H, true, part B in full by ~a): external holds iff C_B is discharged; a partial outcome of B is a known non-performance of B in full." T-DISPATCH T-X)
   'evidence "V's DONE and V's record entry 'A done' are V's reports of its own performance and are not evidence of it. X's receipt is signed, so it is X's report even when V's record relays it, and it is evidence of B's outcome. V's record is complete only through its stated instant: it shows that a part was not performed by its deadline only if complete through that deadline and not itself reporting it."
   'render render))

(define external-enactment
  (enactment 'external (list V X) 'H T-EVAL brief faithful assemble truth texts))
