# ADR-0010: Formatos dos artefatos formais por fase

- **Status:** Accepted
- **Data:** 2026-07-10
- **Relacionados:** [[ADR-0007]] (artefatos por fase do Dragon Book), [[ADR-0009]] (referências), [[ADR-0008]] (épico 002). Rege-se pelos **Princípios 8/9/11** (zero node_modules, zero Python, zero codegen em build-time).

## Contexto

Cada fase da reescrita produz um **artefato formal** (defs regulares, gramática, AST, regras de tipo…). Para
não ficarem em prosa solta, cada um deve ter um **formato padronizado, versionável e citável**. A busca por
formatos da indústria (2024–2026) achou padrões consolidados por fase — mas vários **geram código** e/ou
**arrastam Python/Node**, o que colide com os princípios do Itá.

## Decisão

Adotar, por fase, o formato de **maior citabilidade/portabilidade que respeite os princípios** — priorizando
formatos **só-spec** (não geram nada no build):

| Fase | Formato canônico | Arquivo | Classe |
| :-- | :-- | :-- | :-- |
| **Léxico** (Fase 1) | **W3C EBNF** (seção "Lexical grammar") | `docs/spec/*.ebnf` ou seção do `GRAMMAR` | só-spec |
| **Sintaxe** (Fase 2) | **W3C EBNF** (fonte-da-verdade) **+ tree-sitter** (gramática executável, já em uso) · **AST em ASDL** — a AST pertence à fase de Sintaxe, **não** a uma fase própria | `grammar.ebnf` + `grammar.js` + `ast.asdl` | só-spec + gerador-do-dev (ver nuance ASDL) |
| **Desugaring** (Fase 3) | tabela de reescrita (açúcar → núcleo canônico) | `docs/spec/desugar.md` | só-spec |
| **Binding** (Fase 4) | doc de regras de escopo / resolução de nomes | `docs/spec/binding.md` | só-spec |
| **Semântica / tipos** (Fase 5) | **Ott** (`.ott` → LaTeX; opcional Coq/Isabelle) | `types.ott` | só-spec (doc-tooling) |
| **Análises** (Fase 6) | **Ott**/doc formal (regras de fluxo + exaustividade de `match`) | `flow.ott` ou doc | só-spec |
| **Codegen** (Fase 7) | `.dill` (saída) + **dump textual de Kernel** como golden | `*.dill` + `*.kernel.txt` | toolchain Dart (o dump usa a ferramenta Dart) |
| **Conformance** | **corpus tree-sitter** (parse) + **golden `.expected`** (saída) | `test/corpus/*.txt` + `*.expected` | só-dados |

**Doc visual:** gerar **railroad diagrams** a partir do `.ebnf` para o site/docs (só-spec).

## Guard — Princípios 8/9/11

- **Só-spec (a) é a regra.** W3C EBNF, ASDL-como-spec, Ott, dumps textuais e corpora são documentos/dados —
  não acoplam gerador ao build do `itac`.
- **Único gerador tolerado (b):** `tree-sitter generate` — comando **explícito do dev**, saída **commitada**,
  fora do build; já é assim no `tree-sitter-ita`.
- **Nuance ASDL × Princípio 9 (zero Python):** o gerador de referência do ASDL é Python (`asdl_c.py` do
  CPython). Portanto, no Itá o `.asdl` é usado **como spec** da AST escrita à mão; se um dia gerarmos as
  classes Dart a partir dele, o **gerador deve ser escrito em Dart** (nunca depender do Python), e rodado por
  script do dev com saída commitada — nunca no build.
- **Vetados como fonte-da-verdade (c):** Flex/Bison/ANTLR/Pest/Lark (parser gerado no build), Silver/JastAdd
  (geram o compilador inteiro), Protobuf/protoc. ISO/IEC 14977 EBNF também é evitado (dialeto pouco usado;
  preferir W3C EBNF).

## Consequências

- O `ita-next` entrega, por fase, o artefato no formato acima — versionável e revisável em diff.
- O `GRAMMAR.md` atual (EBNF em prosa) evolui para um **`grammar.ebnf`** canônico (W3C EBNF), do qual se
  geram railroad diagrams; a `tree-sitter-ita` permanece como gramática executável reconciliada.
- Novos artefatos entram no repo: `ast.asdl` (Fase 2), `types.ott` (Fase 5). Cada sub-spec de fase define o
  seu.
- Nenhum formato adiciona dependência de build (Princípio 11) nem de Python/Node ao **compilador** (8/9); as
  ferramentas de doc (Ott, railroad) são do fluxo do dev, não do `itac`.
