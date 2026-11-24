# Produto — Meeting Record

## Objetivo

App para macOS que organiza reuniões, captura o microfone e o áudio do computador e produz transcrições locais. O uso inicial é pessoal, mas outras pessoas devem conseguir instalar e usar o app no próprio Mac, sem configuração específica do autor.

A primeira versão atende Macs com Apple Silicon. Depois do setup e do download dos modelos, funciona offline: áudios, textos e processamento permanecem na máquina, sem conta ou serviço de nuvem.

Os termos do domínio estão em [GLOSSARY.md](GLOSSARY.md).

## Organização e navegação

- A lista principal contém uma linha por Meeting. Trinta dailies são trinta Meetings distintas.
- Criar uma Meeting gera um registro vazio com nome aleatório, editável a qualquer momento. Criar não inicia a gravação.
- Dentro da Meeting, **Inputs** reúne os materiais de origem e **Transcription** apresenta a transcrição final unificada. Essa organização permite outras abas no futuro, sem incluí-las no escopo inicial.
- O primeiro Input define a origem da Meeting: **Recording** ou **Import**. Uma Meeting não mistura essas origens.
- Uma Meeting aceita vários Inputs da origem escolhida.

## Recording

1. O usuário cria ou abre uma Meeting e clica em Gravar.
2. O app captura simultaneamente microfone e áudio do computador, preservando duas faixas separadas em uma Recording.
3. Durante a captura, processa blocos de áudio a cada intervalo e apresenta e salva o texto incrementalmente.
4. Ao parar, finaliza o áudio e processa os blocos pendentes antes de considerar a transcrição concluída.
5. Gravar novamente na mesma Meeting cria outra Recording, preservando as anteriores. Não há pausa na primeira versão.

Há apenas uma Meeting em gravação por vez. O usuário pode navegar e usar o restante do app durante a captura; um indicador identifica a Meeting em gravação e permite pará-la.

### Falantes e idiomas

- A faixa do microfone recebe o rótulo **Me**; a faixa do computador recebe **Other**.
- Esses rótulos indicam a origem do áudio, não identidades verificadas. Todas as vozes capturadas pelo computador ficam como Other.
- Não há diarização, reconhecimento de pessoas, cadastro de participantes ou correção manual de falantes.
- Falas simultâneas das duas faixas são preservadas, ordenadas pelo horário de início, mesmo com sobreposição temporal.
- Português, espanhol e inglês devem ser aceitos, inclusive alternados dentro da mesma gravação. A qualidade precisa ser validada com exemplos reais.

### Processamento e recuperação

Realtime significa texto incremental com algum atraso, não uma promessa de resultado instantâneo por palavra. O trecho mais recente pode ser revisado pelo motor enquanto o processamento avança.

A captura do áudio tem prioridade. Se a transcrição atrasar, o app continua gravando, indica o processamento pendente e conclui a fila após a captura. Parar não exige uma segunda transcrição completa.

Áudio e texto são salvos progressivamente. Após um fechamento inesperado, o app recupera o conteúdo já persistido, identifica a Recording como interrompida e permite concluir o processamento pendente.

## Import

- O usuário escolhe arquivos manualmente para uma Meeting nova ou existente de origem Import.
- A primeira versão importa transcrições `.txt` e `.vtt`, além de áudio. Os formatos de áudio suportados ainda precisam ser definidos.
- O processamento pode começar assim que o arquivo for importado.
- O arquivo original é preservado. Nomes de falantes e timestamps existentes na transcrição são mantidos.
- Áudio importado é transcrito sem atribuição de identidade aos falantes, pois não há diarização.
- Uma transcrição importada não exige áudio correspondente. Não há integração direta com contas do Google Meet ou Zoom.

## Transcription unificada

A Meeting possui uma Transcription final, formada pelos resultados dos seus Inputs. Cada Input mantém seu próprio resultado e a origem dos trechos, permitindo reconstruir a versão unificada sem repetir processamento que continua válido.

Recordings entram em ordem de gravação. Arquivos importados entram em ordem de importação, com possibilidade de reorganização manual. Dentro de uma Recording, os trechos das duas faixas seguem o horário de início. Não há mesclagem inteligente nem remoção automática de conteúdo duplicado entre Inputs.

Durante a gravação, a Transcription é atualizada incrementalmente; fica concluída quando todos os Inputs terminam de processar. Novos Inputs incorporam seus resultados à mesma transcrição.

A primeira versão permite ler e copiar o texto. Edição manual, reprodução sincronizada e navegação do texto para o áudio ficam fora do escopo.

## Meeting search and labels

- A Search entry below Home opens a dedicated view with a plain text field and a label filter to its right.
- Meetings can have an optional plain-text description. Users can edit it from a meeting's context menu; the saved description appears beneath the meeting title and can be searched.
- Text search covers meeting titles, descriptions, available transcript text, and label names. Results update while typing and show a relevant transcript excerpt when the match comes from transcript text, plus a non-empty meeting description beneath its title.
- Text and label filters combine with AND. Selecting multiple labels returns meetings containing every selected label. With no text, selected labels filter the list on their own.
- The Labels page below Search lets users create, rename, recolor, and delete shared labels. Deleting a label removes it from every meeting that uses it.
- A meeting's context menu includes Labels. Its modal shows current assignments and lets users select or remove shared labels before saving.
- A meeting with labels displays an outlined tag icon on the right side of its sidebar row.
- Search is local and works offline. It must remain responsive during recording and normal navigation.

## Armazenamento e exclusão

O conteúdo é mantido localmente até exclusão manual; transcrever não apaga o áudio. Excluir uma Meeting exige confirmação e remove todos os seus Inputs, áudios e transcrições. Também é possível excluir um Input e atualizar a transcrição unificada para refletir os materiais restantes.

## Setup e decisões técnicas pendentes

O setup permite baixar explicitamente o modelo necessário, mostrando tamanho e progresso. Depois disso, o fluxo principal funciona sem internet.

A primeira versão terá um único motor e modelo validados, sem interface de comparação. Whisper e Parakeet são candidatos, não escolhas confirmadas. A avaliação técnica deve determinar:

- Qualidade em português, espanhol, inglês e alternância entre idiomas.
- Viabilidade da transcrição incremental em duas faixas em Apple Silicon.
- Latência, intervalo dos blocos, uso de memória e impacto na captura.
- Chip e memória do Mac de referência, requisitos mínimos e formatos de áudio importáveis.

## Critérios de aceitação da primeira versão

- Criar e renomear uma Meeting vazia sem iniciar a captura.
- Gravar várias Recordings na mesma Meeting, com duas faixas e texto incremental Me / Other, enquanto o app continua navegável.
- Preservar falas sobrepostas e concluir blocos pendentes ao parar.
- Importar transcrições com ou sem nomes e timestamps, sem exigir áudio; importar áudio sem inventar identidades.
- Consultar e copiar uma Transcription unificada que respeite a ordem dos Inputs e preserve a origem dos trechos.
- Recuperar conteúdo persistido de uma Recording interrompida e retomar seu processamento.
- Executar esses fluxos offline após o setup e remover todo o conteúdo de uma Meeting ao excluí-la.

## Fora da primeira versão

Resumos automáticos, extração de decisões ou tarefas, diarização, edição de transcrições ou falantes, reconhecimento de voz entre Recordings, sincronização em nuvem, outras plataformas e agrupamento de Meetings em séries recorrentes.
