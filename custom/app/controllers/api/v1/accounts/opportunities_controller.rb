class Api::V1::Accounts::OpportunitiesController < Api::V1::Accounts::BaseController
  include Concerns::KanbanFeatureGuard

  DEFAULT_STATUS = 'open'.freeze

  before_action :fetch_opportunity, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @opportunities = policy_scope(Opportunity)
                     .includes(:pipeline_stage, :origin_conversation,
                               contact: { avatar_attachment: :blob }, assignee: { avatar_attachment: :blob })

    @opportunities = apply_filters(@opportunities)
    @opportunities = apply_search(@opportunities)
    @opportunities = apply_sort(@opportunities)
    if params[:page].present?
      @opportunities = @opportunities.page(params[:page]).per(15)
      render json: {
        meta: {
          count: @opportunities.total_count,
          current_page: @opportunities.current_page
        },
        payload: @opportunities
      }
    else
      render json: @opportunities
    end
  end

  def show
    render json: @opportunity
  end

  def create
    @opportunity = Current.account.opportunities.build(opportunity_create_params)
    if @opportunity.save
      render json: @opportunity
    else
      render json: { error: @opportunity.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def update
    if @opportunity.update(opportunity_update_params)
      render json: @opportunity
    elsif @opportunity.missing_required_fields.present?
      render json: {
        error: @opportunity.errors.full_messages.join(', '),
        missing_required_fields: @opportunity.missing_required_fields
      }, status: :unprocessable_entity
    else
      render json: { error: @opportunity.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def destroy
    if @opportunity.destroy
      head :ok
    else
      render json: { error: @opportunity.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  private

  def apply_filters(relation)
    relation = relation.where(pipeline_stage_id: params[:pipeline_stage_id]) if params[:pipeline_stage_id].present?
    relation = relation.where(contact_id: params[:contact_id]) if params[:contact_id].present?
    relation = relation.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?
    relation = apply_status_filter(relation)
    relation = apply_custom_attributes_filter(relation)
    apply_payload_filters(relation)
  end

  def apply_status_filter(relation)
    return relation if params[:status] == 'all'

    has_payload_status = false
    if params[:payload].present?
      payload = begin
        JSON.parse(params[:payload])
      rescue StandardError
        []
      end
      has_payload_status = payload.any? { |f| (f['attribute_key'] || f['attributeKey']) == 'status' }
    end

    status_val = params[:status].presence || (has_payload_status ? nil : DEFAULT_STATUS)
    status_val.present? ? relation.where(status: status_val) : relation
  end

  def apply_custom_attributes_filter(relation)
    return relation if params[:custom_attributes].blank?

    params[:custom_attributes].to_unsafe_h.each do |k, v|
      relation = relation.where('custom_attributes->>:key = :value', key: k, value: v) if v.present?
    end
    relation
  end

  def apply_payload_filters(relation)
    return relation if params[:payload].blank?

    payload = JSON.parse(params[:payload])
    payload.each do |filter|
      relation = apply_single_payload_filter(relation, filter)
    end
    relation
  end

  def apply_single_payload_filter(relation, filter)
    key = filter['attribute_key'] || filter['attributeKey']
    vals = filter['values']
    return relation if key.blank?

    operator = filter['filter_operator'] || filter['filterOperator'] || 'equal_to'
    return relation if vals.blank? && %w[is_present is_not_present].exclude?(operator)

    return apply_presence_filter(relation, key, operator) if %w[is_present is_not_present].include?(operator)

    apply_value_filter(relation, key, vals, operator)
  end

  def apply_presence_filter(relation, key, operator)
    is_present = operator == 'is_present'
    if key == 'custom_attributes' || !Opportunity.column_names.include?(key)
      if is_present
        relation.where('custom_attributes ? :key', key: key)
      else
        relation.where('NOT (custom_attributes ? :key) OR custom_attributes->>:key IS NULL', key: key)
      end
    elsif is_present
      relation.where.not(key => nil)
    else
      relation.where(key => nil)
    end
  end

  def apply_value_filter(relation, key, vals, operator)
    vals = vals.is_a?(Array) ? vals : [vals]
    vals = vals.map { |v| v.is_a?(Hash) ? (v['id'] || v['value'] || v) : v }

    if %w[assignee_id status pipeline_stage_id].include?(key)
      operator == 'not_equal_to' ? relation.where.not(key => vals) : relation.where(key => vals)
    elsif operator == 'not_equal_to'
      relation.where('custom_attributes->>:key NOT IN (:values) OR NOT (custom_attributes ? :key)', key: key, values: vals.map(&:to_s))
    else
      relation.where('custom_attributes->>:key IN (:values)', key: key, values: vals.map(&:to_s))
    end
  end

  def apply_search(relation)
    return relation if params[:q].blank?

    query = ActiveRecord::Base.sanitize_sql_like(params[:q])
    relation.left_joins(:contact)
            .where("#{Opportunity.table_name}.title ILIKE :q OR #{Contact.table_name}.name ILIKE :q", q: "%#{query}%")
  end

  def apply_sort(relation)
    case params[:sort_by]
    when 'value_desc'
      relation.order('value DESC NULLS LAST')
    when 'value_asc'
      relation.order('value ASC NULLS LAST')
    when 'last_activity'
      relation.order(updated_at: :desc)
    else
      relation.order(created_at: :desc)
    end
  end

  def fetch_opportunity
    @opportunity = Current.account.opportunities.find(params[:id])
  end

  def check_authorization
    authorize(@opportunity || Opportunity)
  end

  def opportunity_create_params
    params.require(:opportunity).permit(
      :title,
      :contact_id,
      :pipeline_stage_id,
      :status,
      :origin_conversation_id,
      :assignee_id,
      :value,
      custom_attributes: {}
    )
  end

  def opportunity_update_params
    params.require(:opportunity).permit(
      :title,
      :contact_id,
      :pipeline_stage_id,
      :status,
      :origin_conversation_id,
      :assignee_id,
      :value,
      custom_attributes: {}
    )
  end
end
