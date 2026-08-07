class AddUniqueIndexOnIchatrOpportunitiesOriginConversation < ActiveRecord::Migration[7.1]
  def change
    remove_index :ichatr_opportunities, :origin_conversation_id
    add_index :ichatr_opportunities, :origin_conversation_id, unique: true, where: 'origin_conversation_id IS NOT NULL'
  end
end
