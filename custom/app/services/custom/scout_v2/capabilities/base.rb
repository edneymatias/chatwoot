# frozen_string_literal: true

class Custom::ScoutV2::Capabilities::Base
  attr_reader :provider, :conversation

  def initialize(provider:, conversation:)
    @provider = provider
    @conversation = conversation
  end

  class OperationBuilder
    def initialize(name)
      @name = name.to_s
      @inputs = []
      @output = nil
    end

    def input(name, type: 'string', required: true, description: nil)
      @inputs << Custom::ScoutV2::Capabilities::Operation::Input.new(
        name: name.to_s,
        type: type.to_s,
        required: required,
        description: description
      )
    end

    def output(required:, shape:)
      @output = Custom::ScoutV2::Capabilities::Operation::Output.new(
        required: required.map(&:to_s),
        shape: shape.to_sym
      )
    end

    def build
      Custom::ScoutV2::Capabilities::Operation.new(
        name: @name,
        inputs: @inputs.freeze,
        output: @output || Custom::ScoutV2::Capabilities::Operation::Output.new(required: [], shape: :record)
      )
    end
  end

  class << self
    def capability_name(name = nil)
      if name
        @capability_name = name.to_s
      else
        @capability_name
      end
    end

    def operation(name, &block)
      @operations ||= {}
      builder = OperationBuilder.new(name)
      builder.instance_eval(&block) if block
      @operations[name.to_s] = builder.build
    end

    def operations
      @operations ||= {}
    end
  end
end
