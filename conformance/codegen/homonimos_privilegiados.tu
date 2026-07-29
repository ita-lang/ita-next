// Um enum do USUÁRIO pode ter variantes chamadas `none`, `some`, `ok`, `err`.
//
// Este é o fixture METAMÓRFICO da família de `match`: ele é o `match_option.tu`
// e o `result_try.tu` com os identificadores do usuário renomeados **para os
// lexemas privilegiados**. A semântica é outra — são enums comuns — e a saída
// tem de ser a que o programa diz, não a que o lexema sugere.
//
// Até 2026-07-29 os três casos aqui compilavam ERRADO, e nenhum golden percebia:
//
//   - `.none` de um enum do usuário virava `subject == null` (sempre falso),
//     porque o teste do lexema vinha ANTES de olhar o tipo do escrutínio;
//   - `.ok`/`.err` de um enum do usuário viravam `as ItaResult$ok` — mas SÓ
//     quando algum outro ponto do programa mencionasse `Result`, porque o guard
//     era uma flag global (`_resultParts != null`);
//   - o `match` de produto resolvia os campos varrendo todas as classes por
//     NOME, então um pattern com o tipo errado lia o campo da classe errada.
//
// Os três eram silenciosos: o programa rodava e imprimia uma resposta plausível.

enum Estado { none, ativo, some }

enum Resposta { ok, falha, err }

struct Ponto { x: Int, y: Int }

struct Caixa { x: Int, largura: Int }

fn descreve(e: Estado) -> String =>
  match e {
    .none => "parado"
    .ativo => "rodando"
    .some => "alguns"
  }

fn responde(r: Resposta) -> String =>
  match r {
    .ok => "certo"
    .falha => "caiu"
    .err => "erro"
  }

// A presença de `Result` no programa é o que ativava o bug 3. Esta função nunca
// é chamada: ela existe para materializar o `ItaResult` no cache global e provar
// que a emissão de `responde` NÃO depende dela.
fn usaResult() -> Result<Int, String> => .ok(1)

fn leituraDeProduto(p: Ponto) -> Int =>
  match p {
    Ponto { x: a } => a
  }

fn main() {
  print(descreve(e: .none))
  print(descreve(e: .ativo))
  print(descreve(e: .some))
  print(responde(r: .ok))
  print(responde(r: .falha))
  print(responde(r: .err))
  print("${leituraDeProduto(p: Ponto(x: 7, y: 9))}")

  // O `Option` de verdade continua funcionando — a correção guardou por TIPO,
  // não removeu a família.
  let vazio: Int? = nil
  print(match vazio { .none => "nil mesmo", .some(v) => "${v}" })
  let cheio: Int? = 5
  print(match cheio { .none => "nil mesmo", .some(v) => "${v}" })
}
