json.id resource.id
json.app_id resource.app_id
json.status resource.enabled?
json.inbox resource.inbox&.slice(:id, :name)
json.account_id resource.account_id
json.hook_type resource.hook_type

if Current.account_user&.administrator?
  visible_properties = resource.app&.visible_properties || []
  source_settings = resource.respond_to?(:masked_settings) ? resource.masked_settings : resource.settings
  settings = (source_settings || {}).select { |key, _| visible_properties.include?(key.to_s) }

  json.settings settings
  json.reference_id resource.reference_id
end
