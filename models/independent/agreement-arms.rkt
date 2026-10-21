#lang racket/base
;; Family `agreement` — the five arms (chor, fsm, comm, hybrid, hybrid-noe).
;;
;; The observer is the buyer B. Its deliveries, in order:
;;   (msg ACCEPT 2 1 terms)          S's acceptance, terms as-proposed | altered
;;   (msg CONFIRM 2 2) | (msg REJECT 2 2)   B's own outgoing reply
;;   (msg REVOKE 3 2)                if S revoked (S revokes only when not bound)
;;   (msg ACK 4 3)                   if S bound and the ACK was not dropped
;;   (read-ok 11 view) | (read-failed 11)   read-back of S's record
;; Dependencies, in order: fit, mutual.

(require
         "../core/arm.rkt"
         "../core/observe.rkt"
         "../families/agreement/terms.rkt")
(provide arms)

(define FAMILY 'agreement)

;; ---------------------------------------------------------------------------
;; Small readers over B's own deliveries (no inference, just lookup).

(define (first-index ds M) (let ([is (msg-indices ds M)]) (and (pair? is) (car is))))

;; terms carried by S's ACCEPT, or #f
(define (accepted-terms ds)
  (define i (first-index ds 'ACCEPT))
  (and i (let ([p (msg-payload (list-ref ds i))]) (and (pair? p) (car p)))))

;; B's own reply: 'CONFIRM, 'REJECT or #f, with its index
(define (own-reply ds)
  (cond [(first-index ds 'CONFIRM) => (λ (i) (values 'CONFIRM i))]
        [(first-index ds 'REJECT) => (λ (i) (values 'REJECT i))]
        [else (values #f #f)]))

;; a view of the expected shape, or #f
(define (view-of ds kind)
  (define v (read-view ds))
  (and (pair? v) (eq? (car v) kind) v))

;; Compose the two claims from what the judge concluded.
;;   terms   : 'as-proposed | 'altered | #f   (with its citation)
;;   b-bound : #t | #f | 'unknown            (B's own binding, with citations)
;;   s-bound : #t | #f | 'unknown            (S's binding, with citations)
;; fit    : as-proposed → nobody can be bound to unfit terms → Fulfilled;
;;          altered → Violated if anyone is bound, Fulfilled if nobody is.
;; mutual : Fulfilled if both or neither are bound, Violated if they differ.
(define (compose terms t-cite b-bound b-cite s-bound s-cite)
  (define known? (λ (x) (boolean? x)))
  (define fit
    (cond
      [(eq? terms 'as-proposed) (list 'fit 'Fulfilled t-cite)]
      [(eq? terms 'altered)
       (cond [(eq? b-bound #t) (list 'fit 'Violated (append t-cite b-cite))]
             [(eq? s-bound #t) (list 'fit 'Violated (append t-cite s-cite))]
             [(and (eq? b-bound #f) (eq? s-bound #f))
              (list 'fit 'Fulfilled (append t-cite b-cite s-cite))]
             [else (list 'fit 'Indeterminate '())])]
      [else (list 'fit 'Indeterminate '())]))
  (define mutual
    (if (and (known? b-bound) (known? s-bound))
        (list 'mutual (if (eq? b-bound s-bound) 'Fulfilled 'Violated) (append b-cite s-cite))
        (list 'mutual 'Indeterminate '())))
  (claims fit mutual))

(define (terms-cite ds) (let ([i (first-index ds 'ACCEPT)]) (if i (list i) '())))

;; ---------------------------------------------------------------------------
;; CHOR — choreography / multiparty session.
;; The global type is: S→B ACCEPT(terms); B→S CONFIRM | REJECT; then, after
;; CONFIRM, S→B ACK (S binds) or S→B REVOKE (S withdraws), with a timed branch
;; at B when neither has arrived by T-ACK-ARR. B's projection binds B when it
;; sends CONFIRM (protocol bind = send), and B confirms whatever terms arrive.
;; B holds its local session (the messages above, in order) and a read-back of
;; S's session log as S's last message. A message is the event it names:
;;   - B bound  ⇔ B sent CONFIRM (its own act in its projection).
;;   - S bound  ⇔ ACK in the session; S not bound ⇔ REVOKE in the session, or
;;     B sent REJECT (no branch of the global type binds S after REJECT).
;;     When B's timed branch fired, the session's continuation is read from S's
;;     last message: ACK → bound; REVOKE or ACCEPT → S never took the binding
;;     branch. The paradigm has no notion of the log being out of date. With no
;;     log, S's side is outside B's projection → Indeterminate.
;;   - fit: the ACCEPT label carries the terms; CONFIRM after ACCEPT(altered)
;;     binds B to altered terms → Violated; as-proposed terms always fit.
;;   - mutual: both bound or neither → Fulfilled, otherwise Violated.
(define (judge-chor ds)
  (define terms (accepted-terms ds))
  (define-values (reply ri) (own-reply ds))
  (define-values (b-bound b-cite)
    (case reply
      [(CONFIRM) (values #t (list ri))]
      [(REJECT) (values #f (list ri))]
      [else (values 'unknown '())]))
  (define ack (first-index ds 'ACK))
  (define rev (first-index ds 'REVOKE))
  (define lm (view-of ds 'last-message))
  (define-values (s-bound s-cite)
    (cond [ack (values #t (list ack))]
          [rev (values #f (list rev))]
          [(eq? reply 'REJECT) (values #f (list ri))]
          [lm (values (eq? (cadr lm) 'ACK) (list (read-index ds)))]
          [else (values 'unknown '())]))
  (compose terms (terms-cite ds) b-bound b-cite s-bound s-cite))

;; ---------------------------------------------------------------------------
;; FSM — protocol state machines.
;; B's machine: on ACCEPT(as-proposed) send CONFIRM → awaiting; on
;; ACCEPT(altered) send REJECT → rejected (fit-check). From awaiting: on ACK →
;; bound; on REVOKE → unbound; on its own timeout at T-ACK-ARR → unbound
;; (bind = ack: B is bound only in the state reached on ACK).
;; S's machine: offered --CONFIRM--> bound (emits ACK); offered --revoke-->
;; revoked (emits REVOKE); bound and revoked are final.
;; B holds its own state and a read-back of S's current state record, which is
;; authoritative: S is in the state it records.
;;   - B's own state is known from its own transitions.
;;   - S's state: an ACK or REVOKE consumed by B's machine is S's transition
;;     into a final state, so S is bound / revoked. Otherwise S's state is the
;;     one its record shows (trusted as current — no staleness notion); after
;;     REJECT, S can never take the CONFIRM-guarded transition to bound. With
;;     no record and no message from S, S's state is unknown → Indeterminate.
;;   - fit: bound states with altered terms → Violated; as-proposed → Fulfilled.
;;   - mutual: (bound, bound) or (unbound, not bound) → Fulfilled; else Violated.
(define (judge-fsm ds)
  (define terms (accepted-terms ds))
  (define-values (reply ri) (own-reply ds))
  (define ack (first-index ds 'ACK))
  (define rev (first-index ds 'REVOKE))
  (define-values (b-bound b-cite)
    (cond [ack (values #t (list ack))]
          [(eq? reply 'REJECT) (values #f (list ri))]
          [(eq? reply 'CONFIRM) (values #f (append (list ri) (if rev (list rev) '())))]
          [else (values 'unknown '())]))
  (define st (view-of ds 'state))
  (define-values (s-bound s-cite)
    (cond [ack (values #t (list ack))]
          [rev (values #f (list rev))]
          [(eq? reply 'REJECT) (values #f (list ri))]
          [st (values (eq? (cadr st) 'bound) (list (read-index ds)))]
          [else (values 'unknown '())]))
  (compose terms (terms-cite ds) b-bound b-cite s-bound s-cite))

;; ---------------------------------------------------------------------------
;; COMM — commitment-based protocol.
;; The commitment is C(S, B, confirmed, deliver on the terms). S's ACCEPT
;; creates it conditional; it is detached (in force, S bound) when S processes
;; B's confirmation; S's REVOKE before that releases it. B's REJECT means the
;; antecedent never holds. B treats the commitment as in force for itself only
;; when S acknowledges it (bind = ack), and confirms only fitting terms.
;; B, the creditor, holds the social events it saw and a read-back of S's
;; commitment ledger (active / released / none).
;;   - B in force ⇔ ACK received.
;;   - S's commitment: ACK → active; REVOKE → released; REJECT → never
;;     detached; otherwise the ledger's state as S holds it (active → S bound;
;;     released / none → not in force). Without a ledger and without a message
;;     from S, the creditor cannot tell whether the commitment was detached,
;;     and the delivery deadline lies beyond the run → Indeterminate.
;;   - fit: a commitment in force on altered terms → Violated; as-proposed
;;     terms fit → Fulfilled; altered and nothing in force → Fulfilled.
;;   - mutual: both sides hold the commitment in force, or neither → Fulfilled.
(define (judge-comm ds)
  (define terms (accepted-terms ds))
  (define-values (reply ri) (own-reply ds))
  (define ack (first-index ds 'ACK))
  (define rev (first-index ds 'REVOKE))
  (define-values (b-bound b-cite)
    (cond [ack (values #t (list ack))]
          [(eq? reply 'REJECT) (values #f (list ri))]
          [(eq? reply 'CONFIRM) (values #f (append (list ri) (if rev (list rev) '())))]
          [else (values 'unknown '())]))
  (define lg (view-of ds 'ledger))
  (define-values (s-bound s-cite)
    (cond [ack (values #t (list ack))]
          [rev (values #f (list rev))]
          [(eq? reply 'REJECT) (values #f (list ri))]
          [lg (values (eq? (cadr lg) 'active) (list (read-index ds)))]
          [else (values 'unknown '())]))
  (compose terms (terms-cite ds) b-bound b-cite s-bound s-cite))

;; ---------------------------------------------------------------------------
;; HYBRID — commitments + state-machine guards + evidentiary rules.
;; Same commitment and machines as above. B confirms only fitting terms and
;; binds on ACK or, failing it, when a fresh read-back of S's record shows S
;; bound (bind = ack-reconcile). The read-back is S's full record:
;; (full state terms as-of), with as-of its completeness watermark.
;;   - B's own binding follows its own rule, which B applies itself: ACK, or a
;;     record complete through S's processing instant (as-of ≥ T-S-PROCESS)
;;     that shows bound.
;;   - S's binding: S's ACK is the binding act itself (an acknowledgement is
;;     what makes S bound, not a report of some other performance), so ACK →
;;     bound. S's REVOKE is S's own report that it did not bind — a negative,
;;     which E1 admits. After B's REJECT, S's CONFIRM-guarded binding cannot
;;     occur. Otherwise (timed out): E2 — the record decides only if its
;;     watermark covers T-S-PROCESS, the instant by which binding would be
;;     recorded; a stale record (as-of 1) proves only that S was offered at 1,
;;     not that it did not bind later. E3 — no ACK, no REVOKE, no complete
;;     record → Indeterminate.
;;   - fit: as-proposed → Fulfilled; altered → B rejected, nobody bound →
;;     Fulfilled; anyone bound to altered terms → Violated.
;;   - mutual: both bound or neither → Fulfilled; else Violated.
(define (make-hybrid-judge evidentiary?)
  (λ (ds)
    (define terms (accepted-terms ds))
    (define-values (reply ri) (own-reply ds))
    (define ack (first-index ds 'ACK))
    (define rev (first-index ds 'REVOKE))
    (define fv (view-of ds 'full))
    (define ridx (read-index ds))
    (define (as-of v) (let ([a (cadddr v)]) (if (real? a) a -inf.0)))
    (define complete? (and fv (>= (as-of fv) T-S-PROCESS)))
    ;; B's own binding (protocol rule; freshness is part of B's own rule)
    (define-values (b-bound b-cite)
      (cond [ack (values #t (list ack))]
            [(eq? reply 'REJECT) (values #f (list ri))]
            [(and complete? (eq? (cadr fv) 'bound)) (values #t (list ridx))]
            [(eq? reply 'CONFIRM)
             (values #f (append (list ri) (if rev (list rev) '()) (if fv (list ridx) '())))]
            [else (values 'unknown '())]))
    ;; S's binding
    (define-values (s-bound s-cite)
      (cond [ack (values #t (list ack))]
            [rev (values #f (list rev))]
            [(eq? reply 'REJECT) (values #f (list ri))]
            [(and fv (or complete? (not evidentiary?)))
             (values (eq? (cadr fv) 'bound) (list ridx))]
            [else (values 'unknown '())]))
    (compose terms (terms-cite ds) b-bound b-cite s-bound s-cite)))

(define judge-hybrid (make-hybrid-judge #t))

;; ---------------------------------------------------------------------------
;; HYBRID-NOE — the hybrid without E1–E3.
;; Same mechanism, protocol and interface. Reports count as evidence and every
;; successful read-back is authoritative: when B timed out, S's state is
;; whatever the full record shows, whatever its watermark (a record as of 1
;; showing offered is taken to mean S never bound). B's own binding still
;; follows its protocol rule (bind on a fresh record showing bound). Only a
;; failed read with no message from S leaves S's side open → Indeterminate.
(define judge-hybrid-noe (make-hybrid-judge #f))

;; ---------------------------------------------------------------------------

(define arms
  (list
   (arm FAMILY 'chor (hasheq 'fit-check #f 'bind 'send) (hasheq 'view 'last-message) judge-chor)
   (arm FAMILY 'fsm (hasheq 'fit-check #t 'bind 'ack) (hasheq 'view 'state) judge-fsm)
   (arm FAMILY 'comm (hasheq 'fit-check #t 'bind 'ack) (hasheq 'view 'ledger) judge-comm)
   (arm FAMILY 'hybrid (hasheq 'fit-check #t 'bind 'ack-reconcile) (hasheq 'view 'full) judge-hybrid)
   (arm FAMILY 'hybrid-noe (hasheq 'fit-check #t 'bind 'ack-reconcile) (hasheq 'view 'full) judge-hybrid-noe)))
