class CreateMatiasPipelineCurrencySettings < ActiveRecord::Migration[7.1]
  def change
    create_table :matias_pipeline_currency_settings do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.string :currency, null: false, default: 'usd'

      t.timestamps
    end
  end
end
