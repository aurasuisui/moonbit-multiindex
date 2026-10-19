; ---------------------------------------------------------------------------
; clear() 批量退役 + 代际号单调 => clear 之前的 RowId 不会命中 clear 之后的记录
;
; 模型:gen0 为 clear 前的代际号数组,gen1 为 clear 后的;句柄 (s, gen0[s]) 在
; clear 前有效,问它是否可能仍然是 gen1 之后的有效句柄。
; 这是本库拒绝「clear 后把槽位代际号清零再放回 free」的理由(会静默复活旧句柄)。
;
; 结论:unsat。
; ---------------------------------------------------------------------------
(set-logic ALL)

(declare-const s Int)                     ; 某个槽位
(declare-fun gen0 () (Array Int Int))     ; clear 之前的代际号
(declare-fun gen1 () (Array Int Int))     ; clear 之后的代际号

; --- 前提 ---
; 1) clear 对每个槽位把代际号 +1(批量退役,而非清零)
(assert (forall ((x Int)) (= (select gen1 x) (+ (select gen0 x) 1))))

; --- 目标:clear 之前的句柄 (s, gen0[s]) 在 clear 之后不再成立 ---
(assert (not (forall ((g Int))
  (=> (= g (select gen0 s)) (not (= (select gen1 s) g))))))

(check-sat)
