// SPEC: 013 — escopo default das citações `§N` nuas deste arquivo (Art. IV-6d).
// Passes de saneamento pós-construção — LT-F7a (spec 013 §7.1(B)).
//
// A API crua do `pkg/kernel` deixa campos no DEFAULT que o *builder* da CFE
// setaria. O loader binário da VM lê o default e ou EXECUTA ERRADO EM SILÊNCIO
// ou CRASHA; o `verifyComponent` NÃO pega esta classe (grep-confirmado no W1).
// Três invariantes, fisicamente em DOIS `RecursiveVisitor` (o `isFinal` mora
// dentro do OffsetNormalizer, como o oracle `ita/.../codegen.dart:79-146`):
//
//   1. localFunctionId ≥ 1, resetado por Member    → [LocalFunctionIdAssigner]
//   2. offsets secundários -1 → 0                   → [OffsetNormalizer]
//   3. isFinal ⟺ Field sem setter (BIDIRECIONAL)    → [OffsetNormalizer]
//
// ⚠️ Portamos a LIÇÃO, não o estilo — e CORRIGIMOS o oracle: o `isFinal` dele é
// UNIDIRECIONAL (só crava `final` quando NÃO há setter). Isso passa o RED
// vacuamente e torna todo campo de `class` imutável em silêncio, MATANDO o P2
// (`class` = referência mutável). A spec 013 §7.1(3) exige a EQUIVALÊNCIA nos
// dois sentidos: sem-setter ⟹ final, E com-setter ⟹ não-final.
//
// Rodar SEMPRE antes de `computeCanonicalNames()`/`BinaryPrinter`.

import 'package:kernel/ast.dart' as k;

/// Quantas vezes cada passe EFETIVAMENTE alterou alguma coisa.
///
/// ⚠️ **Um passe que nunca se aplica é indistinguível de um passe removido** —
/// e acumula tick verde para sempre. Medido em 2026-07-29 sobre os 35 fixtures
/// (5621 nós de Kernel visitados): o `LocalFunctionIdAssigner` rodava DUAS
/// passadas por fixture e alterava **zero** nós, porque `FunctionExpression` e
/// `FunctionDeclaration` não existem no emitter ainda. O mutante que o tirava
/// do caminho de produção SOBREVIVEU à suíte inteira.
///
/// O passe não está errado — ele é a defesa contra a lição mais cara do projeto
/// (2 closures no mesmo member colidindo no `ClosureFunctionsCache`). O que
/// estava errado era **não saber** que ele não roda. Agora o número é
/// reportado, e a lista de passes legitimamente vacuosos é uma catraca que só
/// pode encolher (ver `sanitize_test.dart`).
typedef RelatorioSaneamento = Map<String, int>;

/// Aplica os passes de saneamento sobre [component], in-place. Deve rodar ANTES
/// de `component.computeCanonicalNames()` e da serialização binária.
RelatorioSaneamento sanitizeComponent(k.Component component) {
  final offsets = OffsetNormalizer();
  final ids = LocalFunctionIdAssigner();
  component.accept(offsets);
  component.accept(ids);
  return {
    'OffsetNormalizer': offsets.aplicou,
    'LocalFunctionIdAssigner': ids.aplicou,
  };
}

/// Saneia SÓ as [libraries] dadas (cada subárvore), sem tocar o resto do
/// `Component`. Usado quando o platform é a BASE do Component (`finalizeProgram`):
/// as libs do platform já vêm corretas do `.dill` — zerar seus offsets ou
/// reescrever `isFinal` seria corromper libs válidas. Só o PROGRAMA é saneado.
///
/// Cada `library.accept(visitor)` recursa na subárvore da lib (via
/// `RecursiveVisitor`), idêntico ao que `sanitizeComponent` faz por Component.
RelatorioSaneamento sanitizeLibraries(Iterable<k.Library> libraries) {
  final offsets = OffsetNormalizer();
  final ids = LocalFunctionIdAssigner();
  for (final lib in libraries) {
    lib.accept(offsets);
    lib.accept(ids);
  }
  return {
    'OffsetNormalizer': offsets.aplicou,
    'LocalFunctionIdAssigner': ids.aplicou,
  };
}

