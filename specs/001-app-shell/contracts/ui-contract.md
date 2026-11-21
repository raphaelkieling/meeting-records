# Contract — Janela, navegação e armazenamento

## Superfície do usuário

- Janela Meeting Record: duas áreas, inicialmente 1000×700 pt, mínimo 720×480 pt.
- Sidebar de 240 pt: Home; Configurações; seção Meetings com lista rolável.
- Home inicial a cada lançamento, mesmo se a execução anterior terminou em outra área.
- Um destino ativo; selecionar Home/Configurações limpa seleção visual da lista de Meetings.
- Home/Configurações: título e mensagem curta de estado inicial, sem controles futuros.
- Meeting: nome completo no detalhe e mensagem de espaço vazio; sem abas, áudio ou ações CRUD.
- Nome na linha: uma linha truncada, com nome completo por help e acessibilidade.
- Rolagem da lista não desloca Home/Configurações. Destinos operáveis por teclado, foco visível,
  rótulos acessíveis e VoiceOver identifica seleção. Repetir seleção mantém o destino atual.

## Leitura do banco

A janela abre independentemente do carregamento. `MeetingStore` inicializa o banco e retorna
Meetings como valores Swift, conforme [data-model.md](../data-model.md).

| Resultado | Apresentação |
|-----------|--------------|
| Carregando | Indicador na seção Meetings; Home/Configurações utilizáveis |
| Sucesso com registros | Uma linha por Meeting, ordenação determinística |
| Sucesso vazio | Mensagem Nenhuma reunião, sem botão de criação |
| Falha | Mensagem Não foi possível carregar as reuniões e botão Tentar novamente |

Erro não significa lista vazia. Retry repete a abertura/leitura; não apaga dados. Se uma
identidade selecionada não estiver mais na lista após recarga, retornar a Home.

## Persistência e validação

- Primeira abertura cria banco/schema vazio; abrir novamente preserva registros existentes.
- Nenhuma mutação de Meeting é disparada por seleção, foco ou mudança de tela.
- No build DEBUG, `MEETING_RECORD_DATA_DIR` absoluto substitui só o diretório de dados.
  Valor inválido gera erro, sem fallback silencioso para a base pessoal.
- Build release ignora o override e usa Application Support do usuário.
- Schema incompatível ou erro de SQLite mantém o arquivo intacto e deixa os destinos fixos disponíveis.
- Nenhuma interface de rede, CLI de produto ou API pública é adicionada nesta feature.

## Empacotamento local

`scripts/build-app.sh` monta `.build/MeetingRecord.app`; debug por padrão, `--release` para
release. O script deve falhar se o build ou cópia do executável falhar, sem apresentar um
bundle antigo como resultado novo. Não instala no diretório Applications nem publica artefatos.
