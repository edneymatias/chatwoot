# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::ScoutOverviewReports', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }

  let!(:stage_new) { PipelineStage.create!(account: account, name: 'Novo', position: 0) }
  let!(:stage_qualified) { PipelineStage.create!(account: account, name: 'Qualificado', position: 1) }
  let!(:stage_unqualified) { PipelineStage.create!(account: account, name: 'Desqualificado', position: 2) }
  let!(:stage_rescue) { PipelineStage.create!(account: account, name: 'Resgatado', position: 3) }

  let!(:scout) do
    Scout.create!(
      account: account,
      name: 'Sales Bot',
      qualified_stage_id: stage_qualified.id,
      unqualified_stage_id: stage_unqualified.id,
      rescue_stage_id: stage_rescue.id
    )
  end
  let!(:channel) { create(:channel_api, account: account) }
  let!(:inbox) { create(:inbox, account: account, channel: channel) }
  let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }

  before do
    account.enable_features!('opportunities')
    ScoutInbox.create!(scout: scout, inbox: inbox)
  end

  describe 'GET /api/v1/accounts/{account.id}/scout_overview_reports' do
    context 'when unauthenticated (U21)' do
      it 'responds with 401 unauthorized' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when user is not a member of the account (U22)' do
      let(:non_member) { create(:user) }

      it 'responds with 401 unauthorized' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports",
            params: { scout_id: scout.id, range: '7' },
            headers: non_member.create_new_auth_token
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when user is an administrator (U24)' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'permits access and responds with 200 ok' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports",
            params: { scout_id: scout.id, range: '7' },
            headers: admin.create_new_auth_token
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when scout_id is missing (U25)' do
      it 'responds with 422 unprocessable entity' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports",
            params: { range: '7' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('scout_id is required')
      end
    end

    context 'when scout_id does not exist in account (U26)' do
      it 'responds with 404 not found' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports",
            params: { scout_id: 999_999, range: '7' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body['error']).to eq('Resource could not be found')
      end
    end

    context 'when range is missing (U27)' do
      it 'responds with 422 unprocessable entity' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports",
            params: { scout_id: scout.id },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('range is invalid or missing')
      end
    end

    context 'when range is invalid (U28)' do
      it 'responds with 422 unprocessable entity' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports",
            params: { scout_id: scout.id, range: 'invalid_range' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('range is invalid or missing')
      end
    end

    context 'when outcome stages are unconfigured (U7, U8, U9, A4)' do
      let!(:unconfigured_scout) do
        Scout.create!(
          account: account,
          name: 'Unconfigured Scout',
          qualified_stage_id: nil,
          unqualified_stage_id: nil,
          rescue_stage_id: nil
        )
      end

      before do
        unconf_inbox = create(:inbox, account: account, channel: channel)
        ScoutInbox.create!(scout: unconfigured_scout, inbox: unconf_inbox)
        unconf_contact_inbox = create(:contact_inbox, contact: contact, inbox: unconf_inbox)
        conv = create(:conversation, account: account, inbox: unconf_inbox, contact: contact, contact_inbox: unconf_contact_inbox)
        create(:message, account: account, inbox: unconf_inbox, conversation: conv, message_type: :incoming)
        Opportunity.create!(
          account: account,
          contact: contact,
          title: 'Opp Unconf',
          pipeline_stage: stage_new,
          origin_conversation: conv,
          created_at: 1.day.ago
        )
      end

      it 'returns nil for unconfigured outcome rates without division by zero error' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports",
            params: { scout_id: unconfigured_scout.id, range: '7' },
            headers: agent.create_new_auth_token

        expect(response).to have_http_status(:ok)
        summary = response.parsed_body['summary']
        expect(summary['total_handled']).to eq(1)
        expect(summary['qualification_rate']).to be_nil
        expect(summary['disqualification_rate']).to be_nil
        expect(summary['abandonment_rate']).to be_nil
      end
    end

    context 'when no opportunities exist in period (U10, U13, A5)' do
      it 'returns total_handled 0 and all rates and avg_messages nil' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports",
            params: { scout_id: scout.id, range: 'last_month' },
            headers: agent.create_new_auth_token

        expect(response).to have_http_status(:ok)
        summary = response.parsed_body['summary']
        expect(summary['total_handled']).to eq(0)
        expect(summary['qualification_rate']).to be_nil
        expect(summary['disqualification_rate']).to be_nil
        expect(summary['abandonment_rate']).to be_nil
        expect(summary['avg_messages_per_conversation']).to be_nil
      end
    end

    context 'when zero opportunities reached outcome stage but total_handled > 0 (U11)' do
      let!(:scout_with_no_outcomes) do
        Scout.create!(
          account: account,
          name: 'No Outcomes Scout',
          qualified_stage_id: stage_qualified.id,
          unqualified_stage_id: stage_unqualified.id,
          rescue_stage_id: stage_rescue.id
        )
      end

      before do
        no_outcomes_inbox = create(:inbox, account: account, channel: channel)
        ScoutInbox.create!(scout: scout_with_no_outcomes, inbox: no_outcomes_inbox)
        no_outcomes_contact_inbox = create(:contact_inbox, contact: contact, inbox: no_outcomes_inbox)
        conv = create(:conversation, account: account, inbox: no_outcomes_inbox, contact: contact, contact_inbox: no_outcomes_contact_inbox)
        create(:message, account: account, inbox: no_outcomes_inbox, conversation: conv, message_type: :incoming)
        Opportunity.create!(
          account: account,
          contact: contact,
          title: 'Opp In Progress',
          pipeline_stage: stage_new,
          origin_conversation: conv,
          created_at: 1.day.ago
        )
      end

      it 'returns 0.0 for outcome rates when configured stage has zero outcomes' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports",
            params: { scout_id: scout_with_no_outcomes.id, range: '7' },
            headers: agent.create_new_auth_token

        expect(response).to have_http_status(:ok)
        summary = response.parsed_body['summary']
        expect(summary['total_handled']).to eq(1)
        expect(summary['qualification_rate']).to eq(0.0)
        expect(summary['disqualification_rate']).to eq(0.0)
        expect(summary['abandonment_rate']).to eq(0.0)
      end
    end

    context 'with period range filtering and switching (U2, A2)' do
      before do
        conv = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
        create(:message, account: account, inbox: inbox, conversation: conv, message_type: :incoming)
        Opportunity.create!(
          account: account,
          contact: contact,
          title: 'Opp 20 days ago',
          pipeline_stage: stage_qualified,
          origin_conversation: conv,
          created_at: 20.days.ago
        )
      end

      it 'includes 20-day-old opportunity in range=30 but excludes it in range=7' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports",
            params: { scout_id: scout.id, range: '7' },
            headers: agent.create_new_auth_token
        expect(response.parsed_body['summary']['total_handled']).to eq(0)

        get "/api/v1/accounts/#{account.id}/scout_overview_reports",
            params: { scout_id: scout.id, range: '30' },
            headers: agent.create_new_auth_token
        expect(response.parsed_body['summary']['total_handled']).to eq(1)
      end
    end

    context 'with multi-scout scoping (A3)' do
      let!(:scout2) { Scout.create!(account: account, name: 'Scout Two') }

      before do
        inbox2 = create(:inbox, account: account, channel: channel)
        ScoutInbox.create!(scout: scout2, inbox: inbox2)
        contact2_inbox = create(:contact_inbox, contact: contact, inbox: inbox2)
        conv2 = create(:conversation, account: account, inbox: inbox2, contact: contact, contact_inbox: contact2_inbox)
        Opportunity.create!(
          account: account,
          contact: contact,
          title: 'Opp for Scout 2',
          pipeline_stage: stage_new,
          origin_conversation: conv2,
          created_at: 1.day.ago
        )
      end

      it 'isolates data strictly to the selected scout' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports",
            params: { scout_id: scout.id, range: '7' },
            headers: agent.create_new_auth_token
        expect(response.parsed_body['summary']['total_handled']).to eq(0)

        get "/api/v1/accounts/#{account.id}/scout_overview_reports",
            params: { scout_id: scout2.id, range: '7' },
            headers: agent.create_new_auth_token
        expect(response.parsed_body['summary']['total_handled']).to eq(1)
      end
    end

    context 'with timezone offset (U29)' do
      it 'shifts calendar month window when timezone_offset is provided across month boundary' do
        boundary_conv = create(:conversation, account: account, inbox: inbox)
        Opportunity.create!(
          account: account,
          contact: contact,
          title: 'Boundary Opportunity',
          origin_conversation: boundary_conv,
          pipeline_stage: stage_qualified,
          created_at: Time.utc(2026, 5, 20, 12, 0, 0)
        )

        travel_to Time.utc(2026, 6, 1, 1, 0, 0) do
          get "/api/v1/accounts/#{account.id}/scout_overview_reports",
              params: { scout_id: scout.id, range: 'this_month' },
              headers: agent.create_new_auth_token
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body['summary']['total_handled']).to eq(0)

          get "/api/v1/accounts/#{account.id}/scout_overview_reports",
              params: { scout_id: scout.id, range: 'this_month', timezone_offset: '-3' },
              headers: agent.create_new_auth_token
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body['summary']['total_handled']).to eq(1)
        end
      end
    end

    context 'with response contract structure (U30)' do
      it 'includes summary, pipeline_stage_distribution, and interest_by_stage keys' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports",
            params: { scout_id: scout.id, range: '7' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:ok)
        keys = response.parsed_body.keys
        expect(keys).to contain_exactly('summary', 'pipeline_stage_distribution', 'interest_by_stage')
      end
    end

    context 'with pipeline stage distribution (U14, U15, U16, A6, A7)' do
      let!(:stage_negotiation) { PipelineStage.create!(account: account, name: 'Negociação', position: 4) }

      before do
        PipelineStage.create!(account: account, name: 'Fechado', position: 5)
        # 1. Opportunity created 2 days ago in stage_new
        conv1 = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
        Opportunity.create!(
          account: account,
          contact: contact,
          title: 'Opp Recent',
          pipeline_stage: stage_new,
          origin_conversation: conv1,
          created_at: 2.days.ago
        )

        # 2. Opportunity created 15 days ago in stage_negotiation (human-managed stage)
        conv2 = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
        Opportunity.create!(
          account: account,
          contact: contact,
          title: 'Opp in Human Stage',
          pipeline_stage: stage_negotiation,
          origin_conversation: conv2,
          created_at: 15.days.ago
        )
      end

      it 'returns all pipeline stages in position ASC with counts scoped to period' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports",
            params: { scout_id: scout.id, range: '7' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:ok)

        dist_7 = response.parsed_body['pipeline_stage_distribution']
        expect(dist_7.map { |s| s['stage_position'] }).to eq([0, 1, 2, 3, 4, 5])
        expect(dist_7.map { |s| s['stage_name'] }).to eq(%w[Novo Qualificado Desqualificado Resgatado Negociação Fechado])

        counts_by_name = dist_7.to_h { |s| [s['stage_name'], s['count']] }
        expect(counts_by_name['Novo']).to eq(1)
        expect(counts_by_name['Negociação']).to eq(0)
        expect(counts_by_name['Fechado']).to eq(0)
      end

      it 'updates pipeline distribution when period range changes to include older opportunities (A7)' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports",
            params: { scout_id: scout.id, range: '7' },
            headers: agent.create_new_auth_token
        counts_7 = response.parsed_body['pipeline_stage_distribution'].to_h { |s| [s['stage_name'], s['count']] }
        expect(counts_7['Negociação']).to eq(0)

        get "/api/v1/accounts/#{account.id}/scout_overview_reports",
            params: { scout_id: scout.id, range: '30' },
            headers: agent.create_new_auth_token
        counts_30 = response.parsed_body['pipeline_stage_distribution'].to_h { |s| [s['stage_name'], s['count']] }
        expect(counts_30['Negociação']).to eq(1)
      end
    end

    context 'with interest by stage (U17, U18, U19, U20, A8, A9)' do
      context 'when scout does not have interest_attribute_definition configured (U17, A9)' do
        it 'returns configured: false' do
          get "/api/v1/accounts/#{account.id}/scout_overview_reports",
              params: { scout_id: scout.id, range: '7' },
              headers: agent.create_new_auth_token
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body['interest_by_stage']).to eq({ 'configured' => false })
        end
      end

      context 'when scout has interest_attribute_definition configured (U18, U19, U20, A8)' do
        let!(:interest_def) do
          create(
            :custom_attribute_definition,
            account: account,
            attribute_model: 'opportunity_attribute',
            attribute_key: 'produto',
            attribute_display_name: 'Produto',
            attribute_display_type: 'list'
          )
        end

        before do
          scout.update!(interest_attribute_definition: interest_def)

          # Opp 1: Seguro (2 days ago)
          c1 = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
          Opportunity.create!(
            account: account, contact: contact, title: 'Opp Seguro',
            pipeline_stage: stage_qualified, origin_conversation: c1,
            custom_attributes: { 'produto' => 'Seguro' }, created_at: 2.days.ago
          )

          # Opp 2: Financiamento (2 days ago)
          c2 = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
          Opportunity.create!(
            account: account, contact: contact, title: 'Opp Financiamento',
            pipeline_stage: stage_qualified, origin_conversation: c2,
            custom_attributes: { 'produto' => 'Financiamento' }, created_at: 2.days.ago
          )

          # Opp 3: nil interest (2 days ago)
          c3 = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
          Opportunity.create!(
            account: account, contact: contact, title: 'Opp No Interest',
            pipeline_stage: stage_qualified, origin_conversation: c3,
            custom_attributes: {}, created_at: 2.days.ago
          )
        end

        it 'returns configured: true with attribute_name and breakdown per stage including null key for selected period' do
          get "/api/v1/accounts/#{account.id}/scout_overview_reports",
              params: { scout_id: scout.id, range: '7' },
              headers: agent.create_new_auth_token
          expect(response).to have_http_status(:ok)

          interest = response.parsed_body['interest_by_stage']
          expect(interest['configured']).to be(true)
          expect(interest['attribute_name']).to eq('Produto')

          qual_stage = interest['data'].find { |s| s['stage_id'] == stage_qualified.id }
          expected_breakdown = {
            'Seguro' => 1,
            'Financiamento' => 1,
            'null' => 1
          }
          expect(qual_stage['breakdown']).to eq(expected_breakdown)
        end
      end
    end

    describe 'acceptance A1: summary metrics for Scout with handled opportunities' do
      before do
        # 1. Qualified opportunity (2 messages)
        conv1 = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
        2.times { create(:message, account: account, inbox: inbox, conversation: conv1, message_type: :incoming) }
        Opportunity.create!(
          account: account,
          contact: contact,
          title: 'Opp 1',
          pipeline_stage: stage_qualified,
          origin_conversation: conv1,
          created_at: 2.days.ago
        )

        # 2. Disqualified opportunity (4 messages)
        conv2 = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
        4.times { create(:message, account: account, inbox: inbox, conversation: conv2, message_type: :incoming) }
        Opportunity.create!(
          account: account,
          contact: contact,
          title: 'Opp 2',
          pipeline_stage: stage_unqualified,
          origin_conversation: conv2,
          created_at: 2.days.ago
        )

        # 3. Abandoned opportunity (6 messages)
        conv3 = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
        6.times { create(:message, account: account, inbox: inbox, conversation: conv3, message_type: :incoming) }
        Opportunity.create!(
          account: account,
          contact: contact,
          title: 'Opp 3',
          pipeline_stage: stage_rescue,
          origin_conversation: conv3,
          created_at: 2.days.ago
        )

        # 4. In progress opportunity (4 messages)
        conv4 = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
        4.times { create(:message, account: account, inbox: inbox, conversation: conv4, message_type: :incoming) }
        Opportunity.create!(
          account: account,
          contact: contact,
          title: 'Opp 4',
          pipeline_stage: stage_new,
          origin_conversation: conv4,
          created_at: 2.days.ago
        )
      end

      it 'returns 200 with summary metrics calculating rates against total handled including in-progress' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports",
            params: { scout_id: scout.id, range: '7' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:ok)
        body = response.parsed_body

        expected_summary = {
          'total_handled' => 4,
          'qualification_rate' => 25.0,
          'disqualification_rate' => 25.0,
          'abandonment_rate' => 25.0,
          'avg_messages_per_conversation' => 4.0
        }
        expect(body['summary']).to eq(expected_summary)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/scout_overview_reports/conversations' do
    context 'when unauthenticated (U1)' do
      it 'returns 401 unauthorized' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id, range: '7' }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when user is not a member of the account (U2)' do
      let(:non_member) { create(:user) }

      it 'responds with 401 unauthorized' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id, range: '7' },
            headers: non_member.create_new_auth_token
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when user is an authenticated agent (U3)' do
      it 'responds with 200 ok' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id, range: '7' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when user is an administrator (U3)' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'responds with 200 ok' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id, range: '7' },
            headers: admin.create_new_auth_token
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when scout_id is missing (U4)' do
      it 'returns 422 unprocessable_content with error message' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { range: '7' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body).to eq({ 'error' => 'scout_id is required' })
      end
    end

    context 'when scout_id does not exist in account (U5)' do
      let(:other_account) { create(:account) }
      let(:other_scout) { Scout.create!(account: other_account, name: 'Other Bot') }

      it 'returns 404 not_found' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: other_scout.id, range: '7' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when range is missing or invalid (U6)' do
      it 'returns 422 when range is missing' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body).to eq({ 'error' => 'range is invalid or missing' })
      end

      it 'returns 422 when range is invalid' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id, range: '999' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body).to eq({ 'error' => 'range is invalid or missing' })
      end
    end

    context 'when status parameter is invalid (U7)' do
      it 'returns 422 unprocessable_content with error message' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id, range: '7', status: 'unknown_status' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body).to eq({ 'error' => 'status is invalid' })
      end
    end

    context 'when status parameter is valid (U8)' do
      %w[all qualified disqualified abandoned in_progress transferred_without_opportunity].each do |st|
        it "accepts status #{st} with 200 ok" do
          get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
              params: { scout_id: scout.id, range: '7', status: st },
              headers: agent.create_new_auth_token
          expect(response).to have_http_status(:ok)
        end
      end
    end

    context 'with pagination parameters (U9)' do
      it 'caps per_page parameter at maximum 100' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id, range: '7', per_page: 500 },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['pagination']['per_page']).to eq(100)
      end
    end

    context 'with page parameter defaulting (U10)' do
      it 'defaults page parameter to 1 when omitted' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id, range: '7' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['pagination']['current_page']).to eq(1)
      end

      it 'defaults page parameter to 1 when less than 1' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id, range: '7', page: -5 },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['pagination']['current_page']).to eq(1)
      end
    end

    describe 'scout inbox scoping (U11)' do
      let!(:other_inbox) { create(:inbox, account: account) }
      let!(:scout_conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
      let!(:other_conversation) { create(:conversation, account: account, inbox: other_inbox, contact: contact) }

      it 'restricts handled conversations to inboxes assigned to the scout' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id, range: '7' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:ok)
        conv_ids = response.parsed_body['conversations'].map { |c| c['id'] }
        expect(conv_ids).to include(scout_conversation.id)
        expect(conv_ids).not_to include(other_conversation.id)
      end
    end

    describe 'funnel outcome classification (U12..U16)' do
      let!(:conv_qualified) { create(:conversation, account: account, inbox: inbox, contact: contact) }
      let!(:opp_qualified) do
        Opportunity.create!(
          account: account,
          title: 'Qualified Deal',
          pipeline_stage: stage_qualified,
          contact: contact
        )
      end

      before do
        OpportunityConversation.create!(account: account, opportunity: opp_qualified, conversation: conv_qualified)
      end

      it 'classifies conversation as qualified when linked opportunity stage equals scout.qualified_stage_id (U12)' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id, range: '7' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:ok)
        conv = response.parsed_body['conversations'].find { |c| c['id'] == conv_qualified.id }
        expect(conv['status']).to eq('qualified')
        expect(conv['opportunity']).to eq(
          {
            'id' => opp_qualified.id,
            'title' => 'Qualified Deal',
            'stage_id' => stage_qualified.id
          }
        )
      end

      it 'classifies conversation as disqualified when linked opportunity stage equals scout.unqualified_stage_id (U13)' do
        conv = create(:conversation, account: account, inbox: inbox, contact: contact)
        opp = Opportunity.create!(account: account, title: 'Unqualified Deal', pipeline_stage: stage_unqualified, contact: contact)
        OpportunityConversation.create!(account: account, opportunity: opp, conversation: conv)

        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id, range: '7' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:ok)
        item = response.parsed_body['conversations'].find { |c| c['id'] == conv.id }
        expect(item['status']).to eq('disqualified')
      end

      it 'classifies conversation as abandoned when linked opportunity stage equals scout.rescue_stage_id (U14)' do
        conv = create(:conversation, account: account, inbox: inbox, contact: contact)
        opp = Opportunity.create!(account: account, title: 'Rescued Deal', pipeline_stage: stage_rescue, contact: contact)
        OpportunityConversation.create!(account: account, opportunity: opp, conversation: conv)

        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id, range: '7' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:ok)
        item = response.parsed_body['conversations'].find { |c| c['id'] == conv.id }
        expect(item['status']).to eq('abandoned')
      end

      it 'classifies conversation as in_progress when opportunity is in intermediate stage or conversation is pending (U15)' do
        conv_initial = create(:conversation, account: account, inbox: inbox, contact: contact)
        opp_initial = Opportunity.create!(account: account, title: 'Initial Deal', pipeline_stage: stage_new, contact: contact)
        OpportunityConversation.create!(account: account, opportunity: opp_initial, conversation: conv_initial)

        conv_pending = create(:conversation, account: account, inbox: inbox, contact: contact, status: :pending)

        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id, range: '7' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:ok)
        item_initial = response.parsed_body['conversations'].find { |c| c['id'] == conv_initial.id }
        item_pending = response.parsed_body['conversations'].find { |c| c['id'] == conv_pending.id }
        expect(item_initial['status']).to eq('in_progress')
        expect(item_pending['status']).to eq('in_progress')
      end

      it 'classifies conversation as transferred_without_opportunity when not pending and no opportunity (U16)' do
        conv_handoff = create(:conversation, account: account, inbox: inbox, contact: contact)
        conv_handoff.open!

        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id, range: '7' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:ok)
        item = response.parsed_body['conversations'].find { |c| c['id'] == conv_handoff.id }
        expect(item['status']).to eq('transferred_without_opportunity')
        expect(item['opportunity']).to be_nil
      end
    end

    describe 'duration and message metrics (U17, U18, U19)' do
      let!(:conv_zero) { create(:conversation, account: account, inbox: inbox, contact: contact) }
      let!(:conv_single) { create(:conversation, account: account, inbox: inbox, contact: contact) }
      let!(:conv_multi) { create(:conversation, account: account, inbox: inbox, contact: contact) }

      before do
        create(:message, account: account, inbox: inbox, conversation: conv_single, message_type: :incoming, created_at: 1.hour.ago)
        create(:message, account: account, inbox: inbox, conversation: conv_multi, message_type: :incoming, created_at: 2.hours.ago)
        create(:message, account: account, inbox: inbox, conversation: conv_multi, message_type: :outgoing, created_at: 2.hours.ago + 180.seconds)
      end

      it 'returns duration_seconds null when conversation has 0 or 1 messages (U17)' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id, range: '7' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:ok)
        item_zero = response.parsed_body['conversations'].find { |c| c['id'] == conv_zero.id }
        item_single = response.parsed_body['conversations'].find { |c| c['id'] == conv_single.id }
        expect(item_zero['duration_seconds']).to be_nil
        expect(item_single['duration_seconds']).to be_nil
      end

      it 'calculates duration_seconds as difference between first and last message for 2+ messages (U18)' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id, range: '7' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:ok)
        item_multi = response.parsed_body['conversations'].find { |c| c['id'] == conv_multi.id }
        expect(item_multi['duration_seconds']).to eq(180)
      end

      it 'calculates messages_count as total incoming and outgoing messages (U19)' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id, range: '7' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:ok)
        item_zero = response.parsed_body['conversations'].find { |c| c['id'] == conv_zero.id }
        item_single = response.parsed_body['conversations'].find { |c| c['id'] == conv_single.id }
        item_multi = response.parsed_body['conversations'].find { |c| c['id'] == conv_multi.id }
        expect(item_zero['messages_count']).to eq(0)
        expect(item_single['messages_count']).to eq(1)
        expect(item_multi['messages_count']).to eq(2)
      end
    end

    describe 'ordering, status counts, filtering, pagination, and lateral resolution (U20..U25)' do
      let!(:c_old) { create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 3.days.ago) }
      let!(:c_new) { create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 1.day.ago) }

      before do
        opp_old = Opportunity.create!(account: account, title: 'Old Deal', pipeline_stage: stage_qualified, contact: contact)
        opp_new = Opportunity.create!(account: account, title: 'New Deal', pipeline_stage: stage_unqualified, contact: contact)
        OpportunityConversation.create!(account: account, opportunity: opp_old, conversation: c_old)
        OpportunityConversation.create!(account: account, opportunity: opp_new, conversation: c_new)
      end

      it 'orders returned conversations chronologically by start timestamp descending (U20)' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id, range: '7' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:ok)
        convs = response.parsed_body['conversations']
        expect(convs.map { |c| c['id'] }).to eq([c_new.id, c_old.id])
      end

      it 'calculates status_counts across all 5 statuses and all total (U21)' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id, range: '7' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:ok)
        counts = response.parsed_body['status_counts']
        sum_statuses = counts['qualified'] + counts['disqualified'] + counts['abandoned'] +
                       counts['in_progress'] + counts['transferred_without_opportunity']
        expect(counts['all']).to eq(sum_statuses)
        expect(counts['qualified']).to eq(1)
        expect(counts['disqualified']).to eq(1)
      end

      it 'filters conversations to matching status while status_counts retains full totals (U22)' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id, range: '7', status: 'qualified' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:ok)
        convs = response.parsed_body['conversations']
        expect(convs).to all(satisfy { |c| c['status'] == 'qualified' })
        counts = response.parsed_body['status_counts']
        expect(counts['disqualified']).to be >= 1
      end

      it 'paginates results returning correct pagination metadata (U23)' do
        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id, range: '7', per_page: 1, page: 1 },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:ok)
        pagination = response.parsed_body['pagination']
        expect(pagination['current_page']).to eq(1)
        expect(pagination['per_page']).to eq(1)
        expect(pagination['total_count']).to be >= 2
        expect(pagination['total_pages']).to be >= 2
        expect(response.parsed_body['conversations'].size).to eq(1)
      end

      it 'excludes conversations created outside range or belonging to another scout (U24)' do
        c_outside = create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 20.days.ago)
        other_scout = Scout.create!(account: account, name: 'Other Scout')
        other_inbox = create(:inbox, account: account)
        ScoutInbox.create!(scout: other_scout, inbox: other_inbox)
        c_other_scout = create(:conversation, account: account, inbox: other_inbox, contact: contact, created_at: 1.day.ago)

        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id, range: '7' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:ok)
        ids = response.parsed_body['conversations'].map { |c| c['id'] }
        expect(ids).not_to include(c_outside.id)
        expect(ids).not_to include(c_other_scout.id)
      end

      it 'resolves latest opportunity stage when conversation has multiple opportunities (U25)' do
        conv_multi_opp = create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 1.day.ago)
        opp_first = Opportunity.create!(
          account: account, title: 'First Stage', pipeline_stage: stage_unqualified,
          contact: contact, updated_at: 10.minutes.ago
        )
        opp_latest = Opportunity.create!(
          account: account, title: 'Latest Stage', pipeline_stage: stage_qualified,
          contact: contact, updated_at: 1.minute.ago
        )

        OpportunityConversation.create!(account: account, opportunity: opp_first, conversation: conv_multi_opp)
        OpportunityConversation.create!(account: account, opportunity: opp_latest, conversation: conv_multi_opp)

        get "/api/v1/accounts/#{account.id}/scout_overview_reports/conversations",
            params: { scout_id: scout.id, range: '7' },
            headers: agent.create_new_auth_token
        expect(response).to have_http_status(:ok)
        item = response.parsed_body['conversations'].find { |c| c['id'] == conv_multi_opp.id }
        expect(item['status']).to eq('qualified')
        expect(item['opportunity']['id']).to eq(opp_latest.id)
      end
    end
  end
end
