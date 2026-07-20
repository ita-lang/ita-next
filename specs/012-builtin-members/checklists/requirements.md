# Checklist de Qualidade da Spec: Membros de built-in — o CHÃO (`.length`, `[]`, `+`)

**Propósito**: validar completude e qualidade da spec (RFC de linguagem) antes de planejar
**Criado**: 2026-07-20
**Spec**: [spec.md](../spec.md)

## Qualidade do conteúdo

- [x] Segue o `spec-template.md` (RFC técnico multi-fase); seções de fase não tocadas foram REMOVIDAS (§2 léxico, §3 sintaxe, §6 fluxo — sem "N/A")
- [x] §1 tem motivação + exemplo `.tu` **antes → depois** e não-objetivos
- [x] Prosa em PT-BR; identificadores em `backticks`; erros internos em EN kebab-case
- [x] Cada fase preenchida cita o capítulo do Dragon Book (§4 `[6.3/6.5]`, §5 `[5.1/5.4]`, §7 `[6.2/8.1]`, §8 `[7.1]`)

## Completude da RFC

- [x] Nenhum marcador [NEEDS CLARIFICATION] remanescente — o único (out-of-bounds de `[]`) foi **FECHADO pelo dono em 2026-07-20** (panic para `List`, `V?` para `Map`; §4.3/§0.6).
- [x] §4 (Especificação formal) presente — a mudança toca tipo (regras de `.length`/`[]`/`+`)
- [x] Comportamento por alvo (VM/AOT/JS) declarado em §7.3; paridade VM×JS marcada (**MATCH**)
- [x] Regras/tipos declarados de forma não-ambígua (premissa/conclusão no §4.3)
- [x] §9 checklist de completude (Apêndice A) coerente com as fases tocadas
- [x] Escopo delimitado; compatibilidade/migração (§10) e alternativas descartadas registradas
- [x] Premissas de runtime (§8) declaram apenas dependências da Dart VM (`dart:core::{List,String,Map}`), sem reespecificá-la

## Prontidão

- [x] Cada CA de §11 é **testável** e vira caso `.tu` no corpus (saída/erro esperado)
- [x] CAs validáveis ao vivo via MCP `ita` (VM; paridade JS quando aplicável)
- [x] Constitution check (§0.5) sem conflito com princípio permanente — **liberado-com-ressalva** (W0 `ita-visionary`, 2026-07-20; emendas incorporadas)
- [x] Definition of Done coerente com CI (conformance + unit + benchmark de compile-time)

## Notas

- **✅ Fechado:** o out-of-bounds de `[]` (§4.3) — resolvido pelo dono em 2026-07-20 (**panic** para `List`, **`V?`** para `Map`). Zero `[NEEDS CLARIFICATION]` restante.
- W0 rendeu 3 emendas (todas aplicadas): a justificativa de face 1 para `[]`/`+` (operadores, cura via `OperatorDecl` diferida), a unificação do clarification List+Map, e a correção de citação/assumption em §10.
- **Status `clarified`.** O `/speckit-clarify` não é mais necessário (o único ruling fechou) — pronta para **`/speckit-plan`**.
