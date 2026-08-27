---
name: f6-flow-check
description: F6 (spec 014) — rulings conferidos + W3 do flow-walk (1º lote): APROVA C/ EMENDAS; buraco Str-parts da F5 (nº1 não-total ⟹ crash I2), anticascata por sub-região virou norma, ledger dos corpos não-walkados
metadata:
  type: project
---

# F6 flow-check — conferência dos 5 rulings (2026-07-16)

Revisão pré-implementação da spec 014. Parecer anterior de F6 NÃO existia em memória (a spec §0 cita
"parecer compiler-craftsman 2026-07-16" feito fora desta memória). Fonte grepada: o Dragon INTEGRAL em
PT (`references/840054556-...txt` — linhas citadas abaixo são desse arquivo).

## Veredictos (todos com fonte verificada no txt)

1. **R1 código-morto=ERRO — CONFIRMA.** Dragon só trata dead code como OTIMIZAÇÃO sobre IR:
   8.5.3 (DCE no DAG, linha 27039), 9.1.6 (linha 29467; em 29469-71 o livro DIZ "o programador
   provavelmente não introduz código morto intencionalmente — ele aparece por transformações
   anteriores"), nota 9 do 6.6 (linha 20310-11: morto GERADO pelo compilador, eliminado depois).
   Objeto diferente do diagnóstico de fonte ⟹ zero conflito. CI `resolving-and-binding.md:1762`
   endossa o MECANISMO (passe estático) mas fala warning. Severidade=erro é norma: JLS §14.21 (Java
   erra unreachable statement) e — melhor assento p/ braço dominado — **JLS §14.11.1 (dominância de
   case label em pattern-switch = compile-time error)**, mais forte que Maranget (cujo título é
   "WARNINGS for pattern matching"). O carve-out `if` sem const-eval preserva o canal `if debug {}`
   (Ex 9.4 do Dragon, linha 29473 — o único morto "intencional" que o livro nomeia exige const-prop,
   que a F6 recusa por design).

2. **R2 `Assign:Void` — CONFIRMA (e simplifica o livro).** No 6.4 a atribuição é `S → id = E ;` —
   STATEMENT nas Figs 6.19/6.20/6.22, nunca produção de E. A herança C só aparece na **nota 9 do 6.6
   (linha 20310)** como COMPLICAÇÃO: "Em C e Java, as expressões podem conter atribuições dentro
   delas, de modo que precisa ser gerado código para E1/E2 mesmo que B.true/B.false sejam fall".
   `Assign:Void` apaga essa obrigação do jumping code da F7. Nenhum esquema fica inaplicável.
   Bivalência JLS §16.1 morre mesmo: sem assign-em-expressão e sem DA vazando de closure (CA7),
   DA-após-expr = DA-antes-expr sempre.

3. **R3 guard-must-exit — CONFIRMA lacuna.** "guard" não existe no Dragon (grep: só o verbo
   "guardar") nem no CI. Dragon 6.6 é esquema de TRADUÇÃO (jumping code) que assume statements
   bem-formados — predicado estático a montante não o toca; else-que-não-completa até simplifica o
   join da tradução. Fundação certa: JLS §14.21 (completesNormally por indução estrutural) + Swift
   TSPL "Early Exit" (norma, assinada).

4. **R4 modelo D-V1 — CONFIRMA, com 3 armadilhas NOMEADAS pelo livro (8.5.4, p.340-41):**
   - **Nota 2 (linha 27089):** "Expressões aritméticas deverão ser avaliadas da MESMA MANEIRA em
     tempo de compilação e execução" + truque de K. Thompson (rodar o código objeto no ato).
     **Bônus Itá: compilador em Dart rodando na VM que ele alveja ⟹ host≡target por construção** —
     usar `int`/`double` do Dart no avaliador É o truque de Thompson de graça (Int64 wrapping
     two's-complement nativo, Float IEEE 754).
   - **Nota 3 (linha 27092):** comparação via subtração introduz overflow — comparar direto.
   - **Corpo (linha 27097-103):** aritmética de máquina não obedece identidades algébricas
     (parênteses do Fortran) — o avaliador avalia a árvore canônica LITERALMENTE, zero rewriting.
   - **Divisão por zero: LACUNA no Dragon** (grep vazio). Decide-se pela nota 2: runtime panicaria
     deterministicamente antes de `main` ⟹ erro de compile. Precedentes: Rust E0080, Go spec
     (divisor const ≠ 0), C++ constexpr. CI dá a FORMA da entrega: valor computado → constant table
     → load (`compiling-expressions.md:947-1010`, OP_CONSTANT).
   - 9.4 (lattice de const-prop) NÃO importa: const-expr V1 não tem fluxo ⟹ recursão direta + Tarjan.

5. **R5 where 1+3 — CONFIRMA, citação exata.** 5.2.5 (linha 15361) dá as DUAS disciplinas: (a) efeitos
   que não restringem a ordem ("qualquer ordenação topológica produz tradução correta", 15372-74) e
   (b) restringir ordens permitidas = arestas implícitas (15375-76). O ruling mapeia 1:1 — (1) banir
   os 5 primitivos ≈ gramática de atributo (15027); (3) ordem publicada Kahn+textual ≈ arestas
   implícitas de (b). Ex 5.10 (linha 15390): inserções na tabela comutam ⟹ qualquer ordem. Resíduo
   interprocedural = o "correta depende da aplicação" de (a), fechado pela ordem publicada.

## W3 do flow-walk 1º lote (2026-07-17) — APROVA COM EMENDAS

Implementação (`flow.dart` + `itac flow` + 43 testes) fiel ao blueprint em TODAS as mecânicas
(equações §2.1, ∩ c/ ⊤-por-omissão via `merged==null`, closure 4-passos, `_LoopCtx`, nº8,
missing-return). Assentos NOVOS deste W3 (parecer em scratchpad `parecer_w3_craftsman.md`):

1. **Buraco Str-parts da F5 (BLOQUEANTE, raiz FORA da F6):** `check.dart` sintetiza
   `Str ⟹ StringType` SEM descer nas partes de interpolação ⟹ a nº1 VIOLA a própria totalidade
   (009 §7-4) — `"${1 + true}"` passa o `itac check` verde, e a F6 estoura `StateError` (I2) em
   `"${if …}"`/`"${match …}"`/closure-BlockBody dentro de `${…}` (parser sub-parseia expr COMPLETA;
   F4 desce nas partes, F5 não). Fix = dedo na F5 (`_synth` das partes). Lição-régua: "não consulto
   tipo de X" não basta — o walk consulta tipos DENTRO de X; totalidade se afere por SUBÁRVORE.
2. **Anticascata por SUB-REGIÃO = norma da F6** (refino do implementador, aprovado): flag de
   `unreachable-code` fecha ao sair de braço/loop/guard/closure; morte só atravessa bloco NU.
   `if {return;x} else {return;y}` ⟹ 2 erros; `if {return;junk}` sem else + código vivo fora ⟹
   sem buraco (carve-out do if reseta na costura). Substitui a subespecificação do blueprint §6.
3. **nº8 é PARCIAL por design e precisa de ledger em spec:** InitDecl/OperatorDecl/payload-defaults
   de enum não são walkados (F5 não os tipa — walkar = I2 em programa verde; LEGÍTIMO), globais
   pulados (mas a F5 TIPA initializer global ⟹ walkar é seguro e fecharia o buraco transitório da
   closure-em-global sem missing-return até o lote const-eval). A F7 não pode assumir totalidade.
4. **Default de param de CLOSURE**: parseável (`_param` compartilhado), F5 o IGNORA em silêncio
   (`_closureSynth` não toca `defaultValue`), F6 não desce — semântica indefinida ponta a ponta;
   pergunta de dono (banir vs cobrir).
5. Cruzamento **guard-else×break×while-true** correto por construção (`_guardElse` não toca
   `_loop`) mas sem teste — idioma real de saída de loop; teste pendente.

## Contrato do avaliador const-expr (D-V1) — entregue no parecer
Domínio `ConstValue` fechado (Int64/Float64/Bool/String/Nil/Struct/Enum — SEM closure, SEM ref a AST);
erros `global-init-not-const`/`global-init-cycle`/`const-eval-panic`; mora em `frontend/analysis/`
alimentado pela ordem do SCC; entrega side-table `Map<Decl,ConstValue>` serializável a `Constant` do
Kernel (mapeamento exato de nó = decisão da 013/F7). **Gaps flagados ao dono:** (i) list/record literal
no initializer — a spec só nomeia struct/enum; (ii) semântica de overflow Int é dependência da
identidade da linguagem (se um dia overflow=panic, avaliador acompanha — nota 2 do 8.5.4 manda).
