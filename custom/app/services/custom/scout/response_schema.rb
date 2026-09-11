# frozen_string_literal: true

class Custom::Scout::ResponseSchema < RubyLLM::Schema
  string :reasoning, description: "Scout's internal thought process"
  string :response, description: 'The message to send to the customer'
end