/// Passes 2 e 3: normaliza offsets `-1 → 0` e crava `isFinal ⟺ sem setter`.
///
/// **Offset PRIMÁRIO — load-bearing.** O `fileOffset` vem da F3 e é preservado
/// quando real (`≥ 0`); só se normaliza sob o sentinela `TreeNode.noOffset`
/// (`== -1`, nó sintético sem span) — nunca cega um span real. Essa metade é
/// EXIGIDA: o `verifyComponent` reprova nó NOMEADO com `noOffset` (`checkLocation`,
/// `verifier.dart`).
///
/// **Offsets SECUNDÁRIOS — defensivo, premissa SOB REVISÃO.** ⚠️ O W3
/// (`dart-vm-expert`, 2026-07-25) mostrou que `-1` secundário é LEGAL no formato
/// (`ast_to_binary.dart` escreve `o+1`; round-trips como `-1`) e o verifier NÃO
/// os checa. A premissa "bus error" (spec 013 §7.1, herdada do oracle) NÃO está
/// sustentada na fonte VENDORADA — vive só no `kernel_loader.cc` da VM C++, fora
/// do vendor, e é CONTRADITA pelo oracle rodar `.dill` com `let`s (cujo
/// `fileEqualsOffset == -1` NÃO é tratado). Mantido como defensivo (espelha o
/// oracle) até o destino ser decidido: completar (falta `fileEqualsOffset`,
/// `ForInStatement.bodyOffset`) ou remover. ⚠️ Zerar FABRICA posição (byte 0 =
/// linha 1) num nó sintético — inócuo, mas some da precisão do stack trace.
class OffsetNormalizer extends k.RecursiveVisitor {
  static const int _noOffset = k.TreeNode.noOffset; // == -1

  /// Quantos nós este passe efetivamente corrigiu. Ver [RelatorioSaneamento].
  int aplicou = 0;

  @override
  void defaultNode(k.Node node) {
    if (node is k.TreeNode && node.fileOffset == _noOffset) {
      node.fileOffset = 0; // primário: só sob noOffset; ≥0 preservado
      aplicou++;
    }
    if (node is k.Class) {
      if (node.startFileOffset == _noOffset) node.startFileOffset = 0;
      if (node.fileEndOffset == _noOffset) node.fileEndOffset = 0;
    } else if (node is k.Constructor) {
      if (node.startFileOffset == _noOffset) node.startFileOffset = 0;
      if (node.fileEndOffset == _noOffset) node.fileEndOffset = 0;
    } else if (node is k.Procedure) {
      // ⚠️ Foot-gun da API (fonte 3.12.2): `Procedure` usa `fileStartOffset`;
      // `Class`/`Constructor` usam `startFileOffset` — assimetria real.
      if (node.fileStartOffset == _noOffset) node.fileStartOffset = 0;
      if (node.fileEndOffset == _noOffset) node.fileEndOffset = 0;
    } else if (node is k.Field) {
      if (node.fileEndOffset == _noOffset) node.fileEndOffset = 0;
      // isFinal ⟺ sem setter — EQUIVALÊNCIA (os dois sentidos):
      final hasSetter = node.setterReference != null;
      if (!hasSetter && !node.isFinal) {
        node.isFinal = true; // sem setter ⟹ final (senão Kernel malformado)
      } else if (hasSetter && node.isFinal) {
        node.isFinal = false; // com setter ⟹ mutável (P2 do `class` com `var`)
      }
    } else if (node is k.FunctionNode) {
      if (node.fileEndOffset == _noOffset) node.fileEndOffset = 0;
    } else if (node is k.Block) {
      if (node.fileEndOffset == _noOffset) node.fileEndOffset = 0;
    }
    super.defaultNode(node);
  }
}

/// Passe 1: atribui um `LocalFunctionId` distinto (`≥ 1`) a cada
/// `FunctionExpression`/`FunctionDeclaration`, sequencial POR MEMBER (reset em
/// `Procedure`/`Constructor`/`Field`) — replica o `LocalFunctionIdGenerator` do
/// CFE.
///
/// Sem isso toda closure fica com `LocalFunctionId.invalid` (`== 0`). No formato
/// Kernel 130 a VM keya o `ClosureFunctionsCache` por `local_function_id`
/// (`runtime/vm/closure_functions_cache.cc`): 2 closures no mesmo member com id
/// 0 colidem — a 2ª executa o corpo da 1ª. Quebra compose (`>>`)/curry.
class LocalFunctionIdAssigner extends k.RecursiveVisitor {
  int _next = 1;

  /// Quantos ids este passe cravou. Zero ⟹ o passe não exerceu função nenhuma
  /// sobre a entrada — ver [RelatorioSaneamento].
  int aplicou = 0;

  @override
  void visitProcedure(k.Procedure node) {
    _next = 1;
    super.visitProcedure(node);
  }

  @override
  void visitConstructor(k.Constructor node) {
    _next = 1;
    super.visitConstructor(node);
  }

  @override
  void visitField(k.Field node) {
    _next = 1;
    super.visitField(node);
  }

  @override
  void visitFunctionExpression(k.FunctionExpression node) {
    aplicou++;
    node.id = k.LocalFunctionId(_next++);
    super.visitFunctionExpression(node);
  }

  @override
  void visitFunctionDeclaration(k.FunctionDeclaration node) {
    aplicou++;
    node.id = k.LocalFunctionId(_next++);
    super.visitFunctionDeclaration(node);
  }
}
