// spec 005 CA2/CA7 — guard-let com `&&`-refino (condition presente) e sem (null).
guard let v = opt && v > 0 else { return }
guard let v = opt else { return }
