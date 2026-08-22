# frozen_string_literal: true

class AddResponseTemplateToIchatrScoutTools < ActiveRecord::Migration[7.0]
  def change
    add_column :ichatr_scout_tools, :response_template, :text
  end
end
