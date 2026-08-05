class Reports::OpportunityAttributeSummaryBuilder
  pattr_initialize [:account!, :definition!, :range]

  def build
    attribute_key = definition.attribute_key
    attribute_values = Array(definition.attribute_values)
    open_hash = open_totals_by_value(attribute_key)
    won_scope, lost_scope = closed_scopes

    rows = attribute_values.map { |val| value_row(val, attribute_key, open_hash, won_scope, lost_scope) }
    rows << no_value_row(open_hash, won_scope, lost_scope, attribute_key, attribute_values)

    {
      definition: {
        id: definition.id,
        attribute_key: definition.attribute_key,
        attribute_display_name: definition.attribute_display_name
      },
      rows: rows
    }
  end

  private

  attr_reader :account, :definition, :range

  def open_totals_by_value(attribute_key)
    raw_open = account.opportunities.open
                      .group(Arel.sql("custom_attributes->>'#{attribute_key}'"))
                      .pluck(Arel.sql("custom_attributes->>'#{attribute_key}'"), Arel.sql('COUNT(*)'), Arel.sql('SUM(value)'))

    raw_open.each_with_object({}) do |(val, count, sum), h|
      h[val] = { count: count.to_i, total_value: (sum || 0).to_f }
    end
  end

  def closed_scopes
    closed_base = range ? account.opportunities.where(closed_at: range) : account.opportunities
    [closed_base.where(status: :won), closed_base.where(status: :lost)]
  end

  def value_row(val, attribute_key, open_hash, won_scope, lost_scope)
    opp_data = open_hash[val] || { count: 0, total_value: 0.0 }
    won = count_and_value(won_scope.where("custom_attributes->>'#{attribute_key}' = ?", val))
    lost = count_and_value(lost_scope.where("custom_attributes->>'#{attribute_key}' = ?", val))

    {
      value: val,
      opportunities_count: opp_data[:count],
      total_value: opp_data[:total_value],
      won_count: won[:count],
      won_value: won[:value],
      lost_count: lost[:count],
      lost_value: lost[:value],
      avg_time_to_close: avg_time_to_close_for_value(won_scope, attribute_key, val)
    }
  end

  def count_and_value(scope)
    count, sum = scope.pick(Arel.sql('COUNT(*)'), Arel.sql('SUM(value)'))
    { count: count.to_i, value: (sum || 0).to_f }
  end

  def avg_time_to_close_for_value(scope, attribute_key, val)
    opps = scope.where("custom_attributes->>'#{attribute_key}' = ?", val)
                .pluck(:created_at, :closed_at).select { |_c, cl| cl }
    average_days(opps)
  end

  def no_value_row(open_hash, won_scope, lost_scope, attribute_key, attribute_values)
    no_count, no_total = no_value_open_totals(open_hash, attribute_values)
    no_scope_condition = no_value_condition(attribute_key, attribute_values)
    won = count_and_value(won_scope.where(no_scope_condition))
    lost = count_and_value(lost_scope.where(no_scope_condition))

    {
      value: nil,
      opportunities_count: no_count,
      total_value: no_total,
      won_count: won[:count],
      won_value: won[:value],
      lost_count: lost[:count],
      lost_value: lost[:value],
      avg_time_to_close: average_days(won_scope.where(no_scope_condition).pluck(:created_at, :closed_at).select { |_c, cl| cl })
    }
  end

  def no_value_open_totals(open_hash, attribute_values)
    open_hash.reduce([0, 0.0]) do |(count, total), (raw_val, data)|
      next [count, total] unless raw_val.nil? || attribute_values.exclude?(raw_val)

      [count + data[:count], total + data[:total_value]]
    end
  end

  def no_value_condition(attribute_key, attribute_values)
    return Arel.sql("custom_attributes->>'#{attribute_key}' IS NULL") if attribute_values.blank?

    sql_list = attribute_values.map { |v| ActiveRecord::Base.connection.quote(v) }.join(',')
    Arel.sql(
      "custom_attributes->>'#{attribute_key}' IS NULL OR " \
      "custom_attributes->>'#{attribute_key}' NOT IN (#{sql_list})"
    )
  end

  def average_days(rows)
    return nil if rows.empty?

    (rows.sum { |created, closed| (closed - created) / 1.day } / rows.size).round(2)
  end
end
