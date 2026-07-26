# Memória — dart-vm-expert (Itá → Dart Kernel/VM)

Fatos da VM/Kernel confirmados contra o vendor `third_party/dart/3.12.2/pkg/kernel` (Kernel fmt 130).
Regra: toda afirmação com arquivo:linha da fonte. VM C++ (`runtime/`) NÃO está vendorada — claims
sobre `kernel_loader.cc`/`closure_functions_cache.cc` são Grupo B não-verificável no vendor.

- [Offsets no Kernel/.dill](kernel-offsets.md) — `-1` é offset LEGAL (round-trip `+1`/`-1`); verifier só checa PRIMÁRIO de nós nomeados; secundários ele ignora
- [Field: isFinal ⟺ setter](kernel-field-mutability.md) — o verifier GATEIA `isImmutable == hasSetter` (erro); arestas isConst/isLate
- [LocalFunctionId](kernel-localfunctionid.md) — invalid=0, first=1, distinto por Member; Member = só Field/Constructor/Procedure; verifier NÃO checa id
- [ItaVerifyTarget vs VmTarget](verify-target-parity.md) — `verification` idêntico (base), mas tearoff-lowering flags DIVERGEM (NoneTarget=none) — furo de paridade
- [RecursiveVisitor: cadeia defaultNode](recursivevisitor-funnel.md) — todos os TreeNode afunilam em `defaultNode`; base p/ passes de saneamento
