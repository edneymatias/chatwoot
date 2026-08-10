class Api::V1::Accounts::OpportunitiesController < Api::V1::Accounts::BaseController
  include Concerns::KanbanFeatureGuard

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
    relation = relation.where(status: params[:status]) if params[:status].present?

    if params[:custom_attributes].present?
      params[:custom_attributes].to_unsafe_h.each do |k, v|
        relation = relation.where('custom_attributes->>:key = :value', key: k, value: v) if v.present?
      end
    end

    if params[:payload].present?
      payload = JSON.parse(params[:payload])
      payload.each do |filter|
        key = filter['attribute_key'] || filter['attributeKey']
        vals = filter['values']
        next if key.blank?

        operator = filter['filter_operator'] || filter['filterOperator'] || 'equal_to'

        next if vals.blank? && !%w[is_present is_not_present].include?(operator)

        if %w[is_present is_not_present].include?(operator)
          is_present = operator == 'is_present'
          relation = if key == 'custom_attributes' || !Opportunity.column_names.include?(key)
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
          next
        end

        vals = vals.is_a?(Array) ? vals : [vals]
        vals = vals.map { |v| v.is_a?(Hash) ? (v['id'] || v['value'] || v) : v }

        if key == 'assignee_id' || key == 'status' || key == 'pipeline_stage_id'
          relation = if operator == 'not_equal_to'
                       relation.where.not(key => vals)
                     else
                       relation.where(key => vals)
                     end
        elsif operator == 'not_equal_to'
          relation = relation.where('custom_attributes->>:key NOT IN (:values) OR NOT (custom_attributes ? :key)', key: key,
                                                                                                                   values: vals.map(&:to_s))
        else
          relation = relation.where('custom_attributes->>:key IN (:values)', key: key, values: vals.map(&:to_s))
        end
      end
    end

    relation
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
