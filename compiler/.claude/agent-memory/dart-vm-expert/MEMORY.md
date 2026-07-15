# Memória — dart-vm-expert (Itá)

Índice. Detalhe nos arquivos-tema. Toda afirmação da VM/Kernel deve citar fonte (vendor local ou doc).

## Contrato F5 → F7
- [Contrato F5→F7 medido contra o Kernel](f5-export-contract.md) — ⚠️ regra do prefixo ∀ por SÍTIO; static de tipo genérico NÃO enxerga o `T` da classe (quebra em silêncio); typeArgs não é Grupo B.

## Kernel / nós
- [Nós do Kernel — fatos confirmados](kernel-nodes.md) — Constructor, Class, Extension, FieldInitializer, AsyncMarker; campos exigidos + paths do vendor.
- [Dispatch, built-ins, extension, for-in](builtin-dispatch-forin.md) — ⚠️ ForInStatement é PROIBIDO (CFE-interno); interfaceTarget exige platform dill; extension→static; GDT não é "de interface".
- [struct / init memberwise / copy-with](struct-copywith-init.md) — ⚠️ Arguments TEM named (match por nome, sem label→posição); FunctionType.namedParameters ordenado ≠ fields ordem-fonte; Field tem 3 References; Field.immutable é verificado.

## Método (aprendido na 011)
- Comportamento da VM é **versionado**: conferir sempre na TAG vendorizada (`raw.githubusercontent.com/dart-lang/sdk/3.12.2/...`), não em `main` nem em commit avulso — o `ForInStatement` mudou de handled p/ unhandled entre commits.

## Vendor / grounding
- Vendor autoritativo: `ita/third_party/dart/3.12.2/pkg/kernel/lib/src/ast/` (tag SDK 3.12.2; "v130" do ADR-0003 = versão do formato binário). Ler daqui é Classe A.

## Specs avaliadas
- [Spec 005 forward-compat](spec-005-forward-compat.md) — nós novos (InitDecl, traits, guard-let condition, async member) todos ✅; débitos de codegen p/ Fase 7.
- [Spec 006 forward-compat](spec-006-forward-compat.md) — WhereExpr→Let/BlockExpression, enums de operador→calls resolvidas, compound-assign→get+op+set; todos ✅, sem edição.
