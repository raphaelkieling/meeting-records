# Evidências — App shell

Data: 2026-11-21. Implementação disponível; aceitação manual integral ainda pendente nos pontos identificados abaixo. Esta entrega não corresponde à versão completa de PRODUCT.md.

## Ambiente

- macOS 27.2.1, build 26B131, arquitetura arm64.
- Xcode 27.2 (27B52), Swift 6.4.2 (swiftlang-6.4.2.1.9).
- Command Line Tools global continua selecionado; comandos usaram `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` sem alterar xcode-select.
- Modelo do chip e memória: consulta por sysctl recusada pelo ambiente isolado; não registrados.
- Executável release inspecionado com vtool: plataforma MACOS, minos 14.0. Não houve execução real em macOS 14.

## Build e testes

Comandos finais, na raiz:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH="$PWD/.build/xcode-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
xcrun swift build --disable-sandbox --cache-path .build/cache --manifest-cache local
xcrun swift test --disable-sandbox --cache-path .build/cache --manifest-cache local
bash scripts/build-app.sh --release
xcrun swift test --disable-sandbox --cache-path .build/cache --manifest-cache local -c release -debug-info-format none
```

- Build debug: PASS com sistema padrão do SwiftPM.
- Bundle debug: PASS; abertura e navegação observadas no macOS.
- Bundle release: PASS com sistema padrão, sem dSYM; abertura observada via cópia de validação.
- XCTest debug final: 8 testes, zero falhas, aproximadamente 0,068 s.
- XCTest release final: 8 testes, zero falhas, aproximadamente 0,059 s.
- Plist e sintaxe bash: PASS.
- Falha de build induzida com executável de compilação de teste: nenhum bundle antigo permaneceu no caminho final. Em seguida o bundle release foi reconstruído com sucesso.

Cobertura reproduzível dos testes:

1. Base nova vazia com user_version 1.
2. Trinta registros, Unicode, nomes repetidos e longos, desempate por ID e reabertura com igualdade integral de valores.
3. Falha de abertura e retry na mesma instância após reparar o diretório.
4. Versão futura rejeitada com arquivo byte a byte preservado.
5. Inicialização com conflito de tabela: rollback, schema e conteúdo mantidos, user_version permanece 0.
6. Schema v1 inválido falha sem apagar dados.
7. Registros inválidos falham em vez de retornar sucesso vazio: UUID inválido, sufixo após NUL, UTF-8 inválido, nome vazio após trim, timestamp nulo ou textual.
8. Override relativo/vazio rejeitado em DEBUG; diretório absoluto resolvido. Em release o override é ignorado.

## Interface observada

Validação por Computer Use, com árvore de acessibilidade e capturas visuais na conversa. A árvore expôs botões, nomes integrais, destino selecionado e foco separadamente. As capturas não foram salvas como arquivos no repositório.

- Bundle normal: Home inicial e Meetings vazia, sem setup adicional; Configurações abre e Home volta com destaque exclusivo.
- Cópia debug de validação em `.build/MeetingRecordValidation.app`, com identificador separado e LSEnvironment apontando MEETING_RECORD_DATA_DIR para `.build/validation-data`. Esse metadado existe somente na cópia ignorada; não está no Info.plist do produto.
- Base temporária inicializada vazia. Com o app encerrado, 30 fixtures Unicode foram inseridas externamente por SQLite, preservando a interface sem CRUD/seed.
- Lista ordenada de 30 linhas exposta pela acessibilidade. Seleções de Meetings diferentes atualizam o detalhe e marcam somente uma linha.
- Rolagem até o fim (valor da barra 1) manteve Home e Configurações fixas. A última Meeting foi selecionada e o nome integral apareceu no detalhe.
- Nomes truncados em linha única na sidebar; nomes completos expostos como labels e help. Detalhe quebra linhas sem sobreposição nas capturas.
- Foco explícito em Home ao abrir. Seta para baixo mudou o foco; Return ativou a Meeting focada. Foco e seleção permaneceram distintos. Tab isoladamente não avançou antes do ajuste explícito de foco; não foi feita uma matriz completa de navegação por Tab após o ajuste.
- Janela reduzida por arraste: duas áreas permaneceram legíveis e sem sobreposição. Tamanho mínimo 720×480 está definido no código; as capturas do controle remoto foram redimensionadas, impedindo confirmar numericamente a dimensão final em pontos.
- Encerrar com Meeting selecionada e reabrir: Home inicial e os 30 registros novamente disponíveis.
- Comparação da base temporária antes/depois de navegar e reabrir: arquivo byte a byte idêntico.
- Cópia debug de erro apontou para `.build/error-data`, que era um arquivo. UI exibiu erro e Tentar novamente, mantendo Configurações utilizável. O arquivo original foi movido para `.build/error-data.original` sem alterar seu conteúdo e foi criado um diretório válido. Retry carregou estado vazio sem reiniciar o app.
- Cópia release recebeu override relativo deliberadamente inválido. Abriu Home com lista vazia sem erro de override, corroborando o teste automatizado de resolução release.
- Nenhum pedido de conta, download de modelo, microfone ou captura foi observado. Inspeção de fontes confirma ausência de rede e APIs de áudio. A rede do Mac não foi desligada para um teste físico offline.

## Matriz de requisitos

| Requisito | Evidência | Resultado |
|---|---|---|
| FR-001 | Bundle debug/release abre duas áreas; binário arm64 e minos 14.0 | PASS no Mac atual; macOS 14 não executado |
| FR-002 | Captura ao fim da lista mantém destinos fixos acima de Meetings | PASS |
| FR-003 | Abertura/reabertura em Home; títulos e mensagens simples | PASS |
| FR-004 | Seleções de Home/Configurações/Meetings e árvore com um destino ativo | PASS nos fluxos observados |
| FR-005 | Meetings selecionáveis, nome integral no detalhe, sem captura | PASS |
| FR-006 | Vazio, 30 linhas, rolagem, truncamento, help/label | PASS |
| FR-007 | Duas áreas compactas, linhas únicas e janela reduzida | PASS visual; dimensão mínima exata pendente |
| FR-008 | Sem rede/áudio/conta nas fontes ou prompts na execução | PASS estrutural; desconexão física não testada |
| FR-009 | Setas/Return, foco visível e labels/selected no AX | Parcial: leitura falada por VoiceOver pendente |
| FR-010 | XCTest, fixtures e erro/retry na UI sem perda | PASS |
| SC-001 | Abertura direta em Home; não exige setup de produto | PASS observado; desconexão física não testada |
| SC-002 | Mudanças de destino corretas e seleção exclusiva nos fluxos exercitados | PASS observado |
| SC-003 | Último item aberto após rolagem; nomes sem sobreposição | PASS |
| SC-004 | Foco e ativação por teclado exercitados | Parcial: percorrer todos os destinos só por teclado pendente |
| SC-005 | Layout reduzido mantém duas áreas; mínimo definido em código | Parcial: confirmar 720×480 pt exatos e comparar com referência original |
| SC-006 | Igualdade integral de 30 registros em testes; base UI byte a byte preservada | PASS |

## Limites e verificações restantes

- VoiceOver: sem validação de saída falada; apenas semântica AX inspecionada. Não alterar preferências globais para simular esse aceite.
- Percorrer todos os 32 destinos exclusivamente por teclado e repetir a navegação com conexão fisicamente indisponível.
- Confirmar tamanho mínimo exato em pontos. A imagem original de referência não consta como arquivo no workspace; a revisão usou o contrato de duas áreas e densidade.
- Meta técnica de 100 ms: não medida. Tempo de chamada da automação inclui transporte e snapshots e não representa tempo de renderização; não foi usado como benchmark.
- macOS 14, modelo exato do chip e memória não foram validados neste ambiente. Nenhuma compatibilidade de runtime além do Mac atual é alegada.

T010, T017 e T019 permanecem abertas em tasks.md para a parte restante da aceitação manual. As implementações e verificações automatizadas correspondentes estão prontas. T020 registra essa matriz e não declara aceite integral da feature.

## Ajustes de implementação

- A conexão SQLite é aberta e fechada dentro de cada operação do actor, em vez de mantida até deinit. Isso mantém os ponteiros confinados, simplifica cleanup e permite retry sem reter conexão inválida.
- Meetings usa ScrollView + VStack de botões nativos em vez de List; para os 30 registros do escopo, mantém todos os destinos disponíveis ao foco e a seleção única compartilhada com os controles fixos. Não há virtualização adicional.
- O script mantém caches locais e desabilita apenas o sandbox interno de execução do manifesto conhecido, pois sandbox-exec aninhado não é permitido neste ambiente. Não há dependências remotas.
- O release local omite informações de debug para evitar a operação dsymutil recusada pelo ambiente. Debug continua com símbolos.
- Avisos do SwiftPM sobre caches globais inacessíveis persistem, sem impedir build/testes com cache local. O sistema padrão de build funciona com o Xcode selecionado por comando; não há opção de build deprecated no script final.
- Sem Inputs, transcrições, CRUD, áudio, seed de produção, serviço de rede, instalação ou publicação.
