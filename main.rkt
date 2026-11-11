#lang racket/base
;; Command line (README.md):
;;   racket main.rkt check <vir>[,<vir>...] <out.results> <src-root> [<item-index>]
;;       check every function and write the results (design.md, 结论22);
;;       each <vir> is a crate.vir or a cache made by `cache`, one per crate;
;;       <src-root> is the checkout the VIR was exported from
;;   racket main.rkt report <in.results> <out.md> <selector> [--lang zh|en]
;;       expand the results into the report (结论23) on the functions
;;       <selector> picks (select.rkt, 结论20), in Chinese (default) or English
;;   racket main.rkt cache <crate.vir> <out.fasl>
;;       read a crate.vir once and cache it, so that `check` starts faster
;;
;; The report's layout is in report.rkt and its wording in text/<lang>.rkt;
;; this file holds neither.
(require racket/list racket/string racket/match racket/runtime-path
         "check.rkt" "items.rkt" "results.rkt" "select.rkt" "vir.rkt" "report.rkt"
         (prefix-in zh: "text/zh.rkt") (prefix-in en: "text/en.rkt"))

;; ================================================================ languages

;; The report's wording, one module per language (report.rkt, `text-keys`).
;; zh is the default; CI passes --lang en.
(define languages (hash "zh" zh:texts "en" en:texts))
(define default-language "zh")

;; ================================================================ command line

;; Where `cargo build --release` in item-index/ puts the parser by default.
(define-runtime-path release-dir "item-index/target/release")
(define default-item-index
  (build-path release-dir (if (eq? (system-type) 'windows) "item-index.exe" "item-index")))

;; <in> may name several VIR dumps separated by commas, one per crate.  The
;; parser supplies each function's name and lines (结论21).
(define (check in out src-root exe)
  (define vir (string-split in ","))
  (define dumps (map load-vir vir))
  (for* ([(p items) (in-parallel vir dumps)] [w (vir-format-warnings items)])
    (eprintf "warning: ~a: ~a\n" p w))
  (define rs (run-check dumps))
  (define (loc r) (and (fn-file r) (cons (fn-file r) (fn-line r))))
  (define idx (load-item-index exe src-root (filter values (map loc rs))))
  (define checked
    (for/list ([r rs])
      (define-values (name lines) (if (loc r) (parser-source idx (loc r) (fn-path r)) (values #f #f)))
      (fn-with-source r name lines)))
  (write-results out vir checked)
  (printf "~a functions checked, results written to ~a\n" (length rs) out)
  ;; expected for derive- and macro-generated functions (注意9); if it is
  ;; most of them, the source root or the parser does not match the VIR
  (define unnamed (count fn-inferred? checked))
  (when (> unnamed 0)
    (printf "~a of them not found by the source parser; they keep the names inferred from VIR (design.md, 注意9)\n" unnamed)))

;; A selector read from a file is shown as `@FILE`, not expanded.
(define (report-on in out selector lang)
  (define texts
    (hash-ref languages lang
              (lambda ()
                (raise-user-error 'report "unknown language ~s; known: ~a" lang
                                  (string-join (sort (hash-keys languages) string<?) ", ")))))
  (define sel (read-selector selector))
  (define-values (_ all) (read-results in))
  (report (filter (compile-selector sel) all)
          (if (string-prefix? selector "@") selector (selector->string sel))
          (length all) out texts))

(define (cache vir out)
  (printf "~a top-level items cached to ~a\n" (cache-vir vir out) out))

(define usage "usage: racket main.rkt check <vir>[,<vir>...] <out.results> <src-root> [<item-index>]
       racket main.rkt report <in.results> <out.md> <selector> [--lang zh|en]
       racket main.rkt cache <crate.vir> <out.fasl>
")

;; `--lang L` may stand anywhere among the arguments of `report`.
(define (take-lang args)
  (let loop ([as args] [acc '()])
    (match as
      [(list* "--lang" l rest) (values l (append (reverse acc) rest))]
      [(cons a rest) (loop rest (cons a acc))]
      ['() (values default-language args)])))

;; The arguments are parsed here rather than by `command-line`, which would
;; reject `--lang` before the subcommand as an unknown switch.
(module+ main
  (define-values (lang args) (take-lang (vector->list (current-command-line-arguments))))
  (match args
    [(list "check" in out src-root) (check in out src-root default-item-index)]
    [(list "check" in out src-root exe) (check in out src-root exe)]
    [(list "report" in out selector) (report-on in out selector lang)]
    [(list "cache" vir out) (cache vir out)]
    [_ (eprintf usage) (exit 2)]))
