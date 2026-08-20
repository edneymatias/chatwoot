# frozen_string_literal: true

class Api::V1::Accounts::Scouts::ScoutInboxesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :set_scout

  def index
    @scout_inboxes = @scout.scout_inboxes.includes(:inbox)
    render json: @scout_inboxes.as_json(include: { inbox: { only: %i[id name channel_type] } })
  end

  def create
    inbox = Current.account.inboxes.find(params[:inbox_id])
    existing = ScoutInbox.find_by(inbox_id: inbox.id)

    if existing
      if existing.scout_id == @scout.id
        render json: existing.as_json(include: { inbox: { only: %i[id name channel_type] } })
        return
      end

      # If attached to another scout, reassign it
      existing.destroy!
    end

    @scout_inbox = @scout.scout_inboxes.create!(inbox: inbox)
    render json: @scout_inbox.as_json(include: { inbox: { only: %i[id name channel_type] } }), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    @scout_inbox = @scout.scout_inboxes.find(params[:id])
    @scout_inbox.destroy!
    head :ok
  end

  private

  def set_scout
    @scout = Current.account.scouts.find(params[:scout_id])
  end

  def check_authorization
    super(Scout)
  end
end
