#lang racket/base
;; Chinese wording of the report.  The keys and their arguments are listed
;; in report.rkt (`text-keys`); arguments that are code arrive already
;; formatted, e.g. "`Frame`".
(provide texts)

(define (ghost g) (if g "幽灵" ""))

(define texts
  (hash
   'title (lambda () "postcondition未提及的输出")
   'scope
   (lambda (total sel n exec proof pub private)
     (format "检查范围: 已检查的~a个exec函数和proof函数中, 选择器~a选中的~a个 (exec ~a个, proof ~a个; pub ~a个, 非pub ~a个). 设计见`design.md`."
             total sel n exec proof pub private))
   'summary-heading (lambda () "汇总")
   'summary-columns (lambda () '("组" "函数" "输出" "报告"))
   'group-name (lambda (g) (if g "有postcondition的函数" "没有postcondition的函数"))
   'tally-columns (lambda () '("问题" "无任何约束" "只有类型不变量"))
   'kind-name
   (lambda (k)
     (case k
       [(return-unmentioned) "返回值未被提及"]
       [(mut-param-unmentioned) "`&mut`参数调用后的状态未被提及"]))
   'trait-impls
   (lambda (impls own with-decl merged merged-reported)
     (format "trait方法的实现共~a个: 自身附加了postcondition子句的~a个, 逐个列出; 其余的结果与声明相同, 其中声明也在本报告中的~a个随声明报告, 不再列出, 声明不在本报告中的~a个按trait方法合并 (其中有报告的~a个列在正文中)."
             impls own with-decl merged merged-reported))
   'no-findings (lambda () "无报告.")
   'selected-heading (lambda () "选中的函数")
   'selected-columns (lambda () '("函数" "位置" "报告"))
   'private (lambda () "非pub")
   'merged-heading (lambda (decl n) (format "~a (~a个实现, 规格都来自该声明, 结果相同)" decl n))
   'merged-example (lambda () "以第一个实现为例:")
   'finding-return
   (lambda (g name ty)
     (format "返回~a值~a的类型为~a. postcondition中没有出现返回值的名字, 也没有`returns`子句."
             (ghost g) (or name "") ty))
   'finding-return-component
   (lambda (i name ty)
     (format "`#[verus_spec]`返回元组的第~a个分量 (~a返回值~a, 类型为~a) 没有被postcondition提及."
             i (if (= i 0) "exec" "幽灵") (or name "") ty))
   'finding-mut
   (lambda (g name ty raw)
     (format "~a参数~a的类型为~a. postcondition中的`final(...)`都不包含`~a`, 调用者只能假设它可能被任意修改."
             (ghost g) name ty raw))
   'finding-type-inv
   (lambda (inv)
     (format " 只有类型不变量: 调用者只知道它满足类型不变量~a, 不知道它与参数或调用前状态的关系." inv))
   'finding-default-only
   (lambda () " 只在`default_ensures`中提及: 只有沿用默认函数体的实现保证这一点, 经由trait泛型调用时得不到.")
   'fn-external-body (lambda () "`external_body`: 函数体未经验证, 规格是被信任的")
   'fn-post-from-decl
   (lambda (decl own?) (format "postcondition来自trait声明~a~a" decl (if own? "和实现自身附加的子句" "")))
   'fn-decl-missing (lambda (decl) (format "未找到trait声明~a, 只按实现自身的子句检查" decl))
   'fn-inferred (lambda () "名称由VIR推断")))
