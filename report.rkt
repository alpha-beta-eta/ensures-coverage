#lang racket/base
;; The report (design.md, 结论23): its layout only.  Every word a reader
;; sees comes from a language module (text/zh.rkt, text/en.rkt), which
;; provides `texts`: a hash from each key of `text-keys` below to a
;; procedure returning a string.  This module holds no natural-language
;; text, so a language is added by adding a file, and the layout is changed
;; without touching any wording.
;;
;; Arguments that are code (names, types, paths, locations) arrive already
;; formatted as Markdown code, e.g. "`Frame`", so a language module only
;; composes words around them.
(require racket/list racket/string racket/match racket/set
         "results.rkt")
(provide report text-keys)

;; key -> number of arguments, and what they are
(define text-keys
  '((title . 0)
    (scope . 7)             ; total selector-code selected exec proof pub non-pub
    (summary-heading . 0)
    (summary-columns . 0)   ; -> list of 4 column names: group, functions, outputs, findings
    (group-name . 1)        ; #t = has a postcondition, #f = has none
    (tally-columns . 0)     ; -> list of 3: finding kind, unconstrained, type invariant only
    (kind-name . 1)         ; 'return-unmentioned | 'mut-param-unmentioned
    (trait-impls . 5)       ; impls own with-decl merged merged-with-findings
    (no-findings . 0)
    (selected-heading . 0)
    (selected-columns . 0)  ; -> list of 3: function, location, findings
    (private . 0)           ; the label for a non-pub function
    (merged-heading . 2)    ; declaration-code number-of-implementations
    (merged-example . 0)
    (finding-return . 3)    ; ghost? name-code-or-#f type-code
    (finding-return-component . 3) ; index name-code-or-#f type-code (index 0 = the exec return)
    (finding-mut . 4)       ; ghost? name-code type-code name
    (finding-type-inv . 1)  ; invariant-code
    (finding-default-only . 0)
    (fn-external-body . 0)
    (fn-post-from-decl . 2) ; declaration-code own-clauses-too?
    (fn-decl-missing . 1)   ; declaration-code
    (fn-inferred . 0)))

(define (code s) (format "`~a`" s))

;; "ostd/src/mm/io.rs:1576", the signature's line
(define (location r) (if (fn-file r) (format "~a:~a" (fn-file r) (fn-line r)) ""))

;; by file, then by line as a number (not as text: 93 before 663)
(define (location<? a b)
  (define fa (or (fn-file a) "")) (define fb (or (fn-file b) ""))
  (or (string<? fa fb)
      (and (string=? fa fb) (< (or (fn-line a) 0) (or (fn-line b) 0)))))

(define (by-location rs) (sort rs location<?))

(define (findings rs) (append-map fn-findings rs))

