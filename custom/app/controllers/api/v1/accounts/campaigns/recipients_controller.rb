# frozen_string_literal: true

class Api::V1::Accounts::Campaigns::RecipientsController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 25

  before_action :campaign
  before_action :authorize_campaign
  before_action :ensure_whatsapp_campaign_analytics_enabled!

  def metrics
    render json: delivery_metrics
  end

  def contacts
    paginated_recipients = filtered_recipients.includes(:contact).page(current_page).per(RESULTS_PER_PAGE)

    render json: {
      payload: paginated_recipients.map { |recipient| recipient_payload(recipient) },
      meta: {
        current_page: paginated_recipients.current_page,
        total_pages: paginated_recipients.total_pages,
        total_count: paginated_recipients.total_count
      }
    }
  end

  def reply_breakdown
    render json: compute_reply_breakdown
  end

  private

  def campaign
    @campaign ||= Current.account.campaigns.find_by!(display_id: params[:campaign_id])
  end

  def ensure_whatsapp_campaign_analytics_enabled!
    return if @campaign.one_off? && @campaign.inbox.inbox_type == 'Whatsapp' && Current.account.feature_enabled?(:whatsapp_campaign)

    raise Pundit::NotAuthorizedError
  end

  def authorize_campaign
    authorize @campaign, :show?
  end

  def delivery_metrics
    counts = recipients.reorder(nil).group(:status).count

    {
      audience: recipients.count,
      sent: recipients.where.not(source_id: nil).count,
      delivered: delivered_count(counts),
      read: counts['read'].to_i,
      failed: counts['failed'].to_i,
      skipped: counts['skipped'].to_i,
      replied: recipients.where.not(replied_at: nil).count,
      status_counts: status_counts_hash(counts)
    }
  end

  def delivered_count(counts)
    counts['delivered'].to_i + counts['read'].to_i + counts['replied'].to_i
  end

  def status_counts_hash(counts)
    Custom::CampaignRecipient.statuses.keys.index_with { |status| counts[status].to_i }
  end

  def compute_reply_breakdown
    sent_count = recipients.where.not(source_id: nil).count
    button_counts = recipients.reorder(nil).where(reply_type: :quick_reply).group(:reply_label).count

    sorted_buttons = button_counts.sort_by { |_label, count| -count }
    rows = sorted_buttons.map do |label, count|
      {
        label: label,
        total_clicks: count,
        click_rate: calculate_click_rate(count, sent_count)
      }
    end

    other_count = recipients.where(reply_type: :free_text).count
    rows << {
      label: 'other',
      total_clicks: other_count,
      click_rate: calculate_click_rate(other_count, sent_count)
    }

    rows
  end

  def calculate_click_rate(count, sent_count)
    return 0.0 if sent_count.zero?

    (count.to_f / sent_count).round(4)
  end

  def filtered_recipients
    return recipients unless Custom::CampaignRecipient.statuses.key?(params[:status])

    recipients.where(status: params[:status])
  end

  def recipients
    @recipients ||= @campaign.ichatr_campaign_recipients.order(created_at: :desc)
  end

  def recipient_payload(recipient)
    {
      contact: {
        id: recipient.contact.id,
        name: recipient.contact.name,
        phone_number: recipient.contact.phone_number
      },
      status: recipient.status,
      message_content: recipient.message_content,
      error_code: recipient.error_code,
      error_title: recipient.error_title,
      error_message: recipient.error_message
    }
  end

  def current_page
    params[:page].presence || 1
  end
end
