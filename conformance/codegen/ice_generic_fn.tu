// FRONTEIRA HONESTA (spec 013 §7.8) — o bloco ∀, 1 de 6.
//
// Os seis `*-generic` do `emit.dart` eram, até 2026-07-29, o maior bloco de
// fronteira SEM catraca do emitter: a F5 tipa genéricos, o programa é legal, e a
// emissão para com ICE — sem que nada ficasse vermelho no dia em que ∀ nascer.
// R7: `_ice` novo ⟹ fixture no mesmo commit. Estes seis pagam a dívida antiga.
//
// Cada um isola UMA construção, porque cada uma é uma fatia distinta e a
// primeira a ser emitida vence: um fixture com `struct Caixa<T>` e uma `fn`
// genérica juntos só provaria o ICE da declaração que vem antes.
//
// A F5 resolve `identidade(x: 7)` e prova `T = Int`; a emissão não baixa
// type-params (`Procedure.function.typeParameters` fica por escrever), então
// para aqui em vez de emitir um `Procedure` sem os parâmetros que o corpo usa.
//
// EXPECT-ICE: ice-codegen-fn-generic

fn identidade<T>(x: T) -> T => x

fn main() {
  print("${identidade(x: 7)}")
}
