# Fase 15 — Indicadores Visuais do Scout (Preview)

**Status**: Preview — escopo movido da Fase 10 (`../10-in-conversation-ui/spec68.md`) nesta
segunda passada de brainstorming, para permitir que a Fase 10 ficasse reduzida a um mecanismo de
backend testável (handoff automático em intervenção humana) sem bloquear em decisões de UI ainda
não amadurecidas. Este documento existe para ancorar uma sessão de brainstorming dedicada, não
para prescrever arquitetura ou implementação.
**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depends on**: Phase 09 (In-Conversation Handoff — `../10-in-conversation-ui/spec68.md`, o
mecanismo de backend que esta fase daria visibilidade).

---

## Por que foi adiado

O objetivo imediato é testar o MVP do produto — Scout conectado a conversas reais, liberando a
conversa corretamente quando um humano intervém — sem esperar por decisões de design visual ainda
não maduras. Ver `../10-in-conversation-ui/spec68.md` para o mecanismo que já ficou pronto.

## O que foi registrado, sem solução ainda

1. **Badge de status na conversa** (`active`/`handed_off`, e possivelmente outros estados)
   indicando se o Scout está engajado na conversa atual. Já havia um desenho técnico razoavelmente
   maduro (computar via `inbox.scout&.enabled?` + `status == 'pending'`, expor via
   `Custom::Concerns::Conversation#scout_status`, jbuilder + `EventDataPresenter` mod, componente
   no header ao lado de `SLACardLabel`) — descartado nesta passada junto com o resto do escopo
   visual, não por problema técnico no desenho em si. Pode ser retomado como ponto de partida.
2. **Link/indicador para a Oportunidade/Kanban associada à conversa atual**. Investigação nesta
   sessão mostrou que já existe uma seção "Oportunidades" no painel de contato
   (`app/javascript/dashboard/routes/dashboard/conversation/ContactOpportunities.vue`), mas com
   diferenças relevantes: lista **todas** as oportunidades do contato (não só a da conversa atual),
   fica **recolhida por padrão** (último item de 11 no accordion lateral), e ao clicar abre um
   **modal de edição**, não navega para o card no board do Kanban. Se uma fase futura decidir que
   ainda vale a pena um elemento novo aqui, essas diferenças (escopo por conversa, visibilidade
   imediata, navegação direta) são o que justificaria não reaproveitar a seção existente como está.
3. **Indicador comparando o resultado do Scout com o desempenho de SDRs humanos** — ideia nova,
   levantada durante o brainstorming desta fase, **não desenvolvida**. Nada foi definido ainda:
   o que conta como "resultado" (taxa de qualificação? tempo até qualificar? taxa de
   fechamento/won?), em que tela apareceria, se é por conversa, por Scout, ou um relatório
   agregado separado. Precisa de uma sessão de brainstorming própria antes de virar escopo.

## Fora de escopo deste preview

- Qualquer decisão de arquitetura, componente ou layout — este documento só registra o que ficou
  pendente e por quê.
- Qualquer mudança na seção "Oportunidades" do painel de contato — permanece como está até uma
  decisão explícita numa fase futura.
