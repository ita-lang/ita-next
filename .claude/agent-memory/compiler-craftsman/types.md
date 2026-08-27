---
name: types
description: Fase 5 (Semântica/Tipos, spec 009) do Itá — levantamento técnico: decomposição, modelo de tipos, bidirecional vs HM, exaustividade, nulidade/flow, side-tables, armadilhas do oracle
metadata:
  type: project
---

# Tipos — Itá Fase 5 (spec 009, levantamento W1 2026-07-14)

Fonte-mãe: **Dragon 6.3** (tipos e declarações) + **Dragon 6.5** (verificação de tipo) + **Dragon 5.1/5.2**
(atributos herdados/sintetizados = a teoria do bidirecional). **CI NÃO funda esta fase** — Lox é dinâmica
(CI `a-map-of-the-territory` §2.1.3: "The language we'll build is dynamically typed, so it will do its type
checking later, at runtime"). Única âncora CI: §2.1.3 (binding→typecheck é a ordem; 3 lugares p/ guardar
o resultado: atributo no nó / lookup table / nova IR) + 11.5 (reporta e continua).

## Decomposição recomendada (ordem forçada)
Linha de corte = a do próprio livro: **6.3 (declarações→tabela) ANTES de 6.5 (checagem de expressões)**.
Dragon 6.5.1: "A síntese de tipo … exige que os nomes sejam declarados antes de serem usados" + módulo é
letrec (spec 008 §0.5-3) ⟹ coletar assinaturas antes de corpos é OBRIGATÓRIO, não estilo.
- **A (Collect)** — 3 sub-passes: A1 cabeças de tipo; A2 expressões de tipo das assinaturas (campos/params/
  ret/bounds/variantes); A3 boa-formação. Two-pass interno pq tipos são MUTUAMENTE RECURSIVOS (Dragon 6.3.1
  box "Nomes de tipo e tipos recursivos" + 6.3.2 + nota 3: grafo com ciclos). Dragon 6.3.6 `record(t)`.
- **B (Check núcleo)** — Dragon 6.5.1 síntese; fecha `nil-under-non-optional`.
- **C (Bidirecional/contextual)** — closure `{$0*2}`, `.variant`, `[]`, `nil`, currying, `**`, `CopyWith`, `Member`.
- **D (Genéricos + unificação)** — Dragon 6.5.5 Alg 6.19 (union-find), só p/ type-args.
- **Exaustividade → F6** (não F5).
**Dragon 6.3.4/6.3.5 (largura/offset/leiaute/alinhamento) = GRUPO B** — a Dart VM faz layout. Metade de 6.3
NÃO se aplica ao Itá (ADR-0007). Ponto fácil de errar ao "implementar o cap 6.3 inteiro".

## Modelo de tipos
- `sealed class Type` espelhando **Dragon 6.3.1** (básico | nome | construtor aplicado | `→` função |
  `×` produto/tupla | variável de tipo).
- **`NamedType(decl: AstNode, args)` — por NÓ-DECL, não por string** (espelha a lição da F4: Kernel referencia
  por objeto). Struct/class/enum = 1 construtor + flag value/ref, NÃO 3 classes distintas.
- **Never/bottom**: LACUNA no Dragon (só tem `void`, 6.3.1 "ausência de um valor"). Fonte externa (Pierce TAPL
  15.4); Dart Kernel tem `NeverType` nativo. Necessário p/ `panic`/`return`/`break` como expressão.
- **`Error` ≠ `Unknown`**: `ErrorType` absorvente pós-erro-reportado (anti-cascata, CI 11.5); "ainda não sei" =
  `TypeVar` (6.5.4/6.5.5) que DEVE resolver no fim, senão `cannot-infer`. O oracle funde os dois → nunca erra.
- Subtipagem **existe** (ASDL: `ClassDecl.superclass` + traits) ⟹ **HM puro é incompatível** (unificação decide
  `=`, subtipagem exige `≤`). Variância: LACUNA no Dragon (6.5.4 é ∀ ML sem subtipagem) → invariante no v1.

## Inferência: BIDIRECIONAL (não HM) — recomendação cravada
Fundamentação nas fontes (não é preferência):
- **Dragon 6.5.1** já parte o mundo em **síntese** (dos filhos p/ cima) vs **inferência** (pelo uso) = os dois
  modos do bidirecional.
