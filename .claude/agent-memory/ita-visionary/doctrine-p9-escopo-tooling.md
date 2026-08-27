---
name: doctrine-p9-escopo-tooling
description: Doutrina — P9 (zero Python) governa a cadeia de build do COMPILADOR, inclusive tooling de dev/CI; o teste é "runtime estrangeiro vs. base POSIX".
metadata:
  type: feedback
---

# Doutrina: o escopo do P9 é a cadeia de build do compilador, não só o runtime do usuário

**Regra:** P9 ("Zero Python como dependência de **build** ou runtime", Const. Art. I-9) alcança tudo que
um contribuidor precisa executar para sair de um checkout limpo até um compilador que compila —
**inclusive scripts de tooling e passos de CI**. Não é limitado ao programa `.tu` do usuário.

**Why:** a própria spec 013 já lê P9 assim, duas vezes, e essas leituras são artefato (Art. IV-6c):
- `spec 013 §7.1` — *"`pkg/kernel` vendorado (Dart puro, **P9 satisfeito**)"*. O `pkg/kernel` não toca o
  runtime do usuário; é dep interna do compilador. Se P9 só governasse o usuário, a frase seria vazia.
- `spec 013 §7.2` — *"**Régua de pureza**: é dep do COMPILADOR (P9/P10/P11 — a MESMA que já justifica o
  vendor `pkg/kernel`), **não** P8 (que governa a resolução de deps do `.tu` do usuário)"*. Isto **parte
  o Artigo I em dois domínios**: P8 = deps do usuário; P9/P10/P11 = deps do compilador.

**O teste (o que separa violação de uso legítimo de shell):** não é "invocou um binário externo", é
**"exige um runtime estrangeiro instalado?"**. `bash`/`curl`/`unzip`/`git`/`od`/`shasum` são base
POSIX/já-pressupostos pelo pipeline; `python3` é um runtime que não está na base de um container Linux
enxuto nem de um macOS sem Xcode CLT. Trocar `python3` por `od`/Dart não é cosmético — é a diferença
entre "precisa instalar linguagem alheia" e "usa o que já está lá".

**How to apply:**
1. Achou `python3` em `tools/*.sh`, hook, ou passo de CI ⟹ **dívida P9 real**, não "fora de escopo".
   Não precisa de emenda do dono (não se está pedindo licença para violar — se está consertando).
2. Prefira o leitor em **Dart** ao shell quando o compilador já tem o leitor: ex. o formato de Kernel
   tem constante in-tree `Tag.BinaryFormatVersion` (`third_party/dart/3.12.2/pkg/kernel/lib/binary/tag.dart:230`),
   e `codegen/lib/compile.dart::platformDillPath()` já deriva o `vm_platform.dill` do
   `Platform.resolvedExecutable`. Dart puro ⟹ P9 trivial + fonte única + sem armadilha de endianness.
3. **Caso-gatilho (2026-07-28):** `tools/pin-dart.sh:50` — `kver()` em `python3` era o ÚNICO leitor do
   formato de Kernel, com `2>/dev/null`: sem python3 ele devolve vazio e o script morre nas linhas
   138/148 com *"formato  != 130"* — falha cuja causa declarada é FALSA. Strike duplo: P9 **e** a
   diretriz "diagnóstico nunca mente" aplicada ao tooling.

Relacionadas: [[doctrine-declaracao-sobrevive-ao-tick-verde]], [[phase7-f7b-design-identity]] (fonte única > cópia).
