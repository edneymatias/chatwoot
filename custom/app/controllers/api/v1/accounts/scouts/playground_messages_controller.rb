# frozen_string_literal: true

class Api::V1::Accounts::Scouts::PlaygroundMessagesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :set_scout

  def create
    message_text = params[:message].to_s.strip
    if message_text.blank?
      render json: { error: 'Message cannot be blank' }, status: :unprocessable_entity
      return
    end

    runner = Custom::Scout::PlaygroundRunner.new(
      scout: @scout,
      message: message_text,
      message_history: permitted_message_history
    )
    result = runner.perform

    render json: result
  end

  private

  def permitted_message_history
    history = params[:message_history]
    return [] unless history.is_a?(Array)

    history.filter_map do |item|
      next unless item.is_a?(ActionController::Parameters) || item.is_a?(Hash)

      role = item[:role].to_s
      content = item[:content].to_s
      next if content.blank?

      { role: role == 'assistant' ? 'assistant' : 'user', content: content }
    end
  end

  def set_scout
    @scout = Current.account.scouts.find(params[:scout_id])
  end

  def check_authorization
    super(Scout)
  end
end
