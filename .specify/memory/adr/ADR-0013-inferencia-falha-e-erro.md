# ADR-0013 — Falha de inferência é ERRO; `dynamic` não é tipo de superfície

> **Status:** Accepted
> **Data:** 2026-07-15
> **Supersedes:** **ADR-0004 — PARCIAL**: revoga apenas a *regra de ouro* `UnknownType → dynamic`. O resto do ADR-0004 (side-table `Map.identity`, rota rustc, AST imutável, pacote `semantic/`, IR adiada) **permanece em vigor e é reafirmado**. · **Relacionados:** ADR-0007 (Kernel tipado é o P0), ADR-0011 (faseamento), ADR-0001 (Dart VM), spec `009-semantic-types` (Fase 5), `constitution.md` Art. I (P4)

## Contexto

O ADR-0004 (2026-07-06) introduziu a fase semântica **no oracle `ita/`**, saindo de um estado em que ela **não existia** (`codegen.dart` gerava Kernel direto da AST; *"fortemente tipada era decorativa"*). Para conseguir o gate **sem falsos-positivos** num compilador que ainda não sabia inferir muita coisa, ele cravou a **regra de ouro**:

> *"HM modesto; regra de ouro **`UnknownType` → `dynamic`** onde a inferência não é confiável."*

Foi a decisão certa **para aquele momento** — bootstrap, prioridade em não rejeitar programa válido. Três fatos, porém, mostram que ela não deve ser transportada para o `ita-next`:

**1. O próprio ADR-0004 chama os buracos de débito, não de estado desejado.** Última linha: *"**Débitos abertos:** type-args de generics não instanciados (`_inferCall`), pattern literal casando braço errado."* A regra de ouro é o **curativo** do débito — não o objetivo.

