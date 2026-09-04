class OpportunityDateComparison
  DATE_ONLY_VALUE = /\A\d{4}-\d{2}-\d{2}\z/

  # Matches upstream Chatwoot's own date-filter semantics for Contacts/Conversations
  # (app/services/filter_service.rb#coerce_lt_gt_value, app/helpers/filters/filter_helper.rb
  # #date_filter): a whole-day comparison via SQL `::date` casting on both sides, anchored to
  # the server/UTC day boundary rather than any per-account timezone. Chatwoot has no
  # account-wide timezone setting today (only individual inboxes have one, via Business
  # Hours), so this is kept consistent with the rest of the product's date filters rather
  # than being uniquely "more correct" for Opportunities alone — revisit if that changes.
  def self.sql_fragment(model, key, operator)
    return "#{model.table_name}.#{key} #{operator} ?" unless date_column?(model, key)

    "(#{model.table_name}.#{key})::date #{operator} ?"
  end

  def self.bound_value(model, key, val)
    return val unless date_column?(model, key) && val.to_s.match?(DATE_ONLY_VALUE)

    Date.iso8601(val)
  end

  def self.date_column?(model, key)
    %i[date datetime time].include?(model.type_for_attribute(key).type)
  end
end
