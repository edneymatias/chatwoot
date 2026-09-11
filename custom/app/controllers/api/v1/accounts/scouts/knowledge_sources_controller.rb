# frozen_string_literal: true

class Api::V1::Accounts::Scouts::KnowledgeSourcesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :set_scout
  before_action :set_knowledge_source, only: %i[show update destroy]

  def index
    @knowledge_sources = @scout.scout_knowledge_sources.includes(:scout_knowledge_embeddings).order(created_at: :desc)
    render json: @knowledge_sources.map { |source| serialize_source(source) }
  end

  def show
    render json: serialize_source(@knowledge_source)
  end

  def create
    @knowledge_source = @scout.scout_knowledge_sources.build(knowledge_source_params.merge(account: Current.account))

    if @knowledge_source.save
      render json: serialize_source(@knowledge_source), status: :created
    else
      render json: { error: @knowledge_source.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def update
    if params[:reprocess]
      @knowledge_source.reprocess!
      render json: serialize_source(@knowledge_source)
      return
    end

    if @knowledge_source.update(knowledge_source_params)
      render json: serialize_source(@knowledge_source)
    else
      render json: { error: @knowledge_source.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def destroy
    @knowledge_source.destroy!
    head :ok
  end

  private

  def set_scout
    @scout = Current.account.scouts.find(params[:scout_id])
  end

  def set_knowledge_source
    @knowledge_source = @scout.scout_knowledge_sources.find(params[:id])
  end

  def check_authorization
    super(ScoutKnowledgeSource)
  end

  def knowledge_source_params
    (params[:knowledge_source] || params).permit(:kind, :url, :question, :answer, :document_file)
  end

  def serialize_source(source)
    data = source.as_json
    data['embeddings_count'] = source.scout_knowledge_embeddings.size
    if source.document? && source.document_file.attached?
      data['document_file'] = {
        'filename' => source.document_file.filename.to_s,
        'byte_size' => source.document_file.byte_size,
        'content_type' => source.document_file.content_type
      }
    end
    data
  end
end
