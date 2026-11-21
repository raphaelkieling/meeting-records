# Research — Swift e SQLite para o app shell

Pesquisa de 2026-11-20. Decisões de design; implementação e medições ainda não realizadas.

## 1. Linguagem e interface

**Decision**: Swift 6 e SwiftUI. Usar `HStack` com sidebar de 240 pt, divisor e detalhe
flexível. Home e Configurações são controles fixos; Meetings usa `List` rolável. Todos
compartilham um enum de seleção, com foco visível e nomes acessíveis. Nome longo recebe
truncamento e help com texto completo; VoiceOver deve receber o nome completo.

**Rationale**: Dois painéis permanentes e sem roteador. A composição fixa evita que a
sidebar desapareça ao reduzir a janela e mantém os atalhos fora da região rolável.
Controles nativos reduzem o trabalho de teclado e acessibilidade, que será validado manualmente.

**Alternatives considered**: `NavigationSplitView` oferece navegação adaptativa e visibilidade
de colunas, úteis em outros escopos, mas desnecessárias aqui; uma única List faria os atalhos
rolarem junto com Meetings. AppKit completo exigiria mais código para este layout.

Fontes: [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview),
[TN3154](https://developer.apple.com/documentation/technotes/tn3154-adopting-swiftui-navigation-split-view).
A composição escolhida é uma decisão deste projeto, não um exemplo prescrito pela Apple.

## 2. Build e bundle

**Decision**: SwiftPM com um target executável `MeetingRecord`, testes XCTest e link da
biblioteca `sqlite3`. Manifesto Swift tools 6.0 e deployment target macOS 14. Script
`scripts/build-app.sh` com configuração debug padrão e opção `--release`, construindo bundle
em `.build/MeetingRecord.app`. Usar `swift build --show-bin-path` para localizar o binário.
`Resources/Info.plist` fornece identificador `com.meetingrecord.app`, tipo APPL, executável
MeetingRecord e mínimo de macOS consistente. Nenhum pacote remoto.

**Rationale**: Swift 6.4 e SDK estão disponíveis via CommandLineTools no ambiente observado;
`xcodebuild -version` falhou porque o developer directory ativo não contém Xcode completo.
SwiftPM evita exigir um gerador de projeto ou instalação de Xcode para iniciar o trabalho.
O mínimo macOS 14 é uma decisão conservadora do projeto, não um requisito do SQLite.

**Alternatives considered**: Projeto Xcode nativo, viável mas com requisito local adicional;
XcodeGen/Tuist não se justificam para um único executável. Apenas `swift run` não oferece
por si só o bundle de aplicativo que deve ser validado no Dock/Finder.

Fontes: [Swift PackageDescription](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html),
[bundle Apple](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle),
[CFBundleExecutable](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleexecutable).
O encaixe SwiftUI `@main App` + executável SwiftPM + bundle manual é uma inferência de design
que precisa de build e execução reais. Assinatura para distribuição, notarização e instalador
ficam fora desta feature; o bundle planejado atende desenvolvimento local.

## 3. SQLite mínimo

**Decision**: API C do SQLite disponível pelo módulo SQLite3 do SDK, sem ORM. Um actor
`MeetingStore` abre a conexão, inicializa schema v1 e lista Meetings. Verificar disponibilidade
do módulo no primeiro build; não escolher outra biblioteca automaticamente em caso de falha.
Não usar WAL ou framework genérico de migração nesta etapa.

**Rationale**: Uma tabela e uma consulta não justificam dependência externa. O actor confina
a conexão e permite que o carregamento seja aguardado sem fazer I/O no MainActor.
`sqlite3_open_v2` deve ter retornos verificados, inclusive cleanup de handle quando falha.
Queries usam prepare/step/finalize; bindings copiam texto quando a origem tem vida curta.

**Alternatives considered**: GRDB é útil para consultas e migrações mais amplas, mas aumenta
as dependências; Core Data/SwiftData acrescentam uma camada não solicitada sobre o banco.

Fontes: [open](https://www.sqlite.org/c3ref/open.html),
[prepare](https://www.sqlite.org/c3ref/prepare.html),
[bind](https://www.sqlite.org/c3ref/bind_blob.html),
[finalize](https://www.sqlite.org/c3ref/finalize.html).

## 4. Localização e evolução dos dados

**Decision**: Application Support resolvido por Foundation, subpasta MeetingRecord.
Criação de tabela e `user_version = 1` numa transação; versões futuras desconhecidas geram
erro preservando arquivo. Falhas de leitura são distintas de lista vazia e oferecem retry.

**Rationale**: Evita caminhos particulares do autor e qualquer recuperação destrutiva.
SQLite disponibiliza `user_version`, mas a política de interpretação pertence ao aplicativo.

**Alternatives considered**: Arquivo no diretório de execução depende de como o app é aberto;
recriar banco após erro perderia dados; mecanismo extensível de migrações é prematuro.

Fontes: [Application Support](https://developer.apple.com/documentation/foundation/url/applicationsupportdirectory),
[user_version](https://www.sqlite.org/pragma.html#pragma_user_version),
[transações](https://www.sqlite.org/lang_transaction.html).

## 5. Validação sem ampliar a interface

**Decision**: Testes de integração com SQLite real e pasta temporária; demonstração manual
com banco separado via `MEETING_RECORD_DATA_DIR` somente em DEBUG. O banco comum inicia vazio.
Fixtures de teste verificam persistência com duas instâncias sucessivas do store; a interface
não ganha botões de criação nem seed automático.

**Rationale**: Comprova a nova exigência de SQLite sem alterar o escopo visual. O override
é um ponto de isolamento de validação, não uma preferência do produto.

**Alternatives considered**: Mock de store não verifica persistência; inserir demonstrações
na base real mistura dados de teste e conteúdo pessoal; CRUD de reuniões pertence a outra feature.

## Resultado

Sem esclarecimentos bloqueantes. Swift/SQLite vieram do usuário; toolkit, empacotamento,
minimum OS e política de armazenamento são decisões desta pesquisa. Validação de runtime,
teclado, import SQLite3 e suporte ao macOS mínimo permanece trabalho da implementação,
sem representar dúvida sobre o escopo planejado.
