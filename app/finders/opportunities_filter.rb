class OpportunitiesFilter
  DEFAULT_STATUS = 'open'.freeze
  NO_PLATFORM_VALUE = 'none'.freeze

  def initialize(relation, params)
    @relation = relation
    @params = params
  end

  def perform
    relation = @relation
    relation = relation.where(pipeline_stage_id: @params[:pipeline_stage_id]) if @params[:pipeline_stage_id].present?
    relation = relation.where(contact_id: @params[:contact_id]) if @params[:contact_id].present?
    relation = relation.where(assignee_id: @params[:assignee_id]) if @params[:assignee_id].present?
    relation = apply_status_filter(relation)
    relation = apply_custom_attributes_filter(relation)
    relation = apply_payload_filters(relation)
    relation = apply_search(relation)
    apply_sort(relation)
  end

  private

  def apply_status_filter(relation)
    return relation if @params[:status] == 'all'

    has_payload_status = false
    if @params[:payload].present?
      payload = begin
        JSON.parse(@params[:payload])
      rescue StandardError
        []
      end
      has_payload_status = payload.any? { |f| (f['attribute_key'] || f['attributeKey']) == 'status' }
    end

    status_val = @params[:status].presence || (has_payload_status ? nil : DEFAULT_STATUS)
    status_val.present? ? relation.where(status: status_val) : relation
  end

  def apply_custom_attributes_filter(relation)
    return relation if @params[:custom_attributes].blank?

    @params[:custom_attributes].to_unsafe_h.each do |k, v|
      relation = relation.where('custom_attributes->>:key = :value', key: k, value: v) if v.present?
    end
    relation
  end

  def apply_payload_filters(relation)
    return relation if @params[:payload].blank?

    payload = JSON.parse(@params[:payload])
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
    if key == 'custom_attributes' || Opportunity.column_names.exclude?(key)
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
    vals = vals.map { |v| v == NO_PLATFORM_VALUE ? nil : v } if key == 'campaign_platform'

    if Opportunity.column_names.include?(key)
      apply_standard_column_filter(relation, key, vals, operator)
    else
      apply_custom_attribute_value_filter(relation, key, vals, operator)
    end
  end

  def apply_standard_column_filter(relation, key, vals, operator)
    case operator
    when 'not_equal_to'
      relation.where.not(key => vals)
    when 'contains'
      apply_contains_filter(relation, key, vals)
    when 'does_not_contain'
      apply_does_not_contain_filter(relation, key, vals)
    when 'is_greater_than'
      apply_column_comparison(relation, key, vals.first, '>')
    when 'is_less_than'
      apply_column_comparison(relation, key, vals.first, '<')
    when 'days_before'
      target = Date.current - vals.first.to_i.days
      relation.where("#{Opportunity.table_name}.#{key}::date = ?", target)
    else
      relation.where(key => vals)
    end
  end

  def apply_column_comparison(relation, key, val, operator)
    sql = OpportunityDateComparison.sql_fragment(Opportunity, key, operator)
    relation.where(sql, OpportunityDateComparison.bound_value(Opportunity, key, val))
  end

  def apply_contains_filter(relation, key, vals)
    queries = vals.map { |v| "%#{ActiveRecord::Base.sanitize_sql_like(v.to_s)}%" }
    clause = queries.map.with_index { |_, i| "#{Opportunity.table_name}.#{key} ILIKE :val_#{i}" }.join(' OR ')
    params = queries.each_with_index.to_h { |q, i| [:"val_#{i}", q] }
    relation.where(clause, params)
  end

  def apply_does_not_contain_filter(relation, key, vals)
    queries = vals.map { |v| "%#{ActiveRecord::Base.sanitize_sql_like(v.to_s)}%" }
    clause = queries.map.with_index { |_, i| "#{Opportunity.table_name}.#{key} NOT ILIKE :val_#{i}" }.join(' AND ')
    params = queries.each_with_index.to_h { |q, i| [:"val_#{i}", q] }
    relation.where("#{Opportunity.table_name}.#{key} IS NULL OR (#{clause})", params)
  end

  def apply_custom_attribute_value_filter(relation, key, vals, operator)
    case operator
    when 'not_equal_to'
      relation.where('custom_attributes->>:key NOT IN (:values) OR NOT (custom_attributes ? :key) OR custom_attributes->>:key IS NULL',
                     key: key, values: vals.map(&:to_s))
    when 'is_greater_than'
      apply_custom_attribute_comparison(relation, key, vals.first, '>')
    when 'is_less_than'
      apply_custom_attribute_comparison(relation, key, vals.first, '<')
    when 'days_before'
      target_date = (Date.current - vals.first.to_i.days).strftime('%Y-%m-%d')
      relation.where(
        "(CASE WHEN custom_attributes->>:key ~ '^\\d{4}-\\d{2}-\\d{2}' THEN (custom_attributes->>:key)::date ELSE NULL END) = :val::date",
        key: key, val: target_date
      )
    else
      relation.where('custom_attributes->>:key IN (:values)', key: key, values: vals.map(&:to_s))
    end
  end

  def apply_custom_attribute_comparison(relation, key, val, comp_op)
    val_str = val.to_s
    if val_str.match?(/^\d{4}-\d{2}-\d{2}/)
      relation.where(
        "(CASE WHEN custom_attributes->>:key ~ '^\\d{4}-\\d{2}-\\d{2}' THEN (custom_attributes->>:key)::date ELSE NULL END) #{comp_op} :val::date",
        key: key, val: val_str[0..9]
      )
    elsif val_str.match?(/^-?\d+(\.\d+)?$/)
      relation.where(
        "(CASE WHEN custom_attributes->>:key ~ '^-?\\d+(\\.\\d+)?$' THEN (custom_attributes->>:key)::numeric ELSE NULL END) #{comp_op} :val::numeric",
        key: key, val: val_str
      )
    else
      relation
    end
  end

  def apply_search(relation)
    return relation if @params[:q].blank?

    query = ActiveRecord::Base.sanitize_sql_like(@params[:q])
    search_clause = <<~SQL.squish
      #{Opportunity.table_name}.title ILIKE :q
      OR #{Contact.table_name}.name ILIKE :q
      OR #{Opportunity.table_name}.campaign_name ILIKE :q
      OR #{Opportunity.table_name}.campaign_adset_name ILIKE :q
      OR #{Opportunity.table_name}.campaign_ad_name ILIKE :q
      OR #{Opportunity.table_name}.campaign_platform ILIKE :q
    SQL

    relation.left_joins(:contact).where(search_clause, q: "%#{query}%")
  end

  def apply_sort(relation)
    case @params[:sort_by]
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
end
