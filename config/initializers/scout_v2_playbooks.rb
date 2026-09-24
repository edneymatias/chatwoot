# frozen_string_literal: true

Rails.application.config.after_initialize do
  Custom::ScoutV2::Playbook::Validator.call!(Custom::ScoutV2::Playbook::Loader.load_all)
end
