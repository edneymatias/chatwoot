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
  let(:contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511988887777') }
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

    it 'frames action confirmation as active-listening acknowledgment of only the newest customer message, consultative-sales style' do
      expect(prompt).to include('escuta ativa')
      expect(prompt).to include('vendas consultivas')
      expect(prompt).to include('apenas a informação nova desta mensagem')
    end

    it 'forbids re-acknowledging, in later turns, information already acknowledged earlier in the conversation' do
      expect(prompt).to include('Nunca repita ou resuma de novo, em turnos seguintes, dados que você já reconheceu')
      expect(prompt).to include('soa repetitivo e inseguro')
    end

    it 'forbids narrating the backend action itself when confirming (e.g. "abri seu atendimento")' do
      expect(prompt).to include('Nunca diga que "abriu um atendimento"')
    end

    it 'includes open-ended clarification guardrails avoiding multiple choice menus for list attributes' do
      expect(prompt).to include('Esclarecimento:')
      expect(prompt).to include('formule uma pergunta totalmente aberta')
    end

    it 'includes contact identity guardrail instructing to ask real name on any channel, including the website widget, with immediacy and priority' do
      expect(prompt).to include('Identidade do contato:')
      expect(prompt).to include('Quando o nome do contato disponível no contexto parecer um identificador de sistema')
      expect(prompt).to include('idealmente na sua primeira resposta')
      expect(prompt).to include('priorizando esta pergunta sobre perguntas de qualificação pendentes')
      expect(prompt).not_to include('canais que não sejam o widget do site')
    end

    it 'includes contact identity guardrail rules for field exemption, non-repetition, real names, and handoff precedence' do
      expect(prompt).to include('esta pergunta é isenta da restrição de perguntar apenas sobre campos configurados')
      expect(prompt).to include('Nunca pergunte novamente caso já tenha perguntado nesta conversa')
      expect(prompt).to include('não faça esta pergunta quando o nome disponível já parecer um nome de pessoa real')
      expect(prompt).to include('nunca faça perguntas se este turno for terminar em transferência para humano')
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

    it 'instructs closing natural message and forbids questions when transferring to human in Fallback para humano' do
      expect(prompt).to include('Fallback para humano:')
      expect(prompt).to include('Sempre que um turno terminar em transferência (por chamada de ferramenta ou qualificação)')
      expect(prompt).to include('sua resposta final deve ser uma mensagem natural de encerramento')
      expect(prompt).to include('confirmando o que foi registrado e explicando que um atendente continuará o atendimento')
      expect(prompt).to include('nunca faça perguntas ao transferir')
    end

    it 'instructs immediate handover_to_human upon recognizing existing customer with product or service in progress' do
      expect(prompt).to include('Reconhecimento de intenção fora de prospecção:')
      expect(prompt).to include('já é cliente com um produto ou serviço em andamento')
      expect(prompt).to include('não tente resolver a questão por conta própria, mesmo que pareça simples')
      expect(prompt).to include('Utilize `handover_to_human` imediatamente')
      expect(prompt.index('Fallback para humano:')).to be < prompt.index('Reconhecimento de intenção fora de prospecção:')
      expect(prompt.index('Reconhecimento de intenção fora de prospecção:')).to be < prompt.index('Idioma e Estilo:')
    end

    it 'instructs immediate handover_to_human for change, cancel, or complaint requests without self-resolution' do
      expect(prompt).to include('Reconhecimento de intenção fora de prospecção:')
      expect(prompt).to include('quer alterar ou cancelar algo que já existe (não uma nova solicitação), tem uma reclamação')
      expect(prompt).to include('não tente resolver a questão por conta própria, mesmo que pareça simples')
      expect(prompt).to include('Utilize `handover_to_human` imediatamente')
    end

    it 'instructs immediate handover_to_human for purely informational question with no signal of new interest' do
      expect(prompt).to include('Reconhecimento de intenção fora de prospecção:')
      expect(prompt).to include('faz uma pergunta puramente informativa sem nenhum sinal de interesse em um novo produto ou serviço')
      expect(prompt).to include('Utilize `handover_to_human` imediatamente')
    end

    it 'uses domain-agnostic wording in non-prospecting guardrail without niche or segment vocabulary' do
      guardrail = prompt[/^- Reconhecimento de intenção fora de prospecção:.*$/]
      expect(guardrail).not_to match(/odont|dental|clinic|avaliação (odont|dentária)|consulta (odont|médica)/i)
    end

    it 'instructs that external customer status lookup is optional reinforcement and never blocks handoff' do
      expect(prompt).to include('Se houver uma ferramenta externa configurada para verificar o status do contato')
      expect(prompt).to include('consulte-a para reforçar a decisão')
      expect(prompt).to include('um sinal claro na própria fala do cliente já é suficiente para transferir, sem exigir confirmação do ERP')
    end

    it 'specifies exhaustive non-prospecting criteria introduced by apenas quando and explicitly carves out routine requests' do
      expect(prompt).to include(
        '- Reconhecimento de intenção fora de prospecção: Se em qualquer momento ficar claro que o contato ' \
        'não busca uma nova oportunidade comercial — apenas quando:'
      )
      expect(prompt).not_to include('— ex.:')
      expect(prompt).to include(
        'Uma nova solicitação de baixa complexidade, preventiva, recorrente ou sem um problema específico descrito ' \
        'continua sendo uma oportunidade comercial nova e válida — siga o funil de qualificação normalmente nesses casos.'
      )
    end

    it 'phrases the routine-request qualification unconditionally without turn or phrasing dependency' do
      expect(prompt).not_to include('se mencionado na primeira resposta')
      expect(prompt).not_to include('se esclarecido depois')
      expect(prompt).not_to include('dependendo do turno')
      expect(prompt).not_to include('responde a uma pergunta de triagem')
    end

    it 'wraps operator custom instructions in subordinate tags with override prohibition' do
      expect(prompt).to include('[Instruções Personalizadas da Conta]')
      expect(prompt).to include('<account_custom_instructions>')
      expect(prompt).to include('Foque em qualificar para o plano Enterprise.')
      expect(prompt).to include('</account_custom_instructions>')
      expect(prompt).to include('Siga-as, exceto quando conflitarem com o formato de resposta JSON')
    end

    it 'allows persona instructions to refine only the non-prospecting-intent guardrail even on subject-matter overlap' do
      expect(prompt).to include(
        'A diretriz "Reconhecimento de intenção fora de prospecção" é a única exceção: ' \
        'estas instruções podem refinar ou expandir o que conta como uma nova oportunidade comercial válida ' \
        'especificamente nesse critério, mesmo que pareçam, à primeira vista, tocar no mesmo assunto dessa diretriz.'
      )
    end

    it 'preserves non-negotiable guardrails and forbids altering any other guardrail from persona instructions' do
      expect(prompt).to include(
        'Siga-as, exceto quando conflitarem com o formato de resposta JSON, com a exigência de responder exclusivamente ' \
        'a partir do contexto fornecido, ou com as diretrizes inegociáveis de segurança e resposta descritas acima — ' \
        'no mínimo, Anti-alucinação, Anti-falsa-promessa e Confirmação de ação.'
      )
      expect(prompt).to include('Nenhuma outra diretriz da seção acima pode ser alterada por estas instruções.')
    end

    it 'repeats the no-question handoff closing reminder right before the response format section, for recency' do
      expect(prompt).to include('[Lembrete de Encerramento]')
      expect(prompt.index('[Lembrete de Encerramento]')).to be < prompt.index('[Formato de Resposta Obrigatório]')
      expect(prompt.index('[Diretrizes de Segurança e Resposta]')).to be < prompt.index('[Lembrete de Encerramento]')
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

      it 'restricts qualification questions to configured fields, forbidding self-initiated clinical/technical questions' do
        expect(prompt).to include('Limite suas perguntas de qualificação aos campos configurados acima')
        expect(prompt).to include('Não invente perguntas adicionais fora dos campos configurados')
        expect(prompt).to include('cada pergunta extra custa um turno a mais ao lead e à operação')
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

    describe 'contact_context_section (User Stories 1 & 2)' do
      context 'when contact has a placeholder name' do
        let(:placeholder_contact) { create(:contact, account: account, name: 'empty-meadow-50', phone_number: '+5511988887777') }
        let(:prompt_with_placeholder) do
          described_class.build(
            scout: scout,
            contact: placeholder_contact,
            inbox: inbox
          )
        end

        it 'appends the placeholder warning to the contact context section with immediacy and priority (FR-003, FR-012)' do
          expect(prompt_with_placeholder).to include('AVISO: O nome acima ("empty-meadow-50") foi gerado automaticamente pelo sistema')
          expect(prompt_with_placeholder).to include('não é o nome real do cliente')
          expect(prompt_with_placeholder).to include('idealmente na sua primeira resposta')
          expect(prompt_with_placeholder).to include('Priorize esta pergunta sobre qualquer pergunta de qualificação pendente')
          expect(prompt_with_placeholder).to include('registre com a ferramenta `update_contact`')
        end

        it 'instructs exemption from configured-fields-only guidance and once-only asking bound (FR-005, FR-013)' do
          expect(prompt_with_placeholder).to include(
            'Esta pergunta de identificação não faz parte dos campos de qualificação configurados ' \
            'e não está sujeita à restrição de perguntar apenas sobre campos configurados'
          )
          expect(prompt_with_placeholder).to include('a regra de não fazer perguntas no handoff prevalece')
          expect(prompt_with_placeholder).to include(
            'nunca repita a pergunta caso já tenha sido feita nesta conversa, mesmo que o visitante não tenha respondido'
          )
        end

        it 'specifically instructs never to use the placeholder name to address the customer directly (FR-002)' do
          expect(prompt_with_placeholder).to include('Nunca use esse valor para se dirigir a ele (ex: nunca diga "Olá, Empty Meadow!")')
        end
      end

      context 'when contact has a real name' do
        it 'omits the placeholder warning paragraph' do
          expect(prompt).to include('Maria Silva')
          expect(prompt).not_to include('AVISO: O nome acima')
          expect(prompt).not_to include('foi gerado automaticamente pelo sistema')
        end
      end
    end

    describe 'contact_context_section — phone number request (channel-agnostic, follows Matias/#62 gap)' do
      context 'when phone_number is blank and the name is already real' do
        let(:no_phone_contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: nil) }
        let(:prompt_no_phone) do
          described_class.build(scout: scout, contact: no_phone_contact, inbox: inbox)
        end

        it 'appends a phone-request warning with immediacy, priority, once-only bound, and no ordering clause' do
          expect(prompt_no_phone).to include('AVISO: O telefone deste contato não está registrado no sistema')
          expect(prompt_no_phone).to include('Peça o telefone de contato o mais cedo possível')
          expect(prompt_no_phone).to include('registre-o com a ferramenta `update_contact`')
          expect(prompt_no_phone).to include('Priorize esta pergunta sobre qualquer pergunta de qualificação pendente')
          expect(prompt_no_phone).to include(
            'não faz parte dos campos de qualificação configurados e não está sujeita à restrição ' \
            'de perguntar apenas sobre campos configurados'
          )
          expect(prompt_no_phone).to include('nunca faça esta pergunta se este turno for terminar em transferência para humano')
          expect(prompt_no_phone).not_to include('Peça-o somente depois de perguntar o nome')
        end
      end

      context 'when phone_number is present' do
        it 'omits the phone-request warning' do
          expect(prompt).not_to include('AVISO: O telefone deste contato não está registrado')
        end
      end

      context 'when both the name is a placeholder and phone_number is blank' do
        let(:unidentified_contact) { create(:contact, account: account, name: 'empty-meadow-50', phone_number: nil) }
        let(:prompt_unidentified) do
          described_class.build(scout: scout, contact: unidentified_contact, inbox: inbox)
        end

        it 'includes both warnings and orders the phone request after the name question' do
          expect(prompt_unidentified).to include('AVISO: O nome acima ("empty-meadow-50") foi gerado automaticamente pelo sistema')
          expect(prompt_unidentified).to include('AVISO: O telefone deste contato não está registrado no sistema')
          expect(prompt_unidentified).to include('Peça-o somente depois de perguntar o nome')
          expect(prompt_unidentified).to include('nunca peça nome e telefone na mesma mensagem')
        end
      end
    end

    describe 'contact_context_section — memory notes warning (User Stories 1, 2, 3)' do
      context 'when contact has notes' do
        let(:contact_with_notes) do
          contact = create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511988887777')
          contact.notes.create!(content: 'Interessada em plano Enterprise, conversou há 3 dias')
          contact
        end

        it 'includes memory notes warning with all three semantic assertions (T004)' do
          rendered_prompt = described_class.build(
            scout: scout,
            contact: contact_with_notes,
            inbox: inbox
          )

          expect(rendered_prompt).to include('AVISO: As anotações acima são resumos de conversas anteriores já concluídas')
          expect(rendered_prompt).to include('Você PODE e DEVE usar essas anotações para personalizar sua abordagem')
          expect(rendered_prompt).to include('uma anotação NUNCA, por si só, justifica chamar a ferramenta `handover_to_human`')
          expect(rendered_prompt).to include('o sinal de transferência deve vir das próprias mensagens da conversa atual')
        end
      end

      context 'when contact has no notes' do
        it 'does NOT include memory notes warning (T005)' do
          rendered_prompt = described_class.build(
            scout: scout,
            contact: contact,
            inbox: inbox
          )

          expect(rendered_prompt).not_to include('As anotações acima são resumos de conversas anteriores')
        end
      end

      it 'preserves existing identity and phone warnings unchanged (regression, T006)' do
        placeholder_contact = create(:contact, account: account, name: 'empty-meadow-50')
        placeholder_contact.notes.create!(content: 'Past handoff request')

        rendered_prompt = described_class.build(
          scout: scout,
          contact: placeholder_contact,
          inbox: inbox
        )

        expect(rendered_prompt).to include('AVISO: O nome acima ("empty-meadow-50") foi gerado automaticamente pelo sistema')
        expect(rendered_prompt).to include('AVISO: O telefone deste contato não está registrado no sistema')
        expect(rendered_prompt).to include('AVISO: As anotações acima são resumos de conversas anteriores')
      end
    end

    describe 'coexistence of identity warning, funnel guidance, and handoff closing reminder (Polish T016)' do
      let(:placeholder_contact) { create(:contact, account: account, name: 'empty-meadow-50', phone_number: '+5511988887777') }
      let!(:stage_new) { PipelineStage.create!(account: account, name: 'New', position: 1) }
      let!(:stage_qualified) { PipelineStage.create!(account: account, name: 'Qualified', position: 2) }
      let!(:attr_budget) do
        CustomAttributeDefinition.create!(
          account: account,
          attribute_key: 'budget',
          attribute_display_name: 'Orçamento Mensal',
          attribute_display_type: 'currency',
          attribute_model: 'opportunity_attribute'
        )
      end

      before do
        scout.update!(
          default_pipeline_stage: stage_new,
          qualified_stage: stage_qualified
        )
        scout.required_custom_attribute_definitions << attr_budget
      end

      it 'renders identity warning and funnel guidance simultaneously and unmodified' do
        rendered_prompt = described_class.build(
          scout: scout,
          contact: placeholder_contact,
          inbox: inbox
        )

        expect(rendered_prompt).to include('AVISO: O nome acima ("empty-meadow-50") foi gerado automaticamente pelo sistema')
        expect(rendered_prompt).to include('[Funil de Vendas e Qualificação]')
        expect(rendered_prompt).to include('Limite suas perguntas de qualificação aos campos configurados acima')
        expect(rendered_prompt).to include('Não invente perguntas adicionais fora dos campos configurados')
      end

      it 'renders handoff closing reminder alongside identity warning' do
        rendered_prompt = described_class.build(
          scout: scout,
          contact: placeholder_contact,
          inbox: inbox
        )

        expect(rendered_prompt).to include('Fallback para humano:')
        expect(rendered_prompt).to include('nunca faça perguntas ao transferir')
        expect(rendered_prompt).to include('[Lembrete de Encerramento]')
        expect(rendered_prompt).to include('sua resposta final não pode conter nenhuma pergunta ao cliente')
      end
    end
  end
end
