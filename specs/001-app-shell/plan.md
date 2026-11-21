# Implementation Plan: Estrutura inicial do Meeting Record

**Branch**: nenhuma branch Git criada; `001-app-shell` é o identificador retornado pelo
setup do Spec Kit em diretório sem repositório Git.
**Date**: 2026-11-20 | **Spec**: [spec.md](spec.md)

**Input**: `specs/001-app-shell/spec.md` e instrução de planejamento: Swift e SQLite para Meetings.

## Summary

Criar um app macOS em Swift/SwiftUI com sidebar compacta e conteúdo principal. Home e
Configurações ficam fixas acima da lista rolável de Meetings. Um único destino selecionado
controla o destaque e o conteúdo. Usar SQLite do sistema para inicializar o banco e carregar
Meetings persistidas, sem acrescentar CRUD à interface. A spec foi alinhada à nova instrução
por FR-010, SC-006 e cenários de persistência/erro.

Build por Swift Package Manager e script pequeno para montar um `.app` local. Sem pacotes
externos, servidor, conta, modelos de transcrição ou permissões de áudio. Este comando entrega
somente planejamento; fontes, configuração de build e banco serão criados na implementação.

## Technical Context

**Language/Version**: Swift 6, manifesto tools-version 6.0, modo Swift 6.

**Primary Dependencies**: SwiftUI, Foundation, AppKit apenas para integração de janela se
necessária; módulo SQLite3 e libsqlite3 do SDK macOS. Nenhuma dependência de terceiros.

**Storage**: arquivo SQLite local em Application Support/MeetingRecord/meetings.sqlite;
resolução por FileManager, sem caminho absoluto do autor. Schema v1 com `PRAGMA user_version`.

**Testing**: XCTest para armazenamento SQLite em diretório temporário e reabertura; validação
manual do bundle para navegação, teclado, VoiceOver, lista longa e janela mínima.

**Target Platform**: macOS 14+ em Apple Silicon; baseline de projeto a validar. Ambiente
observado: macOS 27.2.1 arm64, Swift 6.4 e CommandLineTools ativo. `xcodebuild` indisponível
na seleção atual; build e execução reais ainda não verificados.

**Project Type**: aplicativo desktop, executável SwiftPM empacotado em bundle `.app`.

**Performance Goals**: navegar com uma seleção e renderizar 30 Meetings sem bloquear interação;
meta técnica de troca de destino em até 100 ms após carregamento no Mac de desenvolvimento.
Carregamento inicial do banco fora do MainActor; Home disponível durante leitura.

**Constraints**: offline, duas áreas sempre visíveis, Home inicial, sem estado de navegação
persistido; janela inicial 1000×700 pt, mínimo 720×480 pt, sidebar de 240 pt. Valores são
ponto inicial de implementação e devem passar na validação visual.

**Scale/Scope**: um usuário local, uma janela de trabalho, Home/Configurações e detalhe mínimo
de Meeting; uma tabela. Fixtures de 30 registros exclusivamente para validação.

## Constitution Check

*GATE: avaliado antes da pesquisa e reavaliado após o design.*

| Princípio | Antes da pesquisa | Após o design |
|-----------|-------------------|---------------|
| I. Local/offline | PASS: Swift e SQLite locais | PASS: sem rede; Application Support resolvido no Mac |
| II. Captura durável | Não aplicável: sem captura | Sem introduzir áudio, filas ou permissões |
| III. Origem e reconstrução | PASS: apenas Meeting mínima | PASS: identidade persistida; sem Inputs; erro não apaga banco |
| IV. Fidelidade | Não aplicável: sem transcrição | Sem identidades, áudio ou texto transcrito simulado |
| V. Simplicidade/validação | PASS: somente shell e banco | PASS: frameworks do sistema; testes focados e revisão visual |

Nenhuma violação. Esta etapa prepara o produto; não afirma atender os critérios completos
da primeira versão. O idioma de programação e o armazenamento foram definidos pelo usuário;
a ampliação de persistência foi registrada na spec, preservando o limite da interface.

## Project Structure

### Documentation (this feature)

```text
specs/001-app-shell/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── checklists/requirements.md
└── contracts/ui-contract.md
```

`tasks.md` será gerado por `$speckit-tasks`, não nesta fase.

### Source Code (repository root)

Estrutura proposta; estes arquivos ainda não existem:

```text
Package.swift
Sources/MeetingRecord/
├── MeetingRecordApp.swift
├── ContentView.swift
├── SidebarView.swift
├── Meeting.swift
└── MeetingStore.swift
Tests/MeetingRecordTests/
└── MeetingStoreTests.swift
Resources/Info.plist
scripts/build-app.sh
README.md
```

**Structure Decision**: um target executável e um target de testes. Modelo e armazenamento
separados das views para testar reabertura e erros sem iniciar a interface. `MeetingStore`
é um actor concreto dono de uma conexão SQLite; sem protocolo de repository, ORM, camada
de serviços ou sistema de rotas. View principal mantém seleção e estado de carregamento
no MainActor. O script compila e monta o bundle em `.build/MeetingRecord.app`.

## Phase 0 — Research

Decisões e fontes em [research.md](research.md): SwiftUI, SwiftPM/bundle, SQLite direto,
persistência local, seleção única e validação isolada. Não há decisão técnica bloqueante
em aberto. Viabilidade do conjunto deve ser comprovada pelo build e execução na implementação.

## Phase 1 — Design & Contracts

- [data-model.md](data-model.md): campos, schema lógico, estados e comportamento de erro.
- [contracts/ui-contract.md](contracts/ui-contract.md): janela, navegação, banco e isolamento.
- [quickstart.md](quickstart.md): comandos previstos e cenários reproduzíveis de validação.

Ordem de entrega: pacote e bundle executável; store com inicialização/leitura e testes;
layout/navegação; ligação da lista persistida e estados vazio/erro; validação manual.
Não incluir escrita de Meetings pela interface, importação, gravação ou transcrição.

## Complexity Tracking

Sem exceções constitucionais ou complexidade adicional a justificar.
