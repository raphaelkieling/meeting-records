# Tasks: Estrutura inicial e navegação do Meeting Record

**Input**: Documentos em `specs/001-app-shell/`: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/ui-contract.md` e `quickstart.md`.
**Prerequisites**: Plano e especificação disponíveis; seguir `.specify/memory/constitution.md`.
**Organization**: Tarefas agrupadas por história; esta lista prepara a implementação, sem declarar funcionalidades ou validações já concluídas.
**Validation**: Aceitação manual por história; verificação reproduzível de persistência conforme FR-010/SC-006 e constituição. O plano define XCTest com SQLite real para essa verificação, sem testes que apenas espelhem o layout.

## Format: `[ID] [P?] [Story] Description`

- `[P]`: pode executar em paralelo com as tarefas indicadas nos exemplos, após seus pré-requisitos; arquivos distintos.
- `[US1]` e `[US2]`: histórias da especificação. Setup, fundação e acabamento não recebem história.
- Caminhos relativos à raiz do projeto. Fontes em `Sources/MeetingRecord/`, testes em `Tests/MeetingRecordTests/` e bundle gerado em `.build/MeetingRecord.app`.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Preparar o pacote local sem dependências externas.

- [X] T001 Criar `Package.swift` com Swift tools 6.0, modo Swift 6, macOS 14+, executável MeetingRecord, target XCTest MeetingRecordTests e link sqlite3, usando os diretórios definidos em `specs/001-app-shell/plan.md`.
- [X] T002 [P] Criar `.gitignore` para excluir `.build/`, metadados locais do SwiftPM e arquivos temporários de validação, preservando fontes e documentação.
- [X] T003 [P] Criar `Resources/Info.plist` com identificador com.meetingrecord.app, tipo APPL, executável MeetingRecord e mínimo macOS consistente com `Package.swift`, sem permissões de captura.

**Checkpoint**: Manifesto e metadados prontos para receber as fontes; build executável será validado após US1.

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Definir os valores compartilhados de identidade e navegação, sem antecipar persistência ou CRUD.

- [X] T004 Implementar o valor Swift Meeting em `Sources/MeetingRecord/Meeting.swift`, adequado para transferência entre actor e views, com identidade estável e validação conforme `data-model.md`: `Meeting.id`, `Meeting.name` e `Meeting.createdAt`; manter o nome completo e desambiguar nomes iguais pelo ID.
- [X] T005 Definir o enum de destino único em `Sources/MeetingRecord/ContentView.swift` conforme a seção Estado de navegação de `specs/001-app-shell/data-model.md`, com home inicial, settings e meeting(UUID), sem persistência de seleção e sem confundir foco com destino ativo.

**Checkpoint**: Valores compartilhados prontos; as duas histórias podem iniciar com as restrições de integração descritas nas dependências.

## Phase 3: User Story 1 — Abrir o app e navegar pelas áreas principais (Priority: P1) 🎯 MVP

**Goal**: Abrir uma janela com sidebar compacta permanente e alternar entre Home e Configurações.

**Independent Test**: Abrir o bundle, conferir Home inicial, ir a Configurações e voltar, inclusive com seleções repetidas, offline e somente por teclado. Apenas um destino deve ficar ativo; sidebar permanece visível. Esta história funciona com a seção Meetings vazia, antes da conexão ao banco em US2.

### Implementation for User Story 1

- [X] T006 [P] [US1] Criar a entrada SwiftUI em `Sources/MeetingRecord/MeetingRecordApp.swift` com uma janela de trabalho, tamanho inicial 1000×700 pt e mínimo 720×480 pt; aplicar integração AppKit somente se necessária para cumprir o contrato de janela em `specs/001-app-shell/contracts/ui-contract.md`.
- [X] T007 [P] [US1] Implementar `Sources/MeetingRecord/SidebarView.swift` com largura 240 pt, Home e Configurações fixas acima da seção Meetings inicialmente vazia, controles nativos compactos de linha única e binding para o destino compartilhado; oferecer operação por teclado, foco visível e rótulos acessíveis.
- [X] T008 [US1] Completar `Sources/MeetingRecord/ContentView.swift` com HStack, divisor, sidebar e detalhe flexível, títulos e mensagens simples de Home/Configurações, destaque exclusivo por destino e seleção repetida idempotente; não adicionar controles futuros.
- [X] T009 [US1] Criar `scripts/build-app.sh` com debug padrão e opção --release, compilando via SwiftPM e localizando o executável com --show-bin-path; montar `.build/MeetingRecord.app` com `Resources/Info.plist`, propagar falhas de build/cópia e impedir que bundle antigo seja apresentado como resultado novo; verificar também a importação SQLite3 do SDK sem adicionar bibliotecas alternativas.
- [ ] T010 [US1] Executar build e abertura do bundle, validar os quatro cenários de US1, teclado, VoiceOver, foco e geometria mínima; registrar ambiente, resultados e limitações em `specs/001-app-shell/validation.md`, incluindo ausência de solicitações de conta, modelos ou permissões de áudio (FR-001–004, FR-007–009; SC-001, SC-002, SC-004, SC-005).

**Checkpoint**: Shell executável utilizável e verificável sem depender do armazenamento de US2.

## Phase 4: User Story 2 — Encontrar e selecionar Meetings na sidebar (Priority: P2)

**Goal**: Carregar Meetings persistidas e navegar por elas com estados de carregamento, vazio, erro e retry preservando dados.

**Independent Test**: Em diretório temporário DEBUG, iniciar banco vazio, inserir fixtures externamente com o app encerrado, selecionar duas Meetings e alternar com os destinos fixos. Validar 30 registros, nomes longos, reabertura com Home inicial e erro recuperável sem perda de dados. XCTest deve usar bases temporárias, nunca a base pessoal.

### Implementation and persistence verification for User Story 2

- [X] T011 [P] [US2] Implementar em `Sources/MeetingRecord/MeetingStore.swift` um actor concreto com URL explícita para testes e resolução padrão por FileManager de Application Support/MeetingRecord/meetings.sqlite; aceitar MEETING_RECORD_DATA_DIR absoluto somente em DEBUG, rejeitar override inválido sem fallback e ignorá-lo em release; realizar abertura fora do MainActor, confinar o handle SQLite ao actor, verificar códigos de retorno e fechar/liberar recursos inclusive em falhas.
- [X] T012 [US2] Implementar inicialização e leitura em `Sources/MeetingRecord/MeetingStore.swift`: schema v1 e user_version na mesma transação com rollback, reabertura v1 sem limpar registros, rejeição de versão futura sem alteração e leitura determinística conforme `specs/001-app-shell/data-model.md`; aplicar as definições canônicas `data-model.md`: `Meeting.id`, `Meeting.name` e `Meeting.createdAt` ao schema e à decodificação; finalizar statements, usar bindings para valores variáveis, propagar erros de schema/registro/leitura e não registrar conteúdo pessoal.
- [X] T013 [P] [US2] Implementar em `Sources/MeetingRecord/SidebarView.swift` a lista rolável de Meetings por identidade persistida, seleção compartilhada com os destinos fixos, truncamento de uma linha com help e nome acessível completos, indicação acessível da seleção e foco de teclado; manter os dois destinos fixos fora da rolagem e apresentar loading, Nenhuma reunião ou erro com Tentar novamente conforme `specs/001-app-shell/contracts/ui-contract.md`.
- [X] T014 [US2] Integrar store e sidebar em `Sources/MeetingRecord/ContentView.swift` com estado no MainActor e carregamento assíncrono conforme Estado de carregamento de `specs/001-app-shell/data-model.md`; manter Home/Configurações disponíveis durante I/O e falha, eliminar apresentação de registros antigos em erro, permitir retry inclusive após falha de abertura e retornar a Home se a identidade selecionada desaparecer na recarga; apresentar nome completo da Meeting no detalhe sem mutações no banco.
- [X] T015 [US2] Verificar o armazenamento real em `Tests/MeetingRecordTests/MeetingStoreTests.swift` usando URL temporária e fixtures inseridas diretamente por SQLite, cobrindo banco novo v1 vazio, Unicode e nomes iguais com IDs distintos, nomes completos preservados, ordenação com desempate e reabertura por uma segunda instância do store sem perda; comparar todas as identidades e nomes de 30 registros conforme SC-006, sem API pública de criação para fixtures.
- [X] T016 [US2] Completar `Tests/MeetingRecordTests/MeetingStoreTests.swift` com falhas de abertura e nova tentativa após corrigir o caminho, schema incompatível e registro inválido como erro em vez de vazio, versão futura preservada e rollback de inicialização com falha induzida reproduzível; verificar registros/schema/user_version após falhas e isolamento do override DEBUG inválido, sem recuperação destrutiva.
- [ ] T017 [US2] Executar swift test e os cenários isolados de `specs/001-app-shell/quickstart.md`, incluindo vazio, duas seleções, 30 Meetings, nomes longos, rolagem com destinos fixos, reabertura, erro/retry e navegação offline; registrar evidências em `specs/001-app-shell/validation.md`, verificando também que selecionar/focar/navegar não altera os dados (FR-005, FR-006, FR-010; SC-002–006).

**Checkpoint**: Navegação de Meetings persistidas completa; falha de armazenamento mantém dados e navegação principal acessíveis.

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Tornar execução reproduzível e registrar os limites da validação local.

- [X] T018 [P] Criar `README.md` com pré-requisitos macOS Apple Silicon/Swift, comandos de build/teste e bundle debug/release, localização dos dados, fixtures exclusivamente temporárias e escopo desta feature; alinhar os comandos em `specs/001-app-shell/quickstart.md` ao comportamento implementado.
- [ ] T019 Executar o fluxo completo debug e release de `specs/001-app-shell/quickstart.md` e registrar em `specs/001-app-shell/validation.md` os comandos, versões, chip/memória, captura visual, teclado/VoiceOver, geometria, comportamento release ignorando override DEBUG e medição da troca de destino após carga frente à meta técnica de 100 ms; distinguir deployment target macOS 14 de execução real nessa versão e apontar qualquer verificação indisponível.
- [X] T020 Confrontar evidências e implementação com FR-001–010, SC-001–006 e `specs/001-app-shell/contracts/ui-contract.md`, registrando a matriz de resultados e eventuais pendências em `specs/001-app-shell/validation.md`; confirmar ausência de CRUD, áudio, modelos, rede, seed de produção e instalação/publicação, sem declarar concluída a versão completa de PRODUCT.md.

## Dependencies & Execution Order

### Phase Dependencies

```text
Setup (T001–T003)
  └─ Foundation (T004–T005)
       ├─ US1 (T006–T010) ───────────────────────────┐
       └─ US2 store (T011–T012)                     │
            └─ persistence checks (T015–T016)      │
