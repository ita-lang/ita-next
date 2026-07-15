# Plan 002: Reescrita do compilador (ÉPICO) — plano de execução

> **Spec:** [`spec.md`](./spec.md) (épico) · **Status:** `ready` · **Marco:** `Reescrita`

## 1. Resumo técnico

> ⚠️ **REORIENTADO pelo [[ADR-0011]] (2026-07-10):** a abordagem virou **horizontal** — cada fase completa e
> documentada por vez, **sem** "tradutor em miniatura" (o `ita/` já provou o pipeline). A **§2 abaixo (Fase 0
> mini-tradutor) e a §3 (ordem 0→5) estão OBSOLETAS**; o faseamento vigente (**7 fases**) está na
> [`spec.md`](./spec.md) §B/§B.1. O que permanece válido aqui: mecânica do oracle (§4), plano de teste (§5),
> riscos (§6) **— exceto o risco "escopo do mini-tradutor incha", também OBSOLETO (não há mini-tradutor)** —,
> constitution check (§7). **Também OBSOLETO:** a referência da §8 ao [`design-notes.md`](./design-notes.md),
> que virou histórico (ver o banner de obsolescência no próprio arquivo). **A primeira sub-spec é a Fase 1
> (Léxico + scaffold).**

Plano de execução do épico. **Não implementa fases** — fixa a mecânica do oracle vs `ita/`, o gate de teste e
os riscos. Cada fase é um `/speckit` próprio (spec.md §B), feita **inteira** e validada pelo output da própria
fase (`itac tokenize`/`parse`/`check`) contra o oracle.

## 2. Fase 0 em profundidade (o primeiro código)

### 2a. Scaffold do `ita-next/` (estrutura §A da spec)

Criar a árvore de diretórios + arquivos-raiz de projeto:

```
ita-next/
├── compiler/
│   ├── lib/frontend/{lexer,parser,sdd,semantic}/   (semantic vazio até Fase 4)
│   ├── lib/codegen/  ·  lib/driver/
│   ├── bin/itac.dart          (entry point)
│   ├── test/                  (roda no CI desde já)
│   └── pubspec.yaml
├── conformance/valid/  ·  conformance/invalid/      (corpus golden — separado)
├── examples/                  (demos)
├── tools/  ·  dart-sdk.pin  ·  .gitignore  ·  Makefile
└── .github/workflows/ci.yml   (enxuto, espelha o do ita/)
```

### 2b. Toolchain (ADR-0003)

Trazer do `ita/` (reaproveitar, não reescrever — não é "a linguagem"): `dart-sdk.pin`, `tools/pin-dart.sh`
(adaptar paths relativos), e o vendor `third_party/dart/<tag>/pkg` (`kernel` + `_fe_analyzer_shared`).
Rodar `pin-dart.sh` para materializar `.dart-sdk/` (gitignored) e **assertar o formato de Kernel 130**.

### 2c. Tradutor em miniatura (Cap 2) — front-end mínimo end-to-end

**Subconjunto MÍNIMO** (só o suficiente para provar o pipeline): expressões aritméticas sobre `Int`/`Float`
(`+ - * /`, parênteses, precedência) + um `print(expr)`. Pipeline completo:
`fonte .tu → tokens → AST → tradução dirigida por sintaxe → Dart Kernel (.dill) → roda na VM`.

Arquivos concretos a criar:

| Arquivo | Papel | Cap |
| :-- | :-- | :-- |
| `compiler/lib/frontend/lexer/token.dart` | tipos de token (mínimo: `int`, `float`, `+ - * / ( )`, `ident`, `eof`) | 3 |
| `compiler/lib/frontend/lexer/lexer.dart` | scanner mínimo | 3 |
| `compiler/lib/frontend/parser/ast.dart` | nós mínimos (`NumLit`, `BinOp`, `Call`) | 5 |
| `compiler/lib/frontend/parser/parser.dart` | Pratt mínimo (precedência `+ -` < `* /`) | 4 |
| `compiler/lib/codegen/kernel_gen.dart` | AST → `k.Component` com um `main` que imprime | 8 |
| `compiler/lib/driver/driver.dart` | orquestra lexer→parser→codegen→`.dill`; `run`/`build` | 8 |
| `compiler/bin/itac.dart` | entry point da CLI | — |
| `compiler/pubspec.yaml` | deps: `package:kernel` (vendor) | — |
| `test/mini_translator_test.dart` | unit (lexer/parser) + 1 e2e (`2+3*4` → `14`) | — |
| `conformance/valid/expr_*.tu` (+ `.expected`) | poucos casos de expressão | — |
| `examples/hello.tu` | demo | — |

**Definition of Done da Fase 0:** `itac run examples/hello.tu` imprime o resultado; `dart test` verde no CI;
o `.dill` roda na VM; o mesmo caso rodado no `ita/` (oracle) dá a mesma saída.

