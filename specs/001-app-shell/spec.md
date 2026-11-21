# Feature Specification: Estrutura inicial e navegação do Meeting Record

**Feature Branch**: Não criada; nenhum hook de branch configurado.

**Created**: 2026-11-20

**Status**: Draft

**Input**: User description: "Quero fazer o setup desse projeto, a princípio só vai ter
uma sidebar e um main content. Algo condensado com Home, Configurações em cima e Meetings
abaixo, como a sidebar do GPT com as conversas do lado. A ideia é só fazer isso funcionar,
nada mais." Imagem fornecida como referência de densidade e organização lateral.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Abrir o app e navegar pelas áreas principais (Priority: P1)

Como usuário, quero abrir o Meeting Record e encontrar uma sidebar compacta ao lado do
conteúdo principal, com Home e Configurações no topo, para navegar sem perder o contexto.

**Why this priority**: É a estrutura mínima que torna o projeto utilizável e permite
acrescentar as funções do produto em etapas posteriores.

**Independent Test**: Abrir o app, acessar Configurações e voltar para Home, verificando
que apenas o conteúdo principal e a seleção ativa mudam.

**Acceptance Scenarios**:

1. **Given** o app fechado, **When** o usuário abre o app, **Then** a janela apresenta
   sidebar à esquerda, conteúdo principal à direita e Home selecionada.
2. **Given** Home aberta, **When** o usuário seleciona Configurações, **Then** o conteúdo
   principal identifica Configurações e a sidebar continua visível com essa seleção ativa.
3. **Given** Configurações aberta, **When** o usuário seleciona Home, **Then** o conteúdo
   principal volta a identificar Home e somente Home fica marcada como ativa.
4. **Given** qualquer uma dessas áreas aberta e sem internet, **When** o usuário navega,
   **Then** a navegação funciona sem conta, download de modelo ou pedido de acesso ao áudio.

---

### User Story 2 - Encontrar e selecionar Meetings na sidebar (Priority: P2)

Como usuário, quero ver Meetings abaixo da navegação principal e selecionar uma delas,
como faço com conversas na sidebar do GPT, para abrir seu espaço no conteúdo principal.

**Why this priority**: Estabelece o lugar das reuniões na navegação, sem antecipar os
fluxos de gravação, importação ou gerenciamento de reuniões.

**Independent Test**: Com duas Meetings de demonstração disponíveis, selecionar cada uma
e verificar que o título do conteúdo principal acompanha a seleção.

**Acceptance Scenarios**:

1. **Given** Meetings disponíveis para exibição, **When** o usuário observa a sidebar,
   **Then** encontra a seção Meetings abaixo de Home e Configurações, com uma linha por reunião.
2. **Given** duas Meetings na lista, **When** o usuário seleciona uma delas, **Then** seu
   nome aparece no conteúdo principal e somente essa Meeting fica marcada como ativa.
3. **Given** uma Meeting selecionada, **When** o usuário abre Home ou Configurações,
   **Then** a seleção da Meeting é removida e o destino escolhido ocupa o conteúdo principal.
4. **Given** nenhuma Meeting disponível, **When** o app abre, **Then** a seção Meetings
   apresenta um estado vazio compreensível e Home e Configurações continuam acessíveis.
5. **Given** Meetings armazenadas localmente, **When** o usuário fecha e reabre o app,
   **Then** as mesmas Meetings aparecem na sidebar e Home volta a ser o destino inicial.
6. **Given** falha ao abrir ou ler o armazenamento, **When** o app inicia, **Then** apresenta
   o erro e permite tentar novamente, mantendo Home e Configurações acessíveis e sem apagar dados.

### Edge Cases

- Uma lista com 30 Meetings deve permitir chegar ao último item por rolagem sem tirar
  Home e Configurações de acesso no topo da sidebar.
- Um nome de Meeting maior que a largura da sidebar deve ser truncado visualmente, sem
  ampliar a sidebar ou sobrepor o conteúdo principal; seu nome completo deve ser consultável.
- Cliques repetidos no destino já selecionado devem manter a mesma tela e uma única seleção ativa.
- Ao reduzir a janela até seu tamanho mínimo permitido, sidebar e conteúdo principal devem
  continuar utilizáveis, sem sobreposição; esse tamanho será definido no planejamento.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O app DEVE abrir uma janela utilizável no macOS em Apple Silicon, organizada
  em duas áreas: sidebar à esquerda e conteúdo principal ocupando o espaço restante.
- **FR-002**: A sidebar DEVE apresentar, nesta ordem, Home, Configurações e a seção Meetings.
  Home e Configurações DEVEM permanecer acessíveis acima da lista rolável de Meetings.