- **Dragon 5.1.1**: sintetizado (filhos→pai) vs herdado (pai/irmãos→filho). `synth`=sintetizado `E.type`;
  `check`=herdado `E.expected`. **5.1.2** avisa da circularidade; **5.2 (L-atribuída)** é a subclasse segura →
  é por isso que bidirecional roda em 1 walk sem ponto-fixo.
- **Dragon Exercício 6.5.2** descreve LITERALMENTE o bidirecional (sintetiza conjunto de tipos possíveis
  bottom-up, depois desce top-down p/ fixar o `unique`) — resolução de overload estilo Ada.
- HM rejeitado: 6.5.4 abre com "útil para uma linguagem como ML, que … **não exige que os nomes sejam
  declarados**" — não é o Itá (assinaturas anotadas). + subtipagem + overload (6.5.3: "Nem sempre é possível
  resolver a sobrecarga examinando apenas os argumentos … o contexto precisa fornecer informações") +
  diagnóstico (HM erra longe da causa) + P4 sem-mágica.
- Unificação (Alg 6.19) FICA, restrita a **type-args em aplicação** (matching 1-rodada), sem let-generalization.
- **O modo `check` É a implementação do nullity-invariant**: `nil` não SINTETIZA, só CHECA contra `T?`.
  `let x: String = nil` → erro; `let x = nil` → `cannot-infer` (nunca `dynamic`).

## Exaustividade → F6 (confirma ADR-0011)
Dragon **6.8 (switch) é só CODEGEN de n-way branch** — não trata exaustividade estrutural. CI não tem pattern
matching. **LACUNA declarada → Maranget 2007** (`U(P,q)` usefulness + `I(P,n)` contra-exemplo).
Argumento de fronteira: é análise de COBERTURA sobre matriz, não regra de tipo (não atribui tipo a nó); e
`U(P[1..i-1], p_i)` dá **braço redundante** de graça = irmão de unreachable-code (F6 declarado). 1 algoritmo,
2 diagnósticos, ambos F6. Contrato F5→F6: tipo do scrutinee + **Σ (conj. completo de construtores) + aridade**
por tipo + tipo de cada subpadrão + `.variant` já resolvido. Tipos infinitos (Int/String) → Σ nunca completo,
só `_` fecha. Guard nunca cobre (o oracle já acerta isso).

## Nulidade + flow — nulidade fecha INTEIRA na F5, sem flow-typing
Distinguir: (a) `nil` sob não-opcional = puro check (F5, sem flow). (b) narrowing **por BINDING**
(`guard let`/`if let`/`??`/`?.`/`?`) = regra de tipagem de PATTERN (`.some(x)` vs `Option<T>` liga `x:T`) —
**não precisa de fluxo**, a F3 já pagou o preço desaçucarando p/ `match`. (c) narrowing **sem binding**
(`if x != nil { x.foo }`) = flow-typing real → F6.
Fronteira do Dragon: 6.5 é SDD por NÓ (sem caminho); fluxo é Cap **9.2** = outra estrutura (grafo de fluxo,
pontos-de-programa, "não distinguimos entre os caminhos") — mesma família de use-before-assign = F6 (ADR-0011).
**Recomendo NÃO ter narrowing-sem-binding no v1**: `nullity-invariant.md` lista as portas de desembrulho
("`?`, `guard let`, `if let`, `??`") e **`!= nil` NÃO está na lista** — confirmação normativa. Aditivo depois.

## Side-tables: são QUATRO artefatos (não uma)
`Map.identity` (ADR-0004, AST imutável — a F3 roda 2× p/ testar idempotência):
1. `<Expr, Type>` — consumidor F7 (Kernel tipado = a alavanca ~7,7× do ADR-0007) e F6.
2. **Tabela de tipos** (decl → campos/variantes/assinaturas) — Dragon 6.3.6 `record(t)` ("t é um objeto de
   tabela de símbolos"). Consumidor: F6 (Σ da exaustividade) e F7 (copy-with enumera campos — hoje é
   `_typeFields` DENTRO do codegen do oracle = vazamento).
3. `<Member|EnumShorthand|Call, ResolvedMember>` — a **resolução type-directed** do contrato 008 §5.4. Fácil
   esquecer: a F5 não produz só tipos, produz RESOLUÇÃO (por objeto, p/ o Kernel — lição da F4).
4. `<TypeAnnotation, Type>` — p/ dump e assinaturas.