## 3. Ordem das sub-specs (Fases 0→5) e dependências

| Fase | Sub-spec | Depende de | Expande |
| :-- | :-- | :-- | :-- |
| 0 | `scaffold-mini-translator` (Cap 2) | — | cria o esqueleto end-to-end |
| 1 | `lexer` (Cap 3) | 0 | o lexer mínimo → léxico completo (keywords, strings, interpolação, números, comentários) |
| 2 | `parser` (Cap 4) | 1 | o Pratt mínimo → gramática completa (reconciliar `GRAMMAR.md`), recuperação de erro |
| 3 | `sdd` (Cap 5) | 2 | tradução dirigida por sintaxe / atributos formalizados |
| 4 | `semantic` (Cap 6) | 3 | type-checker via side-table (ADR-0004), gate de tipos |
| 5 | `codegen` (Cap 8) | 4 | codegen completo (fatiado), alvos VM/AOT/JS, `--target=js` |

Cada fase segue `specify → clarify → plan → tasks → implement` e valida contra o oracle antes da próxima.

**Referências por fase (ADR-0009 — Dragon Book "o quê" + Crafting Interpreters "como"):**

| Fase | Artefato formal (Dragon) | Padrão de implementação (CI) |
| :-- | :-- | :-- |
| 1 léxico | defs regulares [3.3] | `scanning.md` (scanner à mão, maximal munch) |
| 2 sintaxe | BNF/EBNF [4.2] | `parsing-expressions.md` + `compiling-expressions.md` (Pratt) |
| 3 SDD/AST | SDD L-atribuída [5.x] | `representing-code.md` + `appendix-ii.md` (AST/Visitor) |
| 4 semântica | regras de tipo [6.5] | `resolving-and-binding.md` (resolução de escopo) |
| 5 codegen | emissão Kernel [8.2] | **princípios de codegen do ADR-0009** (privado/tipado → TFA; **sem LLVM**) |

## 4. Mecânica do oracle (§C da spec)

- **Gerar o esperado:** rodar cada caso `.tu` no **`ita/` via MCP `ita`** (`run`) → captura a saída canônica.
- **Conferir:** rodar o mesmo caso no `ita-next` → comparar byte-a-byte.
- **Reuso de corpus:** conforme cada fase habilita construções, copiar os casos `valid/invalid` e os
  `examples/*.expected` correspondentes do `ita/` para o `conformance/` do `ita-next`.
- **Paridade JS:** entra na Fase 5 (codegen) — `js_parity` do `ita-next` bate o placar do `ita/`.

## 5. Plano de teste (gate desde a Fase 0)

- **Unit:** `dart test` sobre `test/` — **rodando no CI desde a Fase 0** (aprendizado da auditoria: no `ita/`
  os 4 testes Dart eram órfãos).
- **CI (`ci.yml` enxuto):** `pin-dart` (assert Kernel 130) → build AOT do `itac` → unit → conformance →
  **benchmark de compile-time** (ADR-0006, falha em regressão).
- **Conformance:** `valid/` passa, `invalid/` falha — cresce a cada fase.

## 6. Riscos e mitigações

| Risco | Sev | Mitigação |
| :-- | :-- | :-- |
| Version-skew de Kernel (o `.dill` do `ita-next` não carrega na VM pinada) | média | ADR-0003 — mesmo `dart-sdk.pin` e vendor `pkg/kernel` do `ita/`; assert de formato 130 no `pin-dart.sh`. |
| Escopo do mini-tradutor incha (tentação de já colocar features) | **alta** | Regra dura: Fase 0 é **só** expr aritmética + `print`. Qualquer construção além disso é rejeitada no `/tasks` da Fase 0 e adiada à fase própria. |
| Git/versionamento do `ita-next` indefinido | baixa | **Decisão da Fase 0:** `git init` próprio ao fim do scaffold (sem herdar histórico do `ita/`), commit inicial quando o mini-tradutor rodar; repo na org e cutover são ADRs futuros. |

## 7. Constitution check (re-confirmação)

- **ADR-0001** — alvo é `k.Component` → `.dill` → Dart VM; **nenhum arquivo toca LLVM**. **ADR-0003** — pin
  reaproveitado. **ADR-0006** — benchmark AOT no CI desde já. **ADR-0007** — só Grupo A (front-end→codegen);
  **sem `runtime/`**. Princípios 1–11 preservados (a linguagem não muda). **Conflitos: nenhum.**

## 8. Artefatos auxiliares

- [`design-notes.md`](./design-notes.md) — subconjunto exato do mini-tradutor + estrutura de pacotes Dart do `ita-next`.
- [`conformance-cases.md`](./conformance-cases.md) — CA1–CA6 do épico → fontes-oracle no `ita/`.
- *(sem `grammar-delta.md` — a gramática é herdada do `GRAMMAR.md` do `ita/`, reconciliada na Fase 2.)*
