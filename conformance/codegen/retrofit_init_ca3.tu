// **CA3 da spec 013 §11, 2ª cláusula** — *"`extensionInits` são construtores
// adicionais (ADR-0016 §B)"*.
//
// O gabarito é o ADR-0016 §B: `init` no CORPO **mata** o memberwise; em
// `extension` o **PRESERVA** — *"a extension é o glifo que diz 'estou
// ADICIONANDO, não substituindo'"*. No Kernel isso vira um `Constructor` por
// `init`: o primário fica NÃO-nomeado (`P(...)`) e os de `extension` ganham nome
// derivado dos labels (`init$diagonal`).
//
// ⚠️ **O nome sai dos LABELS, nunca do índice na lista.** A ordem de coleta é a
// ordem textual das `extension`, e a R2 cobra que permutar declarações seja
// inobservável — com nome por índice, permutar renomearia construtores no
// `.dill`, e um golden de stdout não veria. Os labels bastam para ser único
// porque a F5 recusa dois candidatos com a mesma lista (`duplicate-init`, ver
// `err_duplicate_init.tu`).
//
// ⚠️ **Qual construtor cada chamada usa é decisão da F5, não daqui.** Ela
// seleciona por label (`_labelsFit`, `check.dart`) e grava o vencedor em
// `ResolvedCall.initTarget`; a F7 apenas encontra o `Constructor` que emitiu
// para aquela decl. Re-casar labels no emitter seria refazer no lexema uma
// decisão já tomada com a tabela de tipos (R1) — e o `slot` da MESMA
// `ResolvedCall` vem do `init` escolhido, então discordar dela poria os args no
// construtor errado sem nada ficar malformado.

// (1) `struct` — memberwise sintetizado + o de `extension`. As DUAS portas
// coexistem, que é o conteúdo inteiro do §B.
struct Ponto {
  x: Int,
  y: Int
}

extension Ponto {
  init(diagonal: Int) {
    self.x = diagonal
    self.y = diagonal
  }
}

// (2) `class` — o `init` do CORPO é o primário, e não há memberwise a preservar:
// *"`struct` usa construtor **memberwise sintetizado** (sem `init` explícito —
// concisão); `class` usa `init` **explícito**"* (ADR-0012 §A-1). O de
// `extension` é adicional.
class Conta {
  var saldo: Int,
  var ativa: Bool

  init(inicial: Int) {
    self.saldo = inicial
    self.ativa = true
  }
}

extension Conta {
  init(encerrada: Int) {
    self.saldo = encerrada
    self.ativa = false
  }
}

// (3) `class` construída **só** por `extension` — sem `init` no corpo e sem
// memberwise, o único construtor vem do retrofit. A F5 abre esta porta de
// propósito (`cands.isNotEmpty`, e não `> 1`): fechá-la seria dar o hint "escreva
// o init numa extension" e trancar a saída.
class Registro {
  nome: String
}

extension Registro {
  init(de: String) {
    self.nome = de
  }
}

// (4) dois `init` de `extension` no mesmo tipo, com labels distintos — ambos
// alcançáveis, e nenhum deles é o primário.
struct Faixa {
  ini: Int,
  fim: Int
}

extension Faixa {
  init(ate: Int) {
    self.ini = 0
    self.fim = ate
  }
}

extension Faixa {
  init(unica: Int) {
    self.ini = unica
    self.fim = unica
  }
}

fn main() {
  // as duas portas do `struct`: memberwise E extension
  let a = Ponto(x: 1, y: 2)
  let b = Ponto(diagonal: 7)
  print("struct: ${a.x},${a.y} ${b.x},${b.y}")

  // `class`: corpo E extension
  let c = Conta(inicial: 100)
  let d = Conta(encerrada: 0)
  print("class: ${c.saldo}/${c.ativa} ${d.saldo}/${d.ativa}")

  // `class` sem primário nenhum
  let r = Registro(de: "itá")
  print("so extension: ${r.nome}")

  // dois adicionais, escolhidos por label
  let f = Faixa(ate: 9)
  let g = Faixa(unica: 4)
  print("dois adicionais: ${f.ini}-${f.fim} ${g.ini}-${g.fim}")
}
