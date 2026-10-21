#lang racket/base
;; Family 5 — deadline-bound service. Enactment adapter (specs/enactment.md):
;; party agents V (provider) and A (attester with a trusted clock); observer H.
;;
;; V's clock skew is a system fault: V knows instants only by its own clock,
;; so V is briefed in its own clock and stamps DONE with it; the message
;; leaves at the true instant and arrives after the world's transit delay.
;; V's record (V's recorded completion stamp) is V's system of record.

(require racket/list "../../core/enact.rkt" "../../core/family.rkt" "terms.rkt" "world.rkt"
         (submod "world.rkt" internals))
(provide deadline-enactment)

(define IFACE (hasheq 'attest? #t))

(define V (role-spec 'V "the provider V"
                     (list (msg-spec 'Done 'report '() "report to H that you completed the service (the instant of completion, by your clock)"))))
(define A (role-spec 'A "the attester A, with a trusted clock"
                     (list (msg-spec 'Attest 'report '() "attest to H that V completed the service (the instant of completion, by your trusted clock)"))))

(define (skew w) (case (ref w 'skew) [(ahead) SKEW] [(behind) (- SKEW)] [else 0]))

(define (brief w role)
  (define t (true-done w))
  (case role
    [(V) (if t (list (format "You completed the service when your clock read instant ~a." (v-stamp w)))
             (list "You did not complete the service."))]
    [(A) (if t (list (format "You witnessed V completing the service at instant ~a." t))
             (list "You did not witness V completing the service."))]))

(define (faithful w role)
  (define t (true-done w))
  (case role
    [(V) (if t (list (make-ev V 'Done (v-stamp w))) '())]
    [(A) (if t (list (make-ev A 'Attest t)) '())]))

(define (assemble w events)
  (define t (true-done w))
  (define done (for/list ([e (msg-of (evs-of events 'V) 'Done)])
                 (list 'msg 'DONE (+ (- (ev-at e) (skew w)) (if (eq? (ref w 'delay) 'long) LONG SHORT)) (ev-at e))))
  (define att (for/list ([e (msg-of (evs-of events 'A) 'Attest)] #:when (or (not t) (eq? (ref w 'attest) 'delivered)))
                (list 'msg 'ATTEST (+ (ev-at e) ATTEST-DELAY) (ev-at e))))
  (define rd (if (eq? (ref w 'read) 'fresh)
                 (list 'read-ok T-READ (list 'record (v-stamp w)))
                 (list 'read-failed T-READ)))
  (values (by-arrival (append done att (list rd))) '()))

(define (truth w ds) (hash-ref ((family-execute deadline) (hasheq) IFACE w) 'truth))

(define (render ds)
  (for/list ([d ds] [i (in-naturals)])
    (case (car d)
      [(msg) (if (eq? (cadr d) 'DONE)
                 (format "[~a] arrived at ~a: DONE from V, stamped ~a by V's clock" i (caddr d) (cadddr d))
                 (format "[~a] arrived at ~a: ATTEST from the attester A, completion at ~a by the trusted clock" i (caddr d) (cadddr d)))]
      [(read-failed) (format "[~a] at ~a: the read-back of V's record failed" i (cadr d))]
      [(read-ok) (format "[~a] at ~a: read-back of V's record (complete as of ~a) — recorded completion stamp: ~a"
                         i (cadr d) (cadr d) (or (cadr (caddr d)) "none"))])))

(define texts
  (hasheq
   'scenario (format "You are a client H. A provider V owes you a service by instant ~a. V reports completion with a DONE message stamped by V's own clock, which may run ahead or behind; the report's transit may be short or long. An independent attester A, with a trusted clock, attests completion. At ~a you read back V's record of its completion stamp."
                     DEADLINE T-READ)
   'deps (list (cons 'temporal (format "the service was completed by instant ~a (true time)" DEADLINE))
               (cons 'completion (format "the service was completed at all by instant ~a" T-EVAL)))
   'commitments (format "C_t = C(V, H, true, service completed by ~a): temporal holds iff C_t is discharged. C_c = C(V, H, true, service completed by ~a): completion holds iff C_c is discharged." DEADLINE T-EVAL)
   'evidence (format "V's DONE and V's record are V's reports of its own performance, timed by V's clock, which may be skewed: they are not evidence of completion, and their stamps admit nothing. ATTEST is a third party's report timed by a trusted clock and is evidence. V's record, read at ~a, is complete through ~a: it shows that the service was not completed by a deadline only if complete through that deadline and not itself reporting completion." T-READ T-READ)
   'render render))

(define deadline-enactment
  (enactment 'deadline (list V A) 'H T-EVAL brief faithful assemble truth texts))
