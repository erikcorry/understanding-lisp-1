/// Binary minus function.
(rplacd (quote -) (quote (expr (lambda (x y) (plus x (minus y))))))

/// Operator synonyms for plus, times, quotient.
(rplacd (quote +) (cdr (quote plus)))
(rplacd (quote *) (cdr (quote times)))
(rplacd (quote /) (cdr (quote quotient)))

/// For some reason we can't use % for this.
(rplacd (quote mod) (quote (expr (lambda (x y)
  (- x (* y (/ x y)))
))))
