class Whatsapp::LiquidTemplateProcessorService
  LIQUID_EXPRESSION = /\{\{|\{%/

  pattr_initialize [:campaign!, :contact!]

  def process_template_params(template_params)
    return template_params if template_params.blank?

    template_params_copy = template_params.deep_dup
    processed_params = template_params_copy['processed_params']

    return template_params_copy if processed_params.blank?

    rendered_params = render_liquid(processed_params)
    return nil if blank_render?(processed_params, rendered_params)

    template_params_copy.merge('processed_params' => rendered_params)
  end

  private

  def render_liquid(processed_params)
    render_value(processed_params)
  rescue Liquid::Error
    processed_params
  end

  def render_value(value)
    case value
    when Hash then value.transform_values { |v| render_value(v) }
    when Array then value.map { |v| render_value(v) }
    when String then render_string(value)
    else value
    end
  end

  def render_string(string)
    return string unless string.match?(LIQUID_EXPRESSION)

    Liquid::Template.parse(string).render!(drops)
  end

  def drops
    {
      'contact' => ContactDrop.new(contact),
      'agent' => UserDrop.new(campaign.sender),
      'inbox' => InboxDrop.new(campaign.inbox),
      'account' => AccountDrop.new(campaign.account)
    }
  end

  def blank_render?(original, rendered)
    case original
    when Hash then blank_render_in_hash?(original, rendered)
    when Array then blank_render_in_array?(original, rendered)
    when String then original.match?(LIQUID_EXPRESSION) && rendered.to_s.blank?
    else false
    end
  end

  def blank_render_in_hash?(original, rendered)
    return false unless rendered.is_a?(Hash)

    original.any? { |key, value| blank_render?(value, rendered[key]) }
  end

  def blank_render_in_array?(original, rendered)
    return false unless rendered.is_a?(Array)

    original.each_with_index.any? { |value, index| blank_render?(value, rendered[index]) }
  end
end
