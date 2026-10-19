; ---------------------------------------------------------------------------
; swap_remove(i) 之后,positions 仍是 order 的逆(在存活区间 [0, n-1) 上)
;
; 模型:order[k] = 第 k 个位置上的槽位号;positions[s] = 槽位 s 当前所在的位置。
; 检查的是这两条不变量在 swap_remove 这一步上是否自洽 —— 与本库 SPEC §13 R3 的
; 「只重排 order,不搬 rows」设计相对应。
;
; 结论:unsat(否定式不可满足,即结论成立)。
; ---------------------------------------------------------------------------
(set-logic ALL)

(declare-const n Int)                     ; 删除前的长度
(declare-const i Int)                     ; 要删除的位置
(declare-fun order () (Array Int Int))
(declare-fun positions () (Array Int Int))

; --- 前提 ---
(assert (> n 0))
(assert (and (>= i 0) (< i n)))
(define-fun j () Int (- n 1))             ; 最后一个位置

; order 在 [0,n) 上取值也在 [0,n)
(assert (forall ((k Int)) (=> (and (>= k 0) (< k n))
  (and (>= (select order k) 0) (< (select order k) n)))))

; order 在 [0,n) 上单射(有限集上单射即双射)
(assert (forall ((a Int) (b Int))
  (=> (and (>= a 0) (< a n) (>= b 0) (< b n)
           (= (select order a) (select order b)))
      (= a b))))

; positions 是 order 的逆
(assert (forall ((k Int)) (=> (and (>= k 0) (< k n))
  (= (select positions (select order k)) k))))

; --- swap_remove(i) 之后 ---
; order2:位置 i 换成原最后一个位置的槽位号
(define-fun order2 ((k Int)) Int (ite (= k i) (select order j) (select order k)))
; positions2:原最后一个槽位现在位于位置 i
(define-fun positions2 ((s Int)) Int (ite (= s (select order j)) i (select positions s)))

; --- 目标:新长度 [0, n-1) 内,positions2 仍是 order2 的逆 ---
(assert (not (forall ((k Int)) (=> (and (>= k 0) (< k j))
  (= (select positions2 (order2 k)) k)))))

(check-sat)
