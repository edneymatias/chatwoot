# frozen_string_literal: true

class ScoutKnowledgeSource < ApplicationRecord
  self.table_name = 'ichatr_scout_knowledge_sources'

  belongs_to :account
  belongs_to :scout

  has_one_attached :document_file

  enum kind: { url: 0, document: 1, faq: 2 }
  enum status: { pending: 0, ready: 1, failed: 2 }

  validates :kind, :status, presence: true
  validates :url, presence: true,
                  format: {
                    with: URI::DEFAULT_PARSER.make_regexp(%w[http https]),
                    message: ->(_object, _data) { I18n.t('errors.scout_knowledge_source.invalid_url') }
                  },
                  if: :url?
  validates :question, :answer, presence: true, if: :faq?
  validate :validate_document_file

  before_validation :set_account_from_scout
  after_commit :enqueue_processing_job, on: %i[create update], if: :should_process?

  def reprocess!
    update!(status: :pending, error_message: nil)
    enqueue_processing_job
  end

  private

  def set_account_from_scout
    self.account_id ||= scout&.account_id
  end

  def validate_document_file
    return unless document?
    return errors.add(:document_file, I18n.t('errors.scout_knowledge_source.must_be_pdf')) unless document_file.content_type == 'application/pdf'
    return unless document_file.byte_size > 10.megabytes

    errors.add(:document_file, I18n.t('errors.scout_knowledge_source.file_too_large'))
  end

  def should_process?
    pending? && (url? || document?)
  end

  def enqueue_processing_job
    Custom::Scout::KnowledgeSources::ProcessJob.perform_later(id)
  end
end
