# frozen_string_literal: true

class CreateIchatrScoutKnowledgeEmbeddings < ActiveRecord::Migration[7.0]
  def up
    create_table :ichatr_scout_knowledge_embeddings do |t|
      t.bigint :account_id, null: false
      t.bigint :scout_id, null: false
      t.bigint :scout_knowledge_source_id, null: false
      t.text :question, null: false
      t.text :answer, null: false
      t.vector :embedding, limit: 768
      t.timestamps
    end

    add_index :ichatr_scout_knowledge_embeddings, :account_id, name: 'index_ichatr_scout_ke_on_account_id'
    add_index :ichatr_scout_knowledge_embeddings, :scout_id, name: 'index_ichatr_scout_ke_on_scout_id'
    add_index :ichatr_scout_knowledge_embeddings, :scout_knowledge_source_id, name: 'index_ichatr_scout_ke_on_source_id'
    add_index :ichatr_scout_knowledge_embeddings, :embedding, using: :hnsw, opclass: :vector_cosine_ops, name: 'idx_scout_knowledge_embeddings_hnsw'

    add_foreign_key :ichatr_scout_knowledge_embeddings, :accounts, on_delete: :cascade
    add_foreign_key :ichatr_scout_knowledge_embeddings, :ichatr_scouts, column: :scout_id, on_delete: :cascade
    add_foreign_key :ichatr_scout_knowledge_embeddings, :ichatr_scout_knowledge_sources, column: :scout_knowledge_source_id, on_delete: :cascade
  end

  def down
    drop_table :ichatr_scout_knowledge_embeddings, if_exists: true
  end
end
