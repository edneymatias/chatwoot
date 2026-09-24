# frozen_string_literal: true

Custom::ScoutV2::RoutingContext = Struct.new(:opportunity, :pending_fields, keyword_init: true)
