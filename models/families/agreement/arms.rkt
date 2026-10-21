#lang racket/base
;; Family 3 — multi-party agreement. The five arms.

(require racket/list "../../core/arm.rkt" "../../core/observe.rkt" "terms.rkt")
(provide arms)

(define (accept-i ds) (car (msg-indices ds 'ACCEPT)))
(define (accept-terms ds) (car (msg-payload (list-ref ds (accept-i ds)))))
(define (confirmed? ds) (pair? (msg-indices ds 'CONFIRM)))

;; S's binding as B's own session shows it: S's ACK shows S bound; S's REVOKE
;; shows S not bound (S revokes only when it is not bound); B's own REJECT
;; means S never received a confirmation and cannot be bound. → (cons bound? cites) or #f
(define (s-bound-by-messages ds)
  (define acks (msg-indices ds 'ACK)) (define revs (msg-indices ds 'REVOKE)) (define rej (msg-indices ds 'REJECT))
  (cond [(pair? acks) (cons #t acks)]
        [(pair? revs) (cons #f revs)]
        [(pair? rej) (cons #f rej)]
        [else #f]))

(define (mutual-claim b-bound b-cites s)   ; s: (cons bound? cites) or #f
  (cond [s (list 'mutual (if (eq? b-bound (car s)) 'Fulfilled 'Violated) (append b-cites (cdr s)))]
        [else (list 'mutual 'Indeterminate '())]))

;; CHOR — global type: B→S PROPOSE; S→B ACCEPT(terms); B→S CONFIRM | REJECT;
;; S→B ACK | REVOKE. Messages are checked by type, not by payload value (no
;; refinement types), so B confirms whatever S accepted, and B is bound when it
;; sends CONFIRM. Fit: the trace conforms to the global type: Fulfilled. Mutual:
;; S's state from the session (ACK, REVOKE, B's REJECT); when B's timer for S's
;; answer fires with neither, S's last recorded session message decides (ACK:
;; bound; REVOKE or ACCEPT: not bound); with no read, Indeterminate.
(define (chor-judge ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (define lm (and v (cadr v)))
  (define confirm (msg-indices ds 'CONFIRM))
  (define s (or (s-bound-by-messages ds) (and lm (cons (eq? lm 'ACK) (list ri)))))
  (claims (list 'fit 'Fulfilled (list (accept-i ds)))
          (mutual-claim (pair? confirm) (append confirm (msg-indices ds 'REJECT)) s)))

;; FSM — B: proposed → (terms fit? confirming : rejected) → bound on ACK.
;; S: offered → bound on CONFIRM | revoked. Guards check the terms value, so
;; fit is Fulfilled. An ACK or REVOKE B's machine received moves S to a final
;; state, and after B's REJECT S cannot reach bound; otherwise S's state record
;; is authoritative. No read and no final message: Indeterminate.
(define (fsm-judge ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (define acks (msg-indices ds 'ACK))
  (define s (or (s-bound-by-messages ds) (and v (cons (eq? (cadr v) 'bound) (list ri)))))
  (claims (list 'fit 'Fulfilled (list (accept-i ds)))
          (mutual-claim (pair? acks) acks s)))

;; COMM — CONFIRM detaches C(S,B, confirmed, deliver on the terms) when S
;; receives it; ACK communicates the commitment as active; REVOKE releases S's
;; offer; after B's REJECT the commitment never detaches. B holds itself bound
;; when it holds the ACK. Fit: commitments are over the stated terms and B
;; confirms only fitting ones: Fulfilled. Mutual: B's holding against the
;; commitment's state, from messages or else S's ledger (active: bound).
(define (comm-judge ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (define acks (msg-indices ds 'ACK))
  (define s (or (s-bound-by-messages ds) (and v (cons (eq? (cadr v) 'active) (list ri)))))
  (claims (list 'fit 'Fulfilled (list (accept-i ds)))
          (mutual-claim (pair? acks) acks s)))

;; HYBRID — FSM guards on terms; B bound on ACK, or on reconciliation: at the
;; read-back B binds if S's record, complete past S's processing, shows S
;; bound. S's binding from its ACK (the act that creates the binding, not a
;; report of performance), its REVOKE or B's REJECT (negatives), or else an
;; authoritative record of S (watermark ≥ T-S-PROCESS). Fit from the terms in
;; S's ACCEPT and B's own CONFIRM/REJECT. HYBRID-NOE: every read authoritative.
(define ((hybrid-judge evidence?) ds)
  (define v (read-view ds)) (define ri (read-index ds))
  (define-values (ss wm) (if v (values (cadr v) (cadddr v)) (values #f #f)))
  (define auth (and v (or (not evidence?) (>= wm T-S-PROCESS))))
  (define acks (msg-indices ds 'ACK))
  (define b-bound (or (pair? acks) (and auth (eq? ss 'bound))))
  (define b-cites (append acks (if (and auth (eq? ss 'bound)) (list ri) '())))
  (define s (or (s-bound-by-messages ds) (and auth (cons (eq? ss 'bound) (list ri)))))
  (define fit-cites (append (list (accept-i ds)) (msg-indices ds 'CONFIRM) (msg-indices ds 'REJECT)))
  (claims (if (and (confirmed? ds) (eq? (accept-terms ds) 'altered))
              (list 'fit 'Violated fit-cites)
              (list 'fit 'Fulfilled fit-cites))
          (mutual-claim b-bound b-cites s)))

(define arms
  (list (arm 'agreement 'chor (hasheq 'fit-check #f 'bind 'send) (hasheq 'view 'last-message) chor-judge)
        (arm 'agreement 'fsm (hasheq 'fit-check #t 'bind 'ack) (hasheq 'view 'state) fsm-judge)
        (arm 'agreement 'comm (hasheq 'fit-check #t 'bind 'ack) (hasheq 'view 'ledger) comm-judge)
        (arm 'agreement 'hybrid (hasheq 'fit-check #t 'bind 'ack-reconcile) (hasheq 'view 'full) (hybrid-judge #t))
        (arm 'agreement 'hybrid-noe (hasheq 'fit-check #t 'bind 'ack-reconcile) (hasheq 'view 'full) (hybrid-judge #f))))
