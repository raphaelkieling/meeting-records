# Data Model — App shell

## Meeting

Representa uma reunião distinta, não uma série recorrente.

| Campo | Swift | SQLite | Regras |
|-------|-------|--------|--------|
| id | UUID | TEXT PRIMARY KEY NOT NULL | UUID válido e estável entre aberturas |
| name | String | TEXT NOT NULL | Texto não vazio após remover espaços; Unicode preservado |
| createdAt | Date | REAL NOT NULL | Instante de criação, segundos desde Unix epoch |

Tabela `meetings`; primeira versão do schema identificada por `PRAGMA user_version = 1`.
A futura criação de Meeting fornecerá o nome aleatório previsto em PRODUCT.md. Esta etapa
não oferece criação ou renomeação. Nenhuma relação, Input ou Transcription é adicionada.

Leitura ordenada por `createdAt DESC, id ASC`, apenas para produzir lista determinística;
sem controles de ordenação nesta etapa. ID desambigua Meetings com nomes iguais.
Nomes longos permanecem completos no banco; truncamento é somente visual.

## Estado de navegação

Um enum em memória representa `home`, `settings` ou `meeting(UUID)`. O valor inicial
é sempre `home`. Seleção e foco são estados distintos; focar não deve gerar duas seleções.
Uma Meeting selecionada usa a identidade persistida, nunca o índice da linha.
Navegar não grava no banco. Não há restauração automática do último destino.

## Estado de carregamento

`loading → loaded([Meeting])` ou `loading → failed(mensagem)`.
`failed → loading` ao tentar novamente. `loaded([])` é vazio legítimo e deve ser distinto de erro.
Home e Configurações permanecem disponíveis em todos esses estados. Ao falhar, não apresentar
Meetings antigas como se tivessem sido carregadas com sucesso.

## Ciclo de armazenamento

- Resolver Application Support do usuário e criar apenas a subpasta do app quando necessário.
- Abrir com leitura/escrita e criação. Uma conexão confinada ao actor; nunca compartilhar
  ponteiro SQLite entre executores. Views recebem somente valores Swift.
- Banco novo v0: criar schema v1 e atualizar user_version na mesma transação. Em falha,
  rollback; sem marcar a migração como concluída.
- Banco v1: validar/levar adiante sem limpar registros e listar Meetings.
- Versão maior que 1: informar versão incompatível; não rebaixar, alterar ou apagar banco.
- Erro de abertura, schema, leitura ou registro inválido: informar falha recuperável,
  permitir retry e preservar o arquivo. Não substituir por banco vazio.
- Verificar retornos SQLite; finalizar statements e fechar conexão na liberação do store.
  Usar bindings para valores variáveis. Não registrar conteúdo de Meetings em logs.

## Isolamento de validação

Testes recebem URL temporária explicitamente no construtor do store. Para inspeção manual,
build DEBUG aceita `MEETING_RECORD_DATA_DIR` como diretório absoluto; build release usa sempre
Application Support. O helper existe apenas para não tocar dados reais durante validação.
Fixtures são inseridas no banco de teste por ferramenta SQLite externa; não há seed automático
em produção nem método público de criação incluído apenas para preparar demonstrações.
