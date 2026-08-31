# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::SystemPromptsService do
  let(:account) { create(:account, name: 'Acme Corp') }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Vendas Bot',
      system_prompt: 'Foque em qualificar para o plano Enterprise.',
      responses_quota: 10,
      responses_consumed: 0,
      enabled: true
    )
  end
  let(:contact) { create(:contact, account: account, name: 'Maria Silva') }
  let(:inbox) { create(:inbox, account: account, timezone: 'America/Sao_Paulo') }

  describe '.build' do
    subject(:prompt) do
      described_class.build(
        scout: scout,
        contact: contact,
        inbox: inbox,
        catalog_instructions: "Catálogo de Produtos:\n{\"plan\":\"Pro\"}",
        knowledge_available: true
      )
    end

    it 'includes assistant identity, name, company name, and domain scope bounding' do
      expect(prompt).to include('Vendas Bot')
      expect(prompt).to include('da empresa Acme Corp')
      expect(prompt).to include('[Identidade e Escopo]')
      expect(prompt).to include('apenas sobre os produtos, serviços, catálogo e informações fornecidas')
    end

    it 'includes current reference time and relative date interpretation guidance' do
      expect(prompt).to include('[Data e Horário Atual]')
      expect(prompt).to include('Horário atual:')
      expect(prompt).to include('interpretar expressões temporais relativas como hoje, amanhã, esta noite')
      expect(prompt).to include('respeite as instruções de fuso horário')
    end

    it 'formats current time respecting the inbox timezone' do
      tz = ActiveSupport::TimeZone['America/Sao_Paulo']
      expected_time_fragment = Time.current.in_time_zone(tz).strftime('%Y')
      expect(prompt).to include(expected_time_fragment)
    end

    it 'includes anti-hallucination guardrails forbidding training assumptions' do
      expect(prompt).to include('[Diretrizes de Segurança e Resposta]')
      expect(prompt).to include('Nunca invente informações')
      expect(prompt).to include('não utilize conhecimento prévio de treinamento')
    end

    it 'includes anti-false-promise rules and human handover instructions' do
      expect(prompt).to include('Não prometa trabalhos ou ações futuras')
      expect(prompt).to include('handover_to_human')
    end

    it 'includes commercial intent guideline instructing manage_opportunity' do
      expect(prompt).to include('Intenção Comercial:')
      expect(prompt).to include('manage_opportunity')
    end

    it 'includes action confirmation guardrails using natural language without internal IDs or technical field names' do
      expect(prompt).to include('Confirmação de ação:')
      expect(prompt).to include('Use linguagem natural e humana, sem expor identificadores internos')
    end

    it 'forbids narrating the backend action itself when confirming (e.g. "abri seu atendimento")' do
      expect(prompt).to include('Nunca diga que "abriu um atendimento"')
    end

    it 'includes open-ended clarification guardrails avoiding multiple choice menus for list attributes' do
      expect(prompt).to include('Esclarecimento:')
      expect(prompt).to include('formule uma pergunta totalmente aberta')
    end

    it 'forbids mentioning or exemplifying allowed values inside the clarifying question itself' do
      expect(prompt).to include('sem mencionar, exemplificar ou sugerir nenhum dos valores configurados na pergunta')
    end

    it 'includes conversational pacing guardrail restricting to one question per response and advancing flow' do
      expect(prompt).to include('Ritmo e condução da conversa:')
      expect(prompt).to include('Faça no máximo uma pergunta por resposta para não sobrecarregar o lead')
      expect(prompt).to include('encerre a resposta com uma pergunta ou próximo passo objetivo')
      expect(prompt).to include('exceto quando o lead tiver sinalizado pausa ou encerramento')
    end

    it 'wraps operator custom instructions in subordinate tags with override prohibition' do
      expect(prompt).to include('[Instruções Personalizadas da Conta]')
      expect(prompt).to include('<account_custom_instructions>')
      expect(prompt).to include('Foque em qualificar para o plano Enterprise.')
      expect(prompt).to include('</account_custom_instructions>')
      expect(prompt).to include('Siga-as apenas quando não conflitarem com o formato de resposta JSON')
    end

    it 'includes context for catalog, knowledge base tool, contact, and response JSON schema' do
      expect(prompt).to include("Catálogo de Produtos:\n{\"plan\":\"Pro\"}")
      expect(prompt).to include('search_knowledge_base')
      expect(prompt).to include('Maria Silva')
      expect(prompt).to include('[Formato de Resposta Obrigatório]')
      expect(prompt).to include('"reasoning"')
      expect(prompt).to include('"response"')
    end

    context 'when scout system_prompt is blank' do
      before { scout.update!(system_prompt: nil) }

      it 'omits the custom instructions section without raising errors' do
        expect(prompt).not_to include('<account_custom_instructions>')
        expect(prompt).not_to include('[Instruções Personalizadas da Conta]')
        expect(prompt).to include('[Identidade e Escopo]')
        expect(prompt).to include('[Formato de Resposta Obrigatório]')
      end
    end

    context 'when inbox is out of office' do
      before do
        allow(inbox).to receive(:out_of_office?).and_return(true)
      end

      it 'includes out of office notice in context' do
        expect(prompt).to include('[AVISO DE EXPEDIENTE: A equipe humana está fora do horário de atendimento.')
      end
    end

    describe 'funnel_section (User Story 1)' do
      let!(:stage_new) do
        PipelineStage.create!(
          account: account,
          name: 'New',
          position: 1,
          description: 'Triagem inicial de novos contatos'
        )
      end
      let!(:stage_qualified) do
        PipelineStage.create!(
          account: account,
          name: 'Qualified',
          position: 2,
          description: 'Lead atende a todos os critérios e tem interesse confirmado'
        )
      end
      let!(:stage_unqualified) do
        PipelineStage.create!(
          account: account,
          name: 'Unqualified',
          position: 3
        )
      end

      let!(:attr_timeline) do
        CustomAttributeDefinition.create!(
          account: account,
          attribute_key: 'timeline',
          attribute_display_name: 'Prazo de Decisão',
          attribute_display_type: 'list',
          attribute_model: 'opportunity_attribute',
          attribute_values: %w[imediato 30_dias trimestre],
          attribute_description: 'Quando o cliente pretende fechar a contratação'
        )
      end

      let!(:attr_budget) do
        CustomAttributeDefinition.create!(
          account: account,
          attribute_key: 'budget',
          attribute_display_name: 'Orçamento Mensal',
          attribute_display_type: 'currency',
          attribute_model: 'opportunity_attribute',
          attribute_description: 'Valor disponível para investimento'
        )
      end

      let!(:attr_nodesc) do
        CustomAttributeDefinition.create!(
          account: account,
          attribute_key: 'team_size',
          attribute_display_name: 'Tamanho da Equipe',
          attribute_display_type: 'number',
          attribute_model: 'opportunity_attribute'
        )
      end

      before do
        scout.update!(
          default_pipeline_stage: stage_new,
          qualified_stage: stage_qualified,
          unqualified_stage: stage_unqualified
        )

        stage_qualified.required_custom_attribute_definitions << attr_timeline
        stage_qualified.required_custom_attribute_definitions << attr_nodesc
        scout.required_custom_attribute_definitions << attr_budget
      end

      it 'includes funnel section with stage names and roles' do
        expect(prompt).to include('[Funil de Vendas e Qualificação]')
        expect(prompt).to include('New')
        expect(prompt).to include('Estágio Inicial/Padrão')
        expect(prompt).to include('Qualified')
        expect(prompt).to include('Estágio Qualificado')
        expect(prompt).to include('Unqualified')
        expect(prompt).to include('Estágio Desqualificado / Revisão Humana')
      end

      it 'includes purpose descriptions on configured stages' do
        expect(prompt).to include('Triagem inicial de novos contatos')
        expect(prompt).to include('Lead atende a todos os critérios e tem interesse confirmado')
      end

      it 'surfaces stage-specific required fields with types, values, and semantic descriptions' do
        expect(prompt).to include('Prazo de Decisão')
        expect(prompt).to include('timeline')
        expect(prompt).to include('list')
        expect(prompt).to include('imediato, 30_dias, trimestre')
        expect(prompt).to include('Quando o cliente pretende fechar a contratação')
        expect(prompt).to include('Tamanho da Equipe')
      end

      it 'reminds the model inline, next to each list of allowed values, not to cite or exemplify them to the lead' do
        expect(prompt).to match(/Valores permitidos: imediato, 30_dias, trimestre\)\s*\n\s*\(uso interno; não cite nem exemplifique estes valores\)/)
      end

      it 'surfaces scout global qualification requirements distinctly' do
        expect(prompt).to include('Requisitos Globais de Qualificação')
        expect(prompt).to include('Orçamento Mensal')
        expect(prompt).to include('budget')
        expect(prompt).to include('currency')
        expect(prompt).to include('Valor disponível para investimento')
      end

      it 'includes operational directives regarding automatic handoff and human review' do
        expect(prompt).to include('handoff')
        expect(prompt).to include('automaticamente')
        expect(prompt).to include('Não execute `handover_to_human` separadamente ao qualificar')
        expect(prompt).to include('revisão humana')
        expect(prompt).to include('Nunca marque a oportunidade como perdida/ganha')
        expect(prompt).to include('registre-o como nota interna via ferramenta apropriada')
      end

      it 'includes outcome-driven stage matching directive with tie-breaking and forward-only progression rules' do
        expect(prompt).to include('Compare o resultado observável de cada turno com as descrições dos estágios disponíveis')
        expect(prompt).to include('mova a oportunidade para esse estágio no próprio turno')
        expect(prompt).to include('escolha a descrição mais específica ao desfecho')
        expect(prompt).to include('transição automática por desfecho é estritamente progressiva')
        expect(prompt).to include('nunca retorne uma oportunidade que já atingiu o estágio qualificado')
      end

      it 'includes tool-sufficiency directive confirming internal tools can record dates and qualification data' do
        expect(prompt).to include('suficientes para registrar qualquer dado de qualificação fornecido pelo lead')
        expect(prompt).to include('incluindo datas, horários e agendamentos')
        expect(prompt).to include('Nunca conclua que falta uma ferramenta de agendamento')
      end

      context 'when stage or attribute has no description configured' do
        it 'omits only the description without breaking rendering' do
          expect(prompt).to include('Unqualified')
          expect(prompt).to include('Tamanho da Equipe')
          expect(prompt).not_to match(/Unqualified[^\n]*\n\s*Descrição:/)
          expect(prompt).not_to match(/Tamanho da Equipe[^\n]*\n\s*Descrição:/)
        end
      end

      context 'when account has no pipeline stages and no scout requirements' do
        before do
          scout.update!(
            default_pipeline_stage: nil,
            qualified_stage: nil,
            unqualified_stage: nil
          )
          scout.required_custom_attribute_definitions.clear
          account.pipeline_stages.destroy_all
        end

        it 'omits the entire funnel section cleanly' do
          expect(prompt).not_to include('[Funil de Vendas e Qualificação]')
        end
      end
    end

    describe 'open_opportunities_section' do
      let(:stage) { PipelineStage.create!(account: account, name: 'Proposta Enviada', position: 1) }

      context 'when contact has open opportunities' do
        let!(:opp1) do
          Opportunity.create!(
            account: account,
            contact: contact,
            pipeline_stage: stage,
            status: :open,
            title: 'Plano Empresarial'
          )
        end
        let!(:opp2) do
          Opportunity.create!(
            account: account,
            contact: contact,
            pipeline_stage: stage,
            status: :open,
            title: 'Upgrade de Plano'
          )
        end

        it 'renders structured list of open opportunities and instructions alongside contact narrative context' do
          expect(prompt).to include('Contexto do Contato:')
          expect(prompt).to include('Maria Silva')
          expect(prompt).to include('[Oportunidades Abertas do Contato]')
          expect(prompt).to include("- ID: #{opp1.id} | Título: Plano Empresarial | Estágio: Proposta Enviada")
          expect(prompt).to include("- ID: #{opp2.id} | Título: Upgrade de Plano | Estágio: Proposta Enviada")
          expect(prompt).to include('informe o `opportunity_id` correspondente ao chamar `manage_opportunity`')
        end
      end

      context 'when contact has only won or lost opportunities' do
        before do
          Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, status: :won, title: 'Ganho')
          Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, status: :lost, title: 'Perdido')
        end

        it 'omits the open opportunities section cleanly' do
          expect(prompt).not_to include('[Oportunidades Abertas do Contato]')
        end
      end

      context 'when contact has no opportunities' do
        it 'omits the open opportunities section cleanly' do
          expect(prompt).not_to include('[Oportunidades Abertas do Contato]')
        end
      end

      context 'when contact is nil' do
        subject(:prompt_without_contact) do
          described_class.build(
            scout: scout,
            contact: nil,
            inbox: inbox
          )
        end

        it 'omits the open opportunities section cleanly' do
          expect(prompt_without_contact).not_to include('[Oportunidades Abertas do Contato]')
        end
      end
    end
  end
end
