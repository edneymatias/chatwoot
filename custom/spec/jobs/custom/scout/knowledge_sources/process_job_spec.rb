# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::KnowledgeSources::ProcessJob, type: :job do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Process Scout',
      responses_quota: 10,
      responses_consumed: 0,
      enabled: true
    )
  end

  describe '#perform' do
    context 'with faq source' do
      let(:faq_source) do
        ScoutKnowledgeSource.create!(
          account: account,
          scout: scout,
          kind: :faq,
          question: 'What are the plans?',
          answer: 'Basic, Pro, and Enterprise.'
        )
      end

      it 'sets ready status and creates ScoutKnowledgeEmbedding record directly' do
        expect do
          described_class.new.perform(faq_source)
        end.to change(ScoutKnowledgeEmbedding, :count).by(1)

        expect(faq_source.reload.status).to eq('ready')
        embedding = faq_source.scout_knowledge_embeddings.last
        expect(embedding.question).to eq('What are the plans?')
        expect(embedding.answer).to eq('Basic, Pro, and Enterprise.')
      end
    end

    context 'with url source' do
      let(:url_source) do
        ScoutKnowledgeSource.create!(
          account: account,
          scout: scout,
          kind: :url,
          url: 'https://example.com/faq'
        )
      end

      it 'extracts html and enqueues GenerateFaqsJob on success' do
        fake_response = instance_double(HTTParty::Response, success?: true, body: '<html><body><h1>Welcome</h1><p>Content</p></body></html>')
        allow(HTTParty).to receive(:get).and_return(fake_response)

        expect do
          described_class.new.perform(url_source)
        end.to have_enqueued_job(Custom::Scout::KnowledgeSources::GenerateFaqsJob).with(url_source.id)

        expect(url_source.reload.status).to eq('pending')
        expect(url_source.content).to include('Welcome')
      end

      it 'marks status failed when HTTP request fails' do
        fake_response = instance_double(HTTParty::Response, success?: false, code: 404)
        allow(HTTParty).to receive(:get).and_return(fake_response)

        described_class.new.perform(url_source)

        expect(url_source.reload.status).to eq('failed')
        expect(url_source.error_message).to include('404')
      end
    end

    context 'with document source' do
      let(:doc_source) do
        source = ScoutKnowledgeSource.new(
          account: account,
          scout: scout,
          kind: :document
        )
        source.document_file.attach(
          io: StringIO.new('%PDF-1.4 test stream'),
          filename: 'guide.pdf',
          content_type: 'application/pdf'
        )
        source.save!
        source
      end

      it 'extracts text from pdf and enqueues GenerateFaqsJob' do
        fake_page = instance_double(PDF::Reader::Page, text: 'Extracted PDF Page 1 Content')
        fake_reader = instance_double(PDF::Reader, pages: [fake_page])
        allow(PDF::Reader).to receive(:new).and_return(fake_reader)

        expect do
          described_class.new.perform(doc_source)
        end.to have_enqueued_job(Custom::Scout::KnowledgeSources::GenerateFaqsJob).with(doc_source.id)

        expect(doc_source.reload.status).to eq('pending')
        expect(doc_source.content).to include('Extracted PDF Page 1 Content')
      end
    end
  end
end
