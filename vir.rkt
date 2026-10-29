#lang racket/base
;; Reading Verus `--log vir` output (crate.vir), design.md 结论18.
;;
;; The dump is S-expression text, so it is read with Racket's own `read`.
;; Only the characters that Racket's reader treats specially but VIR uses
;; inside atoms are remapped, via a readtable, to behave like an ordinary
;; symbol constituent.  Strings, parentheses, numbers and symbols are left
;; to `read`.
(require racket/list racket/string racket/match racket/fasl)
(provide load-vir cache-vir unwrap field walk span-file+line)

;; Characters made to behave like the letter `a` (i.e. plain symbol chars).
;; Extend this list if a real dump contains other reader-special characters.
(define symbol-like-chars '(#\# #\| #\' #\` #\, #\\))

(define vir-readtable
  (for/fold ([rt #f]) ([c symbol-like-chars])
    (make-readtable rt c #\a #f)))

;; read-vir : path-string -> (listof any)
;; Every top-level S-expression in the file.
(define (read-vir path)
  (parameterize ([current-readtable vir-readtable]
                 [read-accept-reader #f]
                 [read-accept-lang #f])
    (call-with-input-file path
      (lambda (in) (for/list ([x (in-port read in)]) x)))))

;; load-vir : path-string -> (listof any)
;; A `.fasl` file is a cache written by cache-vir; anything else is read as
;; crate.vir text, which takes much longer (about 20 s for vostd's ostd).
(define (load-vir path)
  (if (regexp-match? #rx"[.]fasl$" (if (path? path) (path->string path) path))
      (call-with-input-file path fasl->s-exp)
      (read-vir path)))

;; cache-vir : vir-path fasl-path -> number of top-level items
(define (cache-vir vir-path out-path)
  (define items (read-vir vir-path))
  (call-with-output-file out-path #:exists 'replace
    (lambda (o) (s-exp->fasl items o)))
  (length items))

;; VIR wraps nodes with span/type annotations: (@ <span> <node>) or (@@ ...).
(define (unwrap node)
  (if (and (pair? node) (memq (car node) '(@ @@)) (>= (length node) 3))
      (unwrap (caddr node))
      node))

;; (field node 'name) finds `:name <value>` inside a node, or #f.
(define (field node name)
  (define n (unwrap node))
  (define key (string->symbol (string-append ":" (symbol->string name))))
  (and (list? n)
       (let ([m (memq key n)])
         (and m (pair? (cdr m)) (cadr m)))))

;; walk : any -> (listof list) — every list node, preorder.
(define (walk node)
  (if (pair? node)
      (cons node (append-map walk (filter pair? node)))
      '()))

;; span-file+line : VIR span string -> (cons file line) or #f
;; "ostd\\src\\mm\\io.rs:1576:5: 1597:61 (#0)" -> ("ostd/src/mm/io.rs" . 1576).
;; The path is normalised to forward slashes with `..` resolved; a leading
;; `/` (an absolute path on Unix) is kept, so that absolute paths can be told
;; from relative ones.
(define (span-file+line s)
  (match (and (string? s) (regexp-match #px"^(.*):([0-9]+):[0-9]+: [0-9]+:[0-9]+ \\(#[0-9]+\\)$" s))
    [(list _ f l) (cons (normalise f) (string->number l))]
    [_ #f]))

(define (normalise f)
  (define g (string-replace f "\\" "/"))
  (string-append
   (if (string-prefix? g "/") "/" "")
   (string-join
    (reverse
     (for/fold ([acc '()]) ([p (string-split g "/")])
       (cond [(equal? p "..") (if (pair? acc) (cdr acc) acc)]
             [(equal? p ".") acc]
             [else (cons p acc)])))
    "/")))
