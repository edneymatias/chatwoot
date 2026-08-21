# frozen_string_literal: true

class Custom::Scout::Tools::SearchKnowledgeBase < Custom::Scout::Tools::BaseTool
  description 'Search knowledge base for relevant questions and answers using semantic similarity'

  param :query, type: :string, desc: 'The question or topic to search for in the knowledge base', required: true

  def name
    'search_knowledge_base'
  end

  def execute(query:)
    return 'Nenhum termo de busca fornecido.' if query.blank?

    query_vector = Custom::Scout::EmbeddingConfig.for(account).embed(query)
    return 'Nenhuma informação relevante encontrada na base de conhecimento.' if query_vector.blank?

    matches = scout.scout_knowledge_embeddings
                   .nearest_neighbors(:embedding, query_vector, distance: 'cosine')
                   .limit(5)

    return "Nenhuma informação relevante encontrada na base de conhecimento para: #{query}" if matches.empty?

    matches.map { |m| "Pergunta: #{m.question}\nResposta: #{m.answer}" }.join("\n\n")
  rescue StandardError => e
    Rails.logger.error "[Scout SearchKnowledgeBase] Error: #{e.message}"
    "Erro ao consultar base de conhecimento: #{e.message}"
  end
end