**2. Ela colide com o ADR-0007, que é quem justifica a fase existir.** O ADR-0007 é explícito: *"gerar **Kernel tipado** é a **única** alavanca de performance (recupera ~7,7×), além de consertar os bugs 'compila mas roda errado'"* — e os ~7,7× são *"o **custo do dinamismo** no AOT"*. **Emitir `dynamic` é, literalmente, não fazer o trabalho que justifica a fase.** Medição do próprio projeto (ROADMAP, PR #6): tipar só os locais deu **~16× no AOT** (2,14s→0,13s). Cada `dynamic` é perda medida.

**3. O resultado empírico no oracle.** Mapeamento de 2026-07-14: a semântica do `ita/` tem **1355 linhas e checa 4 regras**. A causa é estrutural — o `UnknownType` é **curinga nos dois sentidos** (`resolved_type.dart:46`), então o checker **nunca erra** onde a inferência não alcança. Não checa aridade, tipo de argumento, `return` vs `-> T`, membro inexistente, nem condição de `if`. É a família "compila mas roda errado" **de volta**, pela porta que a regra de ouro abriu.

**4. Dado do backend (`dart-vm-expert`, vendor `pkg/kernel` 3.12.2) — `dynamic` é VIRAL.** Sem `interfaceTarget`, o Kernel só admite `DynamicInvocation` → a TFA não devirtualiza → o inline-cache escala (*unlinked → monomorphic → single-target → linear → megamorphic*) → sem inlining → sem `AllocationSinking`. E o golpe: `unboxing_info.dart` — *"dynamic calls always use boxed values"* ⟹ **um único call-site dinâmico contamina a convenção de chamada por selector**, atingindo o mesmo nome em outras classes. O dano não fica no nó.

> **Nota de método (doutrina do `ita-visionary`, 2026-07-15):** o item 4 **reforça**; ele **não fundamenta**. A razão de recusar `dynamic` na superfície é **P4** — "sem mágica; nunca esconde o que acontece". Se um backend futuro baratear o dinamismo, o item 4 evapora e **P4 não evapora junto**. *O princípio não pode ficar pendurado em nada do backend — nem em custo, nem em fato.*

## Decisão

**No `ita-next`, falha de inferência é ERRO. `dynamic` não é tipo de superfície da linguagem.**

1. **`cannot-infer`** — onde falta informação para tipar, a Fase 5 **erra**, com span e hint. Nunca infere `dynamic`, nunca infere `Nil`.
2. **`dynamic` é inalcançável da sintaxe** — não há keyword `dynamic`, não há `as` (ADR-0012 #6), e nenhuma anotação do usuário produz `dynamic`. Ele existe **apenas** como fallback interno do codegen (F7), onde o Kernel exige um tipo que não sabemos nomear — e mesmo lá, **`Object?` > `dynamic`** (dá `InstanceAccessKind.Object`, não `DynamicInvocation`).
3. **`Object?` NÃO é fallback de inferência.** É **topo**, não curinga: atribui-se *para* ele, nunca *dele* sem prova (`match`/check). Dois lugares legítimos, só: (a) fato de emissão da F7; (b) tipo que o **usuário escreve** na borda `dart:`, decodificando para `Result` — dynamic externo nunca flui para dentro.
4. **`ErrorType` ≠ `TypeVar`** — a distinção que o oracle não fez, e que é a causa-raiz do item 3 do Contexto:
   - **`TypeVar`** = "ainda não sei" (Dragon 6.5.4). **Deve** estar resolvido no fim; se sobrou ⟹ `cannot-infer`.
   - **`ErrorType`** = absorvente **pós-erro-já-reportado** (anti-cascata; a AST é total, com nós `Error*`). Curinga bidirecional — **exatamente a propriedade que o `UnknownType` tinha**, e é **por isso** que ele só pode nascer **depois** de um erro reportado.
   > O bug do oracle **não é ter um curinga**: é dar semântica de `ErrorType` a um "não sei".
5. **Totalidade** — `typeOf(node)` **falha** se não houver entrada; não devolve default. (O oracle faz `_types[node] ?? const UnknownType()` — `type_table.dart:46` — um default que **esconde buraco**: se a F7 pede tipo e recebe default silencioso, o `dynamic` volta pela porta dos fundos.)

**A motivação declarada do ADR-0004 é preservada.** "Zero falsos-positivos" continua valendo: `cannot-infer` **não é** falso-positivo — é o contrato *"dentro do corpo infere, na borda anota"* (spec 009 §0.5-1) pedindo a anotação que falta. O que muda é a resposta ao **"não sei"**: era `dynamic` (falso-negativo silencioso), passa a ser **erro**.

## Consequências

- **O `ita-next` diverge do oracle nesta fase — deliberadamente.** O `ita/` permanece como oracle de **paridade de comportamento válido** (F1–F4), mas **não** é referência para a F5: reproduzi-lo seria reproduzir as 4-regras-em-1355-linhas. É a primeira fase em que o oracle não serve de gabarito (ADR-0011 manda validar *"tendo o `ita/` como oracle"* — aqui, essa validação não se aplica).
- **Programas que hoje passam no `itac check` do oracle podem falhar no `ita-next`.** É o objetivo: `let x: Int = "s"` passava (`bin/itac.dart` pré-M1); aridade errada passa hoje.
- **Kernel tipado por construção** ⟹ a alavanca do ADR-0007 (~7,7×) fica disponível de verdade, e não por acaso.
- **Custo:** a inferência precisa ser **completa o bastante** para não errar onde o usuário foi razoável. Daí a fatia **D** (unificação de type-args) entrar na spec 009 e não ser adiada — sem ela, `Result<T,E>`/`List<T>` não tipam e o `cannot-infer` dispararia em código idiomático. **Inferência incompleta + erro = linguagem inutilizável**; é o par que torna esta decisão viável.
- **Débito herdado a fechar (vazamento do oracle):** `Option`/`Result` moram no `codegen.dart:683` (`_registerBuiltinTypes`), invisíveis à semântica e com type-args apagados para `const DynamicType()`. Devem **migrar para a tabela de tipos da F5** (spec 009 §7-3) — senão o vazamento sobrevive à reescrita e a F7 continua dona do conhecimento de tipo.
- **O ADR-0004 continua válido no que não foi revogado** — e este ADR **reafirma** a side-table `Map.identity` nó→tipo com AST imutável, que a F4 já implementou e a F5 estende (4 tabelas: tipo por nó, tabela de tipos, resolução type-directed, tipo por anotação).
