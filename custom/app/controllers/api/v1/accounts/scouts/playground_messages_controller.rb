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

    render json: dispatch_playground_message(message_text)
  end

  private

  def dispatch_playground_message(message_text)
    if Current.account.feature_enabled?('scout_v2')
      conversation = Custom::ScoutV2::PlaygroundConversation.for(@scout)
      return Custom::ScoutV2::TurnRunner.new(
        scout: @scout,
        conversation: conversation,
        message: message_text,
        message_history: permitted_message_history
      ).perform
    end

    Custom::Scout::PlaygroundRunner.new(
      scout: @scout,
      message: message_text,
      message_history: permitted_message_history
    ).perform
  end

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
