# frozen_string_literal: true

class Custom::ScoutV2::Playbook::Catalog
  include Enumerable

  attr_reader :playbooks

  def initialize(playbooks = [])
    @playbooks = playbooks.to_a.freeze
    freeze
  end

  def each(&)
    playbooks.each(&)
  end

  def find_by_name(name)
    playbooks.find { |pb| pb.name == name }
  end
  alias [] find_by_name

  def ordered_by_priority
    playbooks.sort do |a, b|
      if a.priority && b.priority
        b.priority <=> a.priority
      elsif a.priority
        -1
      elsif b.priority
        1
      else
        0
      end
    end
  end
end
