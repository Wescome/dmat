#lang racket/base
;; DMAT executable models — the base grammar every family extends.
;;
;; A family's terms module extends DMAT0 with its own worlds and read-back
;; views (define-extended-language), so that each family's terms form a
;; closed language. DMAT0 fixes what is common: instants, judgments, claims,
;; and the shape of a delivery.
;;
;; A delivery is what an arm's observer receives:
;;   (msg M arrival asserted payload ...)  a message of kind M, its arrival
;;        instant, the instant its sender asserts for it (the sender's clock
;;        or the event it reports), and its payload;
;;   (read-ok t view)                      a read-back at t returning a view;
;;   (read-failed t)                       a read-back at t that returned nothing.

(require redex/reduction-semantics)
(provide DMAT0 claims-term? JUDGMENTS DEFINITIVE)

(define JUDGMENTS '(Fulfilled Violated Pending Indeterminate))
(define DEFINITIVE '(Fulfilled Violated Pending))

(define-language DMAT0
  (b #t #f)
  (t natural)
  (J Fulfilled Violated Pending Indeterminate)
  (dep variable-not-otherwise-mentioned)
  (cl (claim dep J (natural ...)))
  (cls (cl ...))
  (payload any)
  (view any)
  (d (msg variable t t payload ...)
     (read-ok t view)
     (read-failed t))
  (ds (d ...)))

(define claims-term? (redex-match? DMAT0 cls))
