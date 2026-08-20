# frozen_string_literal: true

class Api::V1::Accounts::Scouts::ProductCatalogItemsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :set_scout

  def index
    render json: current_catalog
  end

  def create
    item = {
      'id' => SecureRandom.uuid,
      'name' => item_params[:name].to_s,
      'pricing' => item_params[:pricing].to_s,
      'value_proposition' => item_params[:value_proposition].to_s
    }

    new_catalog = current_catalog + [item]
    @scout.update!(product_catalog: new_catalog)

    render json: item, status: :created
  end

  def update
    updated_item = nil
    new_catalog = current_catalog.map do |item|
      if item['id'] == params[:id]
        updated_item = item.merge(
          'name' => item_params[:name] || item['name'],
          'pricing' => item_params[:pricing] || item['pricing'],
          'value_proposition' => item_params[:value_proposition] || item['value_proposition']
        )
      else
        item
      end
    end

    if updated_item.nil?
      render json: { error: 'Product catalog item not found' }, status: :not_found
      return
    end

    @scout.update!(product_catalog: new_catalog)
    render json: updated_item
  end

  def destroy
    new_catalog = current_catalog.reject { |item| item['id'] == params[:id] }
    @scout.update!(product_catalog: new_catalog)
    head :ok
  end

  private

  def set_scout
    @scout = Current.account.scouts.find(params[:scout_id])
  end

  def check_authorization
    super(Scout)
  end

  def current_catalog
    raw = @scout.product_catalog
    return [] if raw.blank?

    raw.is_a?(Array) ? raw : []
  end

  def item_params
    params.permit(:name, :pricing, :value_proposition)
  end
end
