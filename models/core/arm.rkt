#lang racket/base
;; The protocol arm descriptor.
;;
;; family    : symbol, the scenario family the arm is written for
;; name      : symbol (chor, fsm, comm, hybrid, hybrid-noe)
;; protocol  : hasheq of the family's conduct-affecting protocol features
;;             (how the arm's participants act: retry policy, binding rule,
;;             regrant policy, delegation rule ...). The world executes them.
;; interface : hasheq of what the protocol makes observable (which messages it
;;             defines, the read-back view kind). The world delivers by it.
;; judge     : deliveries → claims. Sees only deliveries, never the world.

(provide (struct-out arm))
(struct arm (family name protocol interface judge) #:transparent)
