# Fase 34 — Nota Interna de Transferência Não Renderizada na Timeline do Dashboard (Preview)

**Status**: Preview de baixa confiança — achado **único**, registrado originalmente como um efeito
colateral fora de escopo da Fase 32, nunca reproduzido de novo (confirmado com o operador nesta
sessão) e **sem causa raiz identificada**. Diferente das demais fases preview deste roadmap (29, 32,
33, 35, 36), que têm causa raiz confirmada por leitura de código/eliminação de caminhos, esta fase
só tem: (a) um sintoma visual confirmado por um operador, uma única vez; (b) uma checagem de dados
que descarta a hipótese mais óbvia (mensagem ausente/corrompida no banco), sem apontar a causa real.
Não avançar para `/speckit-specify` sem reprodução nova ou evidência adicional — ver "Estado da
evidência" abaixo.
**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depends on**: Fase 32 (`32-contact-memory-handoff-pretext-guardrail/spec-preview.md`) — onde este
achado foi originalmente registrado como "candidato a Fase 34" (achado adicional, fora do escopo
principal daquela fase). Fase 17 (`17-observability-and-handoff-notice/spec77.md`) — instrumentação
OTel que pode conter um trace da execução, se um provider estiver configurado no momento da próxima
investigação (ver evidência abaixo, provider ativo não identificado à época).

---

## Contexto: nota privada de transferência confirmada íntegra no banco, mas ausente da tela

Achado durante a validação da Fase 32 (conversation_id 71392, display_id 45006, conta 2 "Dens
Odontologia", Scout "Vitória"): a nota privada automática de transferência
(`HandoffService#create_transfer_note`, `custom/app/services/custom/scout/handoff_service.rb:49-56`)
**não apareceu na timeline da conversa 45006** no dashboard do Chatwoot, mesmo após hard reload —
sintoma confirmado visualmente pelo operador, que já tinha visto esse mesmo tipo de nota renderizar
corretamente em outras conversas (antes e depois da mensagem pública de handoff).

## Estado da evidência (reproduzido de `32-contact-memory-handoff-pretext-guardrail/spec-preview.md`,
## §"Achado adicional", único registro existente deste problema)

1. **Lado dos dados, descartado como causa**: `Message#id 1407500` existe no banco, com
   `conversation_id`/`account_id`/`inbox_id` corretos, `private: true`, conteúdo íntegro,
   `status: "read"` (igual à mensagem pública vizinha) — nada de soft-delete ou inconsistência
   visível.
2. **Inversão de timestamp checada e descartada como explicação exclusiva**: uma amostra de
   **todas as 4 notas de transferência existentes no sistema** (incluindo a da conversa 44877, que o
   operador confirma ter visto renderizar) mostrou o mesmo padrão em 4/4 casos — a nota privada tem
   `created_at` 1–3s **anterior** à mensagem pública vizinha, apesar de ser criada depois no código
   (`HandoffService#perform`: mensagem pública primeiro, nota privada depois). Essa inversão é
   sistêmica e normal neste fluxo (não uma anomalia exclusiva desta conversa) — logo, sozinha, não
   explica por que só esta não renderizou.
3. **OTel**: `ChatwootApp.otel_enabled?` retornava `true` em produção à época, mas sem `LANGFUSE_*`
   configurado via ENV — o provider ativo de OTel não foi identificado naquela investigação. Se
   algum provider estiver configurado numa próxima investigação, pode haver um trace da execução
   (Fase 17).
4. **Nenhuma reprodução ao vivo** foi feita — a sessão que encontrou o problema não tinha DevTools
   aberto nem acesso para reproduzir em tempo real; a causa mais provável apontada foi do lado do
   frontend (Vue), mas isso é uma suspeita, não uma conclusão.

**Desde então, o problema não voltou a se manifestar** (confirmado pelo operador nesta sessão) —
não há uma segunda ocorrência, nem em produção nem em simulação, para corroborar ou refinar a
suspeita de frontend.

## Por que isto fica como preview de baixa confiança, não como bug pronto para especificar

As demais fases preview deste roadmap (29, 32, 33, 35, 36) chegam à causa raiz por leitura direta de
código/log e eliminação sistemática dos caminhos possíveis. Aqui, o único caminho eliminado foi o
mais óbvio (dado ausente/corrompido) — não há eliminação equivalente do lado do frontend: nenhum
componente Vue foi identificado, nenhum log de console/network foi capturado, nenhum padrão foi
comparado entre "notas que renderizam" vs. "notas que não renderizam" além do timestamp (já
descartado). Especificar uma correção agora seria adivinhação, não diagnóstico.

## Próximos passos de diagnóstico (não uma decisão de desenho — pré-requisito para uma)

1. Reproduzir com DevTools aberto (Network + Console) numa conversa nova que gere handoff, olhando
   especificamente se a mensagem privada chega via WebSocket/ActionCable (`message.created` já era
   emitido corretamente no rádio-log da Fase 35/36, então o backend broadcast não é o suspeito óbvio
   — mas vale confirmar o payload chega ao cliente) e se ela é descartada/filtrada na renderização.
2. Revisar como o componente de lista de mensagens do dashboard trata `private: true` combinado com
   `sender_type: null` (mensagens geradas pelo sistema, sem usuário/bot autor) — hipótese mais
   concreta levantada na Fase 32, ainda não verificada por leitura de código Vue.
3. Se reproduzir de novo, capturar: `Message#id`, conversation/display_id, screenshot/HAR do
   DevTools, e comparar contra uma nota de transferência equivalente que renderizou normalmente na
   mesma sessão — para isolar a variável real.
4. Sem uma nova ocorrência reproduzível, considerar rebaixar este item para o backlog (não pronto
   para implementação) em vez de mantê-lo no roadmap ativo do Scout.

## Fora de escopo desta fase (preview)

- Qualquer mudança de código — não há causa raiz identificada para corrigir.
- Repetir a investigação de dados já feita na Fase 32 (mensagem íntegra, inversão de timestamp
  sistêmica) — já concluída, não precisa ser refeita, só referenciada.

## Testes (rascunho)

- Não aplicável até haver causa raiz confirmada. Quando (e se) reproduzido e diagnosticado, este
  documento deve ser atualizado com um `it` de regressão cobrindo o comportamento real identificado
  (provavelmente em um spec de componente Vue do dashboard, não em `custom/spec/`).

## Critérios de aceite (rascunho, só valem se a fase avançar — e só depois de reprodução)

- A nota privada automática de transferência (`HandoffService#create_transfer_note`) renderiza na
  timeline de toda conversa, de forma consistente — sem depender de hard reload ou de qualquer
  condição de corrida observada.

---

> **Nota**: Este documento não é uma investigação nova — é o registro formal de um achado que já
> existia como "achado adicional (candidato a Fase 34)" no texto da Fase 32
> (`32-contact-memory-handoff-pretext-guardrail/spec-preview.md`, seção "Achado adicional (fora do
> escopo principal — candidato a fase futura)"), agora movido para seu próprio arquivo de fase por
> pedido do operador, sem nenhuma evidência nova coletada nesta sessão — a data de origem, o
> `Message#id`, os IDs de conversa/conta e a checagem de timestamps são os mesmos já documentados lá.
> Confirmado com o operador que o sintoma não se repetiu desde então. Diferente das demais fases
> preview do roadmap, esta permanece **sem causa raiz** — os "próximos passos de diagnóstico" acima
> são pré-requisito para qualquer especificação completa, não uma decisão de desenho já tomada. Ver
> `spec60.md` §11.
