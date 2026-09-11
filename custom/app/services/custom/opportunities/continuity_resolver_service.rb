# frozen_string_literal: true

class Custom::Opportunities::ContinuityResolverService
  ContinuityDecision = Struct.new(:outcome, :opportunity, :candidates, :reason, keyword_init: true)

  def initialize(account:, contact:, declared_opportunity_id: nil)
    @account = account
    @contact = contact
    @declared_opportunity_id = declared_opportunity_id
  end

  def call
    candidates = fetch_candidates

    return decision_for_no_candidates(candidates) if candidates.empty?

    if @declared_opportunity_id.present?
      decision_for_declared_candidate(candidates)
    else
      decision_for_undeclared_candidates(candidates)
    end
  end

  private

  def fetch_candidates
    return [] unless @account.present? && @contact.present?
    return [] unless @contact.account_id == @account.id

    Opportunity.where(account_id: @account.id, contact_id: @contact.id, status: :open).to_a
  end

  def decision_for_no_candidates(candidates)
    ContinuityDecision.new(
      outcome: :create_new,
      opportunity: nil,
      candidates: candidates,
      reason: 'No open opportunities found for contact'
    )
  end

  def decision_for_declared_candidate(candidates)
    matched = candidates.find { |opp| opp.id == @declared_opportunity_id.to_i }

    if matched
      ContinuityDecision.new(
        outcome: :reuse,
        opportunity: matched,
        candidates: candidates,
        reason: "Matched declared opportunity ##{matched.id}"
      )
    else
      ContinuityDecision.new(
        outcome: :ambiguous,
        opportunity: nil,
        candidates: candidates,
        reason: "Declared opportunity ID #{@declared_opportunity_id} is not among the #{candidates.size} open opportunity candidate(s) for contact"
      )
    end
  end

  def decision_for_undeclared_candidates(candidates)
    ContinuityDecision.new(
      outcome: :ambiguous,
      opportunity: nil,
      candidates: candidates,
      reason: "Contact has #{candidates.size} open opportunity candidate(s) but no opportunity ID was declared"
    )
  end
end
