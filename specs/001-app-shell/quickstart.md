# Quickstart — Build e validação local

Implementação disponível. Resultados efetivamente verificados e limitações estão em
[validation.md](validation.md); os cenários abaixo podem ser repetidos sem usar a base pessoal.

## Pré-requisitos

Mac Apple Silicon com macOS 14+, Swift 6 e SDK macOS. Neste ambiente, usar Xcode 27.2:
o Command Line Tools ativo não inclui o plugin SwiftUI requerido pelo SDK atual.
Para o fixture manual: `sqlite3` e `uuidgen`. Nenhum modelo, conta ou servidor é necessário.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swift --version
xcode-select -p
```

## Build e testes

A partir da raiz do projeto:

```sh
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
xcrun swift build --disable-sandbox --cache-path .build/cache --manifest-cache local
xcrun swift test --disable-sandbox --cache-path .build/cache --manifest-cache local
bash scripts/build-app.sh
open .build/MeetingRecord.app
```

Esperado: build sem resolver pacotes externos; testes SQLite passam; bundle abre janela
com Home ativa e sidebar visível. Fechar o app antes de executar os cenários isolados abaixo.

## Banco isolado e primeira abertura

O script monta debug por padrão. Abrir o executável diretamente preserva o ambiente de teste:

```sh
meeting_record_validation_dir=$(mktemp -d /tmp/meeting-record-validation.XXXXXX)
MEETING_RECORD_DATA_DIR="$meeting_record_validation_dir" .build/MeetingRecord.app/Contents/MacOS/MeetingRecord
```

Esperado: Home ativa, seção Meetings vazia, arquivo `meetings.sqlite` no diretório temporário.
Fechar a janela e encerrar o app para retornar ao terminal. Manter a mesma sessão shell.
Não inserir fixtures no banco pessoal em Application Support.

## Lista persistida

Com o app encerrado, inserir somente dados de demonstração na base temporária já inicializada:

```sh
for meeting_record_index in {1..30}; do
  sqlite3 "$meeting_record_validation_dir/meetings.sqlite" "INSERT INTO meetings(id, name, createdAt) VALUES ('$(uuidgen)', 'Reuniao demonstracao $meeting_record_index com nome longo para validar a sidebar compacta', $meeting_record_index);"
done
MEETING_RECORD_DATA_DIR="$meeting_record_validation_dir" .build/MeetingRecord.app/Contents/MacOS/MeetingRecord
```

1. Conferir 30 registros; selecionar duas Meetings e conferir os títulos completos no detalhe.
2. Ir a Home, Configurações e outra Meeting: uma única seleção ativa a cada passo.
3. Rolar até o último registro: os dois destinos fixos continuam disponíveis.
4. Conferir truncamento, help, teclado e VoiceOver, inclusive nomes completos e foco visível.
5. Reduzir janela até 720×480: áreas não se sobrepõem. Comparar densidade à imagem de referência.
6. Fechar e reabrir com o mesmo comando: Home ativa e as mesmas 30 identidades/nomes preservados.
7. Repetir a navegação sem internet: sem pedidos de conta, modelo ou acesso ao áudio.

## Erro e preservação

Em outra pasta temporária, apontar `MEETING_RECORD_DATA_DIR` para um caminho que seja um arquivo,
não um diretório. Esperado: erro de armazenamento e retry; Home e Configurações funcionam.
Após corrigir o caminho e acionar retry, a lista deve carregar sem reiniciar o app.

Os testes automatizados devem cobrir: banco novo v1 vazio; registros Unicode/nomes iguais;
ordem estável; reabertura sem perda; falha de abertura; versão futura rejeitada sem alteração;
rollback se inicialização falhar; registro inválido não tratado como sucesso vazio.
Não escrever testes que apenas repliquem o layout SwiftUI.

## Release local

```sh
bash scripts/build-app.sh --release
open .build/MeetingRecord.app
```

Esperado: versão release abre e usa Application Support, sem aplicar override de DEBUG.
Não implica assinatura de distribuição, notarização ou instalação para outros usuários.

## Registro de evidências

Registrar versão do macOS/Swift, chip, memória, comandos e resultados dos testes. Registrar
captura visual, validação por teclado/VoiceOver e limitações. Se só houver Mac recente,
distinguir deployment target macOS 14 de teste real nessa versão; não alegar compatibilidade
validada sem executar nela. Conferir [contrato](contracts/ui-contract.md) e
[modelo](data-model.md) ao avaliar falhas.