## Armadilhas do oracle (`ita/compiler/lib/semantic/` + codegen) — confrontado 2026-07-14
1. **`Unknown` curinga nos 2 sentidos** (`resolved_type.dart:46`) → checker NUNCA erra onde a inferência não
   alcança; codegen emite `dynamic` (comentário na linha ~20) → **perde a alavanca de perf que É o P0 do ADR-0007**.
2. **Identidade nominal por STRING** (`StructType('Node')`; `_userTypeSymbol` faz `scope.lookup(name)` p/
   reencontrar o símbolo) → colide entre módulos; a F4 já aprendeu a lição certa (aponte o nó).
3. **Genéricos AUSENTES**: Struct/Class/EnumType sem type-args; List/Map/Set hard-coded. `struct Box<T>` e
   `Result<T,E>` inexprimíveis — `genericParam` existe na AST desde a F2.
4. **`Option`/`Result` moram no CODEGEN** (`codegen.dart:683 _registerBuiltinTypes`), invisíveis à semântica,
   com type-args apagados p/ `const k.DynamicType()`. O checker compensa com **hack por NOME de método**
   (`type_checker.dart:166`: `callee.member == 'unwrapOr'` → tipo do default). Oposto de P4.
5. **`T?` (nullable) vs `Option<T>` (ADT boxed) coexistem sem unificação** — e a **F3 do ita-next JÁ CRAVOU**
   `a ?? b` → `match a { .some($x) => $x, .none => b }` (`desugar.dart:379`). ⟹ a spec 009 é OBRIGADA a cravar
   `T?` ≡ `Option<T>` (Σ={some,none}) ou separá-los explicitamente. Fato consumado da F3.
6. `_inferMatch` **sem join**: braços com tipos diferentes → `mixed` → `Unknown` (silêncio). "Tudo é expressão"
   exige política (erro vs LUB). LUB nominal com traits = inferno de diagnóstico (o `lub(Integer,String)` do Java).
7. **Coerção implícita Int→Float** (`isAssignableFrom` + `_numeric`) — Dragon 6.5.2 diz que é escolha da
   linguagem (Fig 6.25 widening); se ficar, a F5 tem de MATERIALIZAR a conversão (Dragon 6.5.2 `widen(a,t,w)`
   gera a instrução), senão VM×JS divergem. Tensão com P4 → ruling.
8. **`==` sempre Bool sem checar operandos** (`1 == "a"` compila); `!x` idem. Fura Dragon 6.5.1.
9. **Exaustividade flat**: só enum top-level, ignora subpadrões ⟹ `match r { .ok(.none) => …, .err(e) => … }`
   passa como exaustivo. Bug real.
10. **`_inferWhere` do oracle está DEFASADO**: registra bindings em ordem TEXTUAL; a F3 do ita-next cravou
    `where`=letrec com topo-sort. Pós-F3 a F5 nem VÊ `WhereExpr` (foi lowered). Não copiar o oracle cegamente.

## Retidos que a F5 tipa (pós-desugar)
`Try`, `CopyWith`, `Binary.pow`, `IfExpr` bool, `GuardLetStmt`, `ForStmt`, `MatchExpr`, `Closure`.
- **`Try` (`?`) é regra NÃO-LOCAL**: operando `Result<T,E>` → `T`, E EXIGE que o retorno da fn envolvente seja
  `Result<_,E>` compatível ⟹ o passe precisa carregar "tipo de retorno da fn corrente" no contexto.
- **`for` retido** (ruling do dono): o protocolo `Iterator.next() -> Option<T>` é DÉBITO de roadmap ⟹ hoje o
  tipo do target sai de tabela hard-coded (mágica). Lacuna real → ruling.
- `$0`-closure sem `$k`: F3 deixou params vazios (aridade contextual). Não exige criar binder na F5 (o corpo
  não usa `$k`) — funciona por causa da decisão da F3. Mudar isso quebraria a ordem 4→5.

## Review técnico da spec 009 (2026-07-15) — blockers achados
Spec `ita-lang/specs/009-semantic-types/spec.md` (draft). Fidelidade ao levantamento: alta (§4.4 4 razões,
§5.2, §5.4 Try não-local, §4.7, §7 = fiéis). Blockers técnicos:
1. **§4.3 falta a REGRA DE SUBSUNÇÃO** — `Γ⊢e⇒S  S≤T ⟹ Γ⊢e⇐T` é o **único** ponto onde `≤` é consultado
   (Pierce&Turner, Local Type Inference, TOPLAS 2000 §3). Sem ela o implementador espalha `isSubtype`.
