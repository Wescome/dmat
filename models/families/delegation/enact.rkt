#lang racket/base
;; Family 4 — conditional delegation. Enactment adapter (specs/enactment.md):
;; party agents V (provider), S (subcontractor), A (attester); observer H.
;; Protocol: the hybrid's retention (V stays responsible when it delegates).
;; V's record (state, ledger, S's stage) is V's system of record and holds
;; conduct.

(require racket/list "../../core/enact.rkt" "../../core/family.rkt" "terms.rkt" "world.rkt"
         (submod "world.rkt" internals))
(provide delegation-enactment)

(define PROTOCOL (hasheq 'on-delegate 'retain))
(define IFACE (hasheq 'notice? #t 'attest? #t 'view 'full))

(define V (role-spec 'V "the provider V"
                     (list (msg-spec 'Accept 'act '() "accept H's referral (the instant you accepted)")
                           (msg-spec 'Delegated 'act '() "notify H that you delegated the patient's care to subcontractor S (the instant you delegated)")
                           (msg-spec 'Start 'report '() "notify H that you initiated care (the instant care was initiated)"))))
(define S (role-spec 'S "the subcontractor S"
                     (list (msg-spec 'Start 'report '() "notify H that you initiated care on V's behalf (the instant care was initiated)"))))
(define A (role-spec 'A "the attester A, an independent party that witnesses care initiation"
                     (list (msg-spec 'Attest 'report '() "attest to H that care was initiated (the instant it was initiated)"))))

(define (brief w role)
  (define r (run PROTOCOL w))
  (define cap (hash-ref r 'cap)) (define s-acc (hash-ref r 's-acc))
  (define perf (hash-ref r 'performer)) (define st (hash-ref r 'start-at))
  (case role
    [(V) (append
          (list (format "You accepted H's referral at instant ~a." T-ACCEPT))
          (if cap (list "You had capacity to provide care yourself.")
              (list (format "You lacked capacity and delegated the patient's care to subcontractor S at instant ~a, retaining responsibility until care is initiated." T-DELEGATE)
                    (format "S ~a the delegation at instant ~a." (if s-acc "accepted" "declined") T-S-RESPONSE)))
          (cond [(and (eq? perf 'V) st) (list (format "You initiated care at instant ~a." st))]
                [(and (eq? perf 'V-resumed) st) (list (format "Since S declined, you resumed and initiated care at instant ~a." st))]
                [(eq? perf 'S) (list (if st (format "S initiated care at instant ~a; S notifies H itself." st) "S did not initiate care."))]
                [else (list "You did not initiate care.")]))]
    [(S) (cond [cap (list "V did not delegate anything to you; you have no part in this referral.")]
               [else (append (list (format "V delegated a patient's care to you at instant ~a." T-DELEGATE)
                                   (format "You ~a the delegation at instant ~a." (if s-acc "accepted" "declined") T-S-RESPONSE))
                             (cond [(and (eq? perf 'S) st) (list (format "You initiated care at instant ~a." st))]
                                   [s-acc (list "You did not initiate care.")]
                                   [else '()]))])]
    [(A) (if st (list (format "You witnessed care being initiated for the patient at instant ~a." st))
             (list "You did not witness any initiation of care."))]))

(define (faithful w role)
  (define r (run PROTOCOL w))
  (define perf (hash-ref r 'performer)) (define st (hash-ref r 'start-at))
  (case role
    [(V) (append (list (make-ev V 'Accept T-ACCEPT))
                 (if (hash-ref r 'cap) '() (list (make-ev V 'Delegated T-DELEGATE)))
                 (if (and st (memq perf '(V V-resumed))) (list (make-ev V 'Start st)) '()))]
    [(S) (if (and st (eq? perf 'S)) (list (make-ev S 'Start st)) '())]
    [(A) (if st (list (make-ev A 'Attest st)) '())]))

(define (assemble w events)
  (define r (run PROTOCOL w))
  (define v-evs (evs-of events 'V))
  (define acc (for/list ([e (msg-of v-evs 'Accept)]) (list 'msg 'ACCEPT (+ 1 (ev-at e)) (ev-at e))))
  (define del (for/list ([e (msg-of v-evs 'Delegated)]
                         #:when (or (hash-ref r 'cap) (eq? (ref w 'delegated-msg) 'delivered)))
                (list 'msg 'DELEGATED (+ 1 (ev-at e)) (ev-at e))))
  (define starts (sort (append (msg-of v-evs 'Start) (msg-of (evs-of events 'S) 'Start)) < #:key ev-at))
  ;; a message the world never planned travels on a reliable channel
  (define planned-start (hash-ref r 'start-at))
  (define notice (for/list ([e starts] #:when (or (not planned-start) (eq? (ref w 'notice) 'delivered)))
                   (list 'msg 'START (+ (ev-at e) NOTICE-DELAY) (ev-at e))))
  (define attest (for/list ([e (msg-of (evs-of events 'A) 'Attest)] #:when (or (not planned-start) (eq? (ref w 'attest) 'delivered)))
                   (list 'msg 'ATTEST (+ (ev-at e) ATTEST-DELAY) (ev-at e))))
  (define rd
    (case (ref w 'read)
      [(unavailable) (list 'read-failed T-READ)]
      [else (define as-of (if (eq? (ref w 'read) 'stale) STALE-AS-OF T-READ))
            (define-values (vs c1 c2 stage) (record-at r as-of))
            (list 'read-ok T-READ (list 'full vs c1 c2 stage as-of))]))
  (values (by-arrival (append acc del notice attest (list rd))) '()))

(define (truth w ds) (hash-ref ((family-execute delegation) PROTOCOL IFACE w) 'truth))

(define (render ds)
  (for/list ([d ds] [i (in-naturals)])
    (case (car d)
      [(msg) (format "[~a] arrived at ~a: ~a~a, for instant ~a" i (caddr d) (cadr d)
                     (case (cadr d) [(ATTEST) " from the attester A"] [(START) " (care-initiation notice from the performer)"] [else " from V"])
                     (cadddr d))]
      [(read-failed) (format "[~a] at ~a: the read-back of V's record failed" i (cadr d))]
      [(read-ok) (define v (caddr d))
                 (format "[~a] at ~a: read-back of V's record as of instant ~a — V's state ~a; V's commitment C1 to H ~a; S's commitment C2 to V ~a; S's stage ~a"
                         i (cadr d) (list-ref v 5) (list-ref v 1) (list-ref v 2) (list-ref v 3) (list-ref v 4))])))

(define texts
  (hasheq
   'scenario (format (string-append
                      "You are a hospital H. You referred a patient to provider V; V accepts at ~a. When V lacks capacity it delegates the care to a subcontractor S at ~a, retaining responsibility until care is initiated; S accepts or declines at ~a, and if S declines V resumes. "
                      "Whoever performs initiates care (at ~a, or at ~a if V resumed) and sends you a START notice; an independent attester A attests care initiation. At ~a you read back V's record "
                      "(V's state: accepted, delegating, delegated, resumed, started, sub-started; V's commitment C1 to you: active, pending, discharged, released; S's commitment C2 to V; S's stage).")
                     T-ACCEPT T-DELEGATE T-S-RESPONSE T-START T-RESUME-START T-READ)
   'deps (list (cons 'continuity "at no instant between V's acceptance and care initiation is the obligation owned by nobody")
               (cons 'temporal (format "care was initiated by instant ~a" DEADLINE)))
   'commitments (format "C1 = C(V, H, V accepted by ~a, care initiated by ~a), retained by V when it delegates. temporal holds iff C1 is discharged; if V never accepted, Violated. continuity is violated only if C1 was released (responsibility handed to nobody); retention keeps C1 V's from acceptance to discharge."
                        T-ACCEPT DEADLINE)
   'evidence "ACCEPT and DELEGATED are V's acts. A START notice (from V or from S, V's delegate) and V's ledger showing C1 discharged are reports by V's side of its own performance: they are not evidence that care was initiated, though a report of initiation after the deadline is an admission of lateness. ATTEST is a third party's report and is evidence. V's record is complete only through its as-of instant: it shows that care was not initiated by the deadline only if complete through the deadline and not itself reporting initiation."
   'render render))

(define delegation-enactment
  (enactment 'delegation (list V S A) 'H T-EVAL brief faithful assemble truth texts))
