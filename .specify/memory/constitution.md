<!--
Sync Impact Report — material temporário de revisão; remover antes do commit.
Versão: scaffold sem versão adotada → 1.0.0 (adoção inicial).
Princípios preenchidos:
- PRINCIPLE_1 → I. Processamento local e autonomia offline
- PRINCIPLE_2 → II. Captura durável antes da transcrição
- PRINCIPLE_3 → III. Origem preservada e resultados reconstruíveis
- PRINCIPLE_4 → IV. Transcrição fiel aos limites do áudio
- PRINCIPLE_5 → V. Simplicidade e validação no Mac do usuário
Seções preenchidas: Escopo e decisões técnicas; Fluxo de desenvolvimento e validação;
Governance. Nenhuma seção removida; templates dependentes não alterados.
Pendências: PRODUCT.md referencia GLOSSARY.md, ausente na adoção desta constituição.
Nenhum placeholder adiado. Motor, modelo, requisitos mínimos e formatos de áudio
continuam decisões técnicas de planejamento, conforme PRODUCT.md.
-->

# Meeting Record Constitution

## Core Principles

### I. Processamento local e autonomia offline

O fluxo principal DEVE funcionar offline após o setup e o download explícito dos modelos.
Áudios, transcrições e processamento DEVEM permanecer no Mac, sem exigir conta ou serviço
de nuvem. O download DEVE informar tamanho e progresso. O app DEVE permitir instalação
e uso por outras pessoas sem caminhos, credenciais ou configuração específicos do autor.
Essas regras garantem privacidade e autonomia no uso diário.

### II. Captura durável antes da transcrição

A captura DEVE ter prioridade sobre o processamento de texto. Atrasos na transcrição DEVEM
gerar uma fila pendente visível, mantendo a gravação e a navegação disponíveis. Áudio e texto
DEVEM ser persistidos progressivamente. Ao parar, o app DEVE finalizar o áudio e concluir
os blocos pendentes antes de declarar a transcrição concluída, sem exigir uma segunda
transcrição integral. Após fechamento inesperado, DEVE recuperar o conteúdo persistido,
marcar a Recording como interrompida e permitir retomar o processamento pendente.

### III. Origem preservada e resultados reconstruíveis

Cada Meeting DEVE manter seus Inputs e uma Transcription unificada derivada deles.
O primeiro Input DEVE fixar a origem Recording ou Import; a Meeting DEVE aceitar novos
Inputs apenas dessa origem. Cada Input DEVE preservar seu original, seu resultado e a
proveniência dos trechos. A unificação DEVE respeitar a ordem definida em PRODUCT.md,
permitir reconstrução sem repetir processamento ainda válido e refletir a exclusão de Inputs.
O conteúdo DEVE permanecer local até exclusão manual; excluir uma Meeting DEVE exigir
confirmação e remover todos os seus Inputs, áudios e transcrições.

### IV. Transcrição fiel aos limites do áudio

Uma Recording DEVE preservar separadamente microfone e áudio do computador, rotulados
Me e Other. Esses rótulos DEVEM representar fontes, sem alegar identidades verificadas.
Falas sobrepostas DEVEM ser preservadas e ordenadas pelo horário de início. Importações
DEVEM preservar nomes de falantes e timestamps existentes; áudio sem identificação DEVE
ser transcrito sem inventar identidades. Português, espanhol, inglês e alternância entre eles
DEVEM fazer parte da validação. Texto incremental DEVE comunicar atraso e processamento
pendente; a conclusão DEVE ocorrer somente quando todos os Inputs terminarem de processar.

### V. Simplicidade e validação no Mac do usuário

A primeira versão DEVE atender macOS em Apple Silicon com um único motor e modelo
validados. Escolhas de tecnologia DEVEM se apoiar em evidência dos fluxos do produto,
incluindo exemplos reais de áudio, em vez de tratar candidatos como decisões confirmadas.
A solução DEVE implementar o menor conjunto necessário aos critérios de aceitação de
PRODUCT.md. Novas abstrações e dependências DEVEM ter uma necessidade concreta registrada
no plano técnico. Requisitos de instalação DEVEM ser reproduzíveis em outro Mac compatível.

## Escopo e decisões técnicas

PRODUCT.md define o comportamento e os critérios de aceitação da versão inicial. Cada
Meeting representa uma reunião distinta; criá-la DEVE gerar um registro vazio renomeável
sem iniciar captura. Recording DEVE aceitar várias gravações sequenciais, com apenas uma
Meeting em gravação por vez. Inputs e Transcription DEVEM manter suas funções de materiais
de origem e resultado unificado.

A primeira versão inclui importação de `.txt`, `.vtt` e áudio, além de leitura e cópia da
transcrição. Resumos, extração de tarefas, diarização, edição de transcrições ou falantes,
reprodução sincronizada, sincronização em nuvem e outras plataformas permanecem fora do
escopo inicial. Ampliações DEVEM ser explícitas na especificação e em PRODUCT.md; quando
afetarem um princípio, DEVEM passar também por emenda constitucional.

Motor e modelo, formatos de áudio importáveis, intervalo dos blocos, latência, memória,
Mac de referência e requisitos mínimos DEVEM ser definidos na avaliação técnica.
Whisper e Parakeet são candidatos. O planejamento DEVE registrar medições e a justificativa
da escolha antes de apresentar esses pontos como requisitos confirmados.

## Fluxo de desenvolvimento e validação

Especificações e planos DEVEM identificar os princípios aplicáveis e ligar o trabalho aos
critérios de aceitação de PRODUCT.md. Termos de domínio DEVEM seguir as definições do
produto e de GLOSSARY.md quando esse arquivo estiver disponível. Divergências ou decisões
em aberto DEVEM ser registradas antes de implementar o comportamento afetado.

Mudanças em captura, persistência, recuperação ou unificação DEVEM incluir verificação
reproduzível dos riscos afetados. Antes de declarar a primeira versão aceita, a validação
DEVE demonstrar os fluxos completos de PRODUCT.md, incluindo duas faixas com sobreposição,
fila após parar, recuperação de interrupção, importação, exclusão e operação offline após
setup. Qualidade multilíngue e impacto do processamento na captura DEVEM ser medidos com
áudios reais no Mac de referência. Os resultados DEVEM registrar ambiente, procedimento,
observações e limitações, distinguindo evidência de hipóteses ainda não verificadas.

## Governance

Esta constituição rege os compromissos do projeto; PRODUCT.md detalha seu comportamento.
Em caso de conflito, a mudança DEVE explicitar a divergência e obter uma decisão do
responsável pelo projeto antes de alterar o compromisso afetado. Toda revisão de
especificação, plano e implementação DEVE verificar conformidade com estes princípios.

Emendas DEVEM registrar motivação, princípios afetados, impacto sobre dados e fluxos
existentes e migração quando aplicável. A aprovação cabe ao responsável pelo projeto.
A versão DEVE seguir MAJOR.MINOR.PATCH: MAJOR para remoção ou redefinição incompatível de
princípios; MINOR para novos princípios, seções ou ampliação material de orientação;
PATCH para esclarecimentos sem mudança de compromisso. Toda emenda DEVE atualizar a data
de alteração e o relatório de impacto. A data de ratificação original DEVE ser preservada.

**Version**: 1.0.0 | **Ratified**: 2026-11-20 | **Last Amended**: 2026-11-20
