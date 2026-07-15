let a = xs.map { $0 >> f }
let b = xs.map { f >> $0 }
let c = xs.map { ($0 >> f)($1) }
let d = xs.map { match y {
  "${$0}" => 1
  _ => 2
} }