;; 结论23: how a trait method implementation appears in the report.
;;   'with-decl  no clauses of its own, the declaration is in the report: omitted
;;   'merged     no clauses of its own, the declaration is not in the report:
;;               merged with the other implementations of the same method
;;   'own        listed on its own
;; reported? : declaration path -> boolean
(define (placement r reported?)
  (cond [(or (not (fn-trait r)) (fn-own-post? r)) 'own]
        [(reported? (fn-trait r)) 'with-decl]
        [else 'merged]))

(define (table-header cols)
  (format "| ~a |\n|~a\n" (string-join cols " | ")
          (apply string-append (for/list ([_ cols]) "---|"))))

;; report : (listof fn) selector-text total out-path texts -> void
;;   total  number of functions checked, before the selector
;;   texts  a language module's `texts`
(define (report rs scope total out-path texts)
  (define (t key . args) (apply (hash-ref texts key) args))
  (define (explain-finding fi)
    (define x (and (finding-output fi) (code (finding-output fi))))
    (define ty (code (typ->text (finding-typ fi))))
    (string-append
     (match (finding-role fi)
       ['return (t 'finding-return (finding-ghost? fi) x ty)]
       ['return-component (t 'finding-return-component (finding-index fi) x ty)]
       ['mut-param (t 'finding-mut (finding-ghost? fi) x ty (finding-output fi))])
     (if (finding-type-inv fi) (t 'finding-type-inv (code (short-path (finding-type-inv fi)))) "")
     (if (finding-default-only? fi) (t 'finding-default-only) "")))
  ;; the line under a function's heading
  (define (explain-function r)
    (define decl (fn-trait r))
    (string-join
     (filter values
             (list (code (location r))
                   (symbol->string (fn-mode r))
                   (and (not (fn-public? r)) (t 'private))
                   (and (fn-external-body? r) (t 'fn-external-body))
                   (and decl (fn-trait-found? r) (t 'fn-post-from-decl (code decl) (fn-own-post? r)))
                   (and decl (not (fn-trait-found? r)) (t 'fn-decl-missing (code decl)))
                   (and (fn-inferred? r) (t 'fn-inferred))))
     " · "))
  (define (print-findings r)
    (for ([fi (fn-findings r)])
      (printf "- **~a**~a: ~a\n" (t 'kind-name (finding-kind fi))
              (if (finding-output fi) (format " (~a)" (code (finding-output fi))) "")
              (explain-finding fi))))
  (define in-report (for/set ([r rs]) (fn-path r)))
  (define (place r) (placement r (lambda (d) (set-member? in-report d))))
  (define (in-group g) (filter (lambda (r) (eq? (fn-has-post? r) g)) rs))
  (define (tally rs)
    (display (table-header (t 'tally-columns)))
    (for ([k finding-kinds])
      (define fs (filter (lambda (fi) (eq? (finding-kind fi) k)) (findings rs)))
      (printf "| ~a | ~a | ~a |\n" (t 'kind-name k)
              (count (lambda (fi) (not (finding-type-inv fi))) fs)
              (count finding-type-inv fs))))
  (define (print-group rs)
    (define own (filter (lambda (r) (and (eq? (place r) 'own) (pair? (fn-findings r)))) rs))
    (define merged
      (filter (lambda (g) (pair? (fn-findings (car g))))
              (group-by fn-trait
                        (by-location (filter (lambda (r) (eq? (place r) 'merged)) rs)))))
    ;; one entry per function, or per merged trait method, by source position
    (define entries
      (sort (append (map list own) merged) location<? #:key car))
    (when (null? entries) (printf "~a\n\n" (t 'no-findings)))
    (for ([e entries])
      (match e
        [(list r)
         (printf "### ~a\n\n~a\n\n" (code (fn-name r)) (explain-function r))
         (print-findings r)]
        [(cons r _)
         (printf "### ~a\n\n" (t 'merged-heading (code (fn-trait r)) (length e)))
         (for ([x e])
           (printf "- ~a: ~a\n" (code (fn-name x)) (code (location x))))
         (printf "\n~a\n\n" (t 'merged-example))
         (print-findings r)])
      (newline)))
  (with-output-to-file out-path #:exists 'replace
    (lambda ()
      (printf "# ~a\n\n" (t 'title))
      (printf "~a\n\n"
              (t 'scope total (code scope) (length rs)
                 (count (lambda (r) (eq? (fn-mode r) 'exec)) rs)
                 (count (lambda (r) (eq? (fn-mode r) 'proof)) rs)
                 (count fn-public? rs)
                 (count (lambda (r) (not (fn-public? r))) rs)))
      (printf "## ~a\n\n" (t 'summary-heading))
      (display (table-header (t 'summary-columns)))
      (for ([g '(#t #f)])
        (define gs (in-group g))
        (printf "| ~a | ~a | ~a | ~a |\n" (t 'group-name g) (length gs)
                (apply + (map fn-outputs gs)) (length (findings gs))))
      (for ([g '(#t #f)])
        (printf "\n**~a**\n\n" (t 'group-name g))
        (tally (in-group g)))
      (define impls (filter fn-trait rs))
      (define merged (filter (lambda (r) (eq? (place r) 'merged)) impls))
      (printf "\n~a\n\n"
              (t 'trait-impls (length impls)
                 (count (lambda (r) (eq? (place r) 'own)) impls)
                 (count (lambda (r) (eq? (place r) 'with-decl)) impls)
                 (length merged)
                 (count (lambda (r) (pair? (fn-findings r))) merged)))
      (for ([g '(#t #f)])
        (printf "## ~a\n\n" (t 'group-name g))
        (print-group (in-group g)))
      (printf "## ~a\n\n" (t 'selected-heading))
      (display (table-header (t 'selected-columns)))
      (for ([r (by-location rs)])
        (printf "| ~a | ~a | ~a |\n" (code (fn-name r))
                (string-join (filter values (list (code (location r))
                                                  (symbol->string (fn-mode r))
                                                  (and (not (fn-public? r)) (t 'private))))
                             " · ")
                (length (fn-findings r))))))
  (printf "report written to ~a\n" out-path))