2. **§4.2b falta `ErrorType`**: absorvente **bidirecional** (`E≤T` **e** `T≤E`) — é a diferença exata p/ `Never`
   (que é só `Never≤T`). O bug do oracle É "semântica de ErrorType aplicada ao Unknown".
3. **Invariante `Optional` normalizado**: sound como forma canônica SE (a) `subst` passar pelo smart constructor;
   (b) `redundant-optional` morar em **A2 sobre o `TypeNode`** (sintático), não no construtor — senão dispara em
   `compact<String?>`; (c) **Alg 6.19 é unificação SINTÁTICA sobre construtores LIVRES** — `?` idempotente NÃO é
   livre ⟹ `T?` vs `S?` tem 2 soluções, o algoritmo devolve `T:=S` e `T:=S?` é **inalcançável** (não há turbofish,
   GRAMMAR §6). Incompletude DELIBERADA a declarar. Precedente: Swift SE-0230 (`try?` gerava `T??`).
4. **§4.5 `max(t,t)=t` contradiz §4.3 `join(Never,T)=T`**. Formular: join ≠ LUB; é igualdade + bottom
   (reticulado PLANO com `Never` no fundo) — `max` do 6.5.2 sobre hierarquia achatada.
5. **§4.3 justifica `join(Never,T)=T` pelo Kernel** — inverte a doutrina do próprio §8.3 ("o princípio é a razão,
   o dado da VM é o reforço"). Razão real: P3 + bottom (TAPL 15.4).
6. **"1 walk" (§5.2) depende de NÃO haver overload.** Ex 6.5.2 é explicitamente DOIS percursos (set bottom-up →
   unique top-down); só colapsa em 1 walk se cada nome tem 1 tipo (= ruling F4 #1, namespace unificado).
   `OperatorDecl` pode reintroduzir overload → responder.
7. **`for` ausente da spec** (minha armadilha #12): a F5 VÊ `ForStmt` retido e tem de tipar o `target`; sem trait
   `Iterator` = tabela hard-coded = a mágica que §4.5/§8.3 recusam. Ruling.
8. **CA27 está ERRADO**: `let xs: List<Animal> = [Cachorro()]` PASSA (check-mode empurra `Animal` p/ o elemento +
   subsunção). Invariância só morde com VARIÁVEL: `let ds: List<Cachorro> = …; let as: List<Animal> = ds`.
9. §4.8 falta: regra/erro de `==`/comparação (armadilha #8 entrou só p/ `&&`/`||`/`!` via `not-bool`);
   `try-on-non-result` (operando não-`Result`) ≠ `try-outside-result-fn` (fn envolvente).
10. §7 faltam 4 invariantes: **totalidade** da `<Expr,Type>` (o `?? UnknownType` do oracle é o buraco);
    totalidade da tabela de resolução (senão F7 cai em `DynamicInvocation`, §8.2); `Optional` normalizado;
    nenhum `MutType` sobrevive.
- **Escopo A+B:** CA15/CA16/CA22/CA23/CA24/CA27 NÃO são implementáveis em A+B. **Recomendo D ANTES de C**:
  A2 já precisa de generic params (stdlib usa `Option<T>` 33×, `List<T>` em tudo) ⟹ o que é deferível é só a
  **unificação de type-args em aplicação** (6.5.5); e C-flagship (closure CA15) DEPENDE de D, não o contrário.
- `Option`/`Result` devem MIGRAR do codegen (`codegen.dart:684`) p/ a tabela de tipos da F5 — senão o vazamento
  (armadilha #4) sobrevive à reescrita. Não está no contrato §7.
- `RecordType(positional,named)` (§4.1) diverge do ASDL (`TupleType(type* elements)`); `named` não tem sintaxe de
  superfície. Alinhar ou justificar.

## Rulings a escalar
- **ita-visionary:** `T?` ≡ `Option<T>`?; coerção Int→Float?; join de match (erro vs LUB)?; `Result`/`Option`
  prelúdio-em-`.tu` vs built-in?; narrowing `!= nil` existe?; variância; `mut` = tipo ou qualificador do binding?;
  struct recursivo por valor; existe top (`Any`)?
- **dono:** exaustividade F5 vs F6 (recomendo F6); fatiamento A→B→C→D; `let x: String` sem init (definite
  assignment = F6, `nullity-invariant.md` §Aberto).
- **dart-vm-expert:** Type→Kernel DartType; NeverType; nullability nativa vs Option boxed; generics reified.
