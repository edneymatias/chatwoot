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

    runner = Custom::Scout::PlaygroundRunner.new(scout: @scout, message: message_text)
    result = runner.perform

    render json: result
  end

  private

  def set_scout
    @scout = Current.account.scouts.find(params[:scout_id])
  end

  def check_authorization
    super(Scout)
  end
end