US1 sidebar/content (T007–T008)                     │
  └─ US2 list (T013) + store (T012)                 │
       └─ integration (T014)                       │
            └─ US2 acceptance (T017) ──────────────┤
                                                  └─ Polish (T018–T020)
```

- Setup e fundação bloqueiam ambas as histórias. T004 precede T005 para a identidade usada na navegação.
- US1: T006 e T007 podem ocorrer juntas; T008 integra ambas. T009 depende das fontes de US1 e metadados; T010 depende do bundle.
- US2: T011 → T012. Após T012, T015 → T016 verificam o store sem precisar da UI. Não executar T015/T016 em paralelo entre si: editam o mesmo arquivo.
- T013 depende da sidebar de US1; pode ocorrer em paralelo com T011/T012. T014 depende de T008, T012 e T013; T017 depende de T009, T014 e T016.
- US2 é verificável isoladamente com fixtures, mas reutiliza o shell de US1 para a aceitação visual. Seu store pode avançar após a fundação sem esperar o aceite visual de US1.
- T018 pode ocorrer enquanto T019 valida o produto, desde que T019 use a versão dos comandos já acordada. T020 sucede ambos e todos os checkpoints.
- Sem paralelismo entre tarefas que editam o mesmo arquivo. As dependências são pré-requisitos para execução futura, sem implicar delegação nesta geração.

## Parallel Example: User Story 1

Após a fundação:

```text
T006: Sources/MeetingRecord/MeetingRecordApp.swift
T007: Sources/MeetingRecord/SidebarView.swift
```

Integrar em T008, empacotar em T009 e validar em T010.

## Parallel Example: User Story 2

Após a fundação e T007–T008:

```text
T011 → T012: Sources/MeetingRecord/MeetingStore.swift
T013: Sources/MeetingRecord/SidebarView.swift
```

Após T012 e T013:

```text
T014: Sources/MeetingRecord/ContentView.swift
T015 → T016: Tests/MeetingRecordTests/MeetingStoreTests.swift
```

Convergir em T017. A marcação `[P]` indica oportunidade com outro ramo independente, sem dispensar os pré-requisitos acima.

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Concluir Setup e Foundational.
2. Implementar US1 e validar o bundle com Home/Configurações e Meetings vazia.
3. Aceitar esse incremento como shell de navegação; a feature inteira ainda exige US2 e sua persistência.

### Incremental Delivery

1. US1 entrega janela e navegação principal.
2. US2 acrescenta store, leitura persistida, seleção de Meetings e estados recuperáveis, com verificação em banco temporário.
3. Acabamento documenta execução, acessibilidade, medições e limites reais do ambiente.
4. Cada checkpoint deve passar antes de declarar o incremento concluído. Corrigir o comportamento na tarefa responsável caso falhe na verificação; não ampliar para fluxos de PRODUCT.md fora desta feature.

## Notes

- As citações de campos em T004/T012 resolvem para a tabela Meeting de `specs/001-app-shell/data-model.md`, fonte canônica das restrições; não duplicar regras divergentes.
- Não criar repository genérico, ORM, camada de serviços, roteador ou dependências de terceiros.
- Testes de persistência usam SQLite real e recursos temporários; validação visual segue os cenários de aceitação, sem testes que apenas repliquem a implementação SwiftUI.
- Não usar fixtures na base pessoal nem apresentar dados demonstrativos como reuniões reais.

## Execution status — 2026-11-21

17/20 tarefas concluídas. T010, T017 e T019 tiveram build, testes e cenários visuais executados, mas permanecem abertas para a aceitação manual restante descrita em [validation.md](validation.md). Código das duas histórias e bundle release disponíveis; nenhuma pendência foi marcada como validada sem evidência.