- **FR-003**: Home DEVE ser o destino inicial a cada abertura do app. Home e Configurações
  DEVEM exibir seu título e um estado inicial simples, sem controles de funções futuras.
- **FR-004**: Selecionar um destino DEVE atualizar o conteúdo principal e destacar somente
  o item ativo, mantendo a sidebar visível.
- **FR-005**: Cada Meeting disponível DEVE ocupar uma linha selecionável na seção Meetings.
  Sua seleção DEVE apresentar o nome da reunião no conteúdo principal, sem iniciar captura
  ou processamento.
- **FR-006**: A seção Meetings DEVE suportar lista vazia, rolagem de listas longas e nomes
  longos sem comprometer a navegação. O nome completo truncado DEVE ser consultável.
- **FR-007**: O layout DEVE ter densidade compacta: itens em linhas únicas e hierarquia
  visual discreta entre navegação fixa e Meetings, conforme a referência fornecida.
  A composição DEVE manter duas áreas, sem acrescentar a coluna intermediária da imagem.
- **FR-008**: A navegação DEVE funcionar offline, sem autenticação, download de modelos,
  permissões de microfone ou captura de áudio do computador.
- **FR-009**: Home, Configurações e itens de Meetings DEVEM ser acessíveis por teclado,
  com foco visível e nomes compreensíveis para tecnologias assistivas.

- **FR-010**: O app DEVE inicializar o armazenamento local de Meetings na primeira abertura
  e carregar registros existentes nas aberturas seguintes, preservando identidade e nome.
  Falhas de armazenamento DEVEM ser informadas com opção de tentar novamente, sem apagar
  ou recriar destrutivamente o banco.

### Key Entities *(include if feature involves data)*

- **Destino de navegação**: Home, Configurações ou uma Meeting específica; apenas um
  destino pode estar ativo de cada vez.
- **Meeting na navegação**: Representação mínima de uma reunião distinta, com identidade
  e nome para listar e selecionar. Esta feature não adiciona Inputs ou transcrições.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Ao abrir o app, o usuário encontra Home e as duas áreas visíveis, sem etapas
  de configuração prévias, inclusive sem conexão com a internet.
- **SC-002**: Home, Configurações e cada Meeting disponível podem ser abertas com uma única
  seleção na sidebar; 100% das transições dos cenários de aceitação exibem o destino correto
  e exatamente um item ativo.
- **SC-003**: Com 30 Meetings disponíveis, o usuário alcança e abre a última por rolagem;
  Home e Configurações permanecem acessíveis e nomes longos não sobrepõem as áreas.
- **SC-004**: Todos os destinos disponíveis podem ser alcançados e ativados usando apenas
  o teclado, com identificação visual do foco e do destino selecionado.
- **SC-005**: Na revisão visual, a janela apresenta exatamente duas áreas, com Home e
  Configurações acima de Meetings e itens compactos em linhas únicas, inclusive no tamanho
  mínimo de janela adotado.

- **SC-006**: Em uma base com 30 Meetings, 100% das identidades e nomes são mantidos após
  fechar e reabrir o app; na falha de leitura, os dados permanecem intactos e a navegação
  principal continua disponível.

## Assumptions

- Esta entrega estabelece apenas a estrutura executável e a navegação do app. Não representa
  a conclusão da primeira versão descrita em PRODUCT.md.
- Home é uma tela inicial simples. Configurações é apenas um destino navegável nesta etapa,
  sem preferências editáveis ou setup de modelos.
- A lista inicia vazia na ausência de dados. Dados locais de demonstração podem ser usados
  para validar seleção, nomes longos e rolagem, sem exigir criação de Meetings pela interface
  e sem apresentar exemplos como reuniões reais do usuário.
- Criar, renomear, excluir, ordenar e buscar Meetings,
  gravar, importar, transcrever e apresentar abas Inputs/Transcription ficam fora desta feature.
- A imagem e a referência ao GPT orientam a organização e densidade. Não exigem reprodução
  dos elementos de GitHub, das três colunas ou de todas as funções desses produtos.
- A constituição e PRODUCT.md orientam o domínio e o uso local. Princípios de captura,
  recuperação e transcrição serão aplicados quando esses fluxos forem especificados.
- Atualização de escopo em 2026-11-20: a instrução de planejamento adiciona armazenamento
  local persistente de Meetings. A implementação usará Swift e SQLite conforme solicitado;
  a interface continua limitada à navegação.
- O procedimento para executar o projeto será definido em
  `$speckit-plan`; esta especificação não depende de serviços externos ou de motor de transcrição.
