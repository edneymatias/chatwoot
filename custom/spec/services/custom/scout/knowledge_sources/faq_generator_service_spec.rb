# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::KnowledgeSources::FaqGeneratorService do
  let(:account) { create(:account) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Knowledge Scout',
      responses_quota: 10,
      responses_consumed: 0,
      enabled: true
    )
  end
  let(:knowledge_source) do
    ScoutKnowledgeSource.create!(
      account: account,
      scout: scout,
      kind: :url,
      url: 'https://example.com/info',
      content: 'Company policy: 30 days return window for all orders.'
    )
  end

  let(:fake_chat) { instance_double(RubyLLM::Chat) }

  before do
    allow(scout).to receive(:llm_chat).and_return(fake_chat)
    allow(fake_chat).to receive(:with_params).and_return(fake_chat)
    allow(fake_chat).to receive(:with_instructions).and_return(fake_chat)
  end

  describe '#generate' do
    it 'returns empty array when knowledge source content is blank' do
      knowledge_source.content = ''
      service = described_class.new(knowledge_source)
      expect(service.generate).to eq([])
    end

    it 'calls LLM and parses JSON Q&A pairs' do
      json_response = {
        faqs: [
          { question: 'What is the return window?', answer: '30 days for all orders.' }
        ]
      }.to_json

      allow(fake_chat).to receive(:ask).and_return(instance_double(RubyLLM::Message, content: json_response))

      service = described_class.new(knowledge_source)
      result = service.generate

      expect(result).to eq(
        [
          { question: 'What is the return window?', answer: '30 days for all orders.' }
        ]
      )
    end

    it 'handles markdown json code blocks in response' do
      fenced_response = "```json\n{\"faqs\": [{\"question\": \"Q1?\", \"answer\": \"A1.\"}]}\n```"
      allow(fake_chat).to receive(:ask).and_return(instance_double(RubyLLM::Message, content: fenced_response))

      service = described_class.new(knowledge_source)
      result = service.generate

      expect(result).to eq([{ question: 'Q1?', answer: 'A1.' }])
    end

    it 'truncates content exceeding MAX_CONTENT_LENGTH before calling ask' do
      large_content = 'A' * 20_000
      knowledge_source.content = large_content

      expect(fake_chat).to receive(:ask).with(satisfy { |arg| arg.length == 12_000 })
                                        .and_return(instance_double(RubyLLM::Message, content: '{"faqs": []}'))

      service = described_class.new(knowledge_source)
      service.generate
    end

    it 'rescues JSON parse error and returns empty array' do
      allow(fake_chat).to receive(:ask).and_return(instance_double(RubyLLM::Message, content: 'invalid json'))

      service = described_class.new(knowledge_source)
      expect(service.generate).to eq([])
    end
  end
end
