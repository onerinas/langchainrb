# frozen_string_literal: true

module Langchain::Vectorsearch
  class Pgvector < Base
    #
    # The PostgreSQL vector search adapter
    #
    # Gem requirements: gem "pgvector", "~> 0.2"
    #
    # Usage:
    # pgvector = Langchain::Vectorsearch::Pgvector.new(url:, index_name:, llm:, namespace_column: nil, namespace: nil)
    #

    # The operators supported by the PostgreSQL vector search adapter
    OPERATORS = {
      "cosine_distance" => "cosine",
      "euclidean_distance" => "euclidean"
    }
    DEFAULT_OPERATOR = "cosine_distance"

    attr_reader :db, :operator, :table_name, :namespace_column, :namespace, :documents_table

    # @param url [String] The URL of the PostgreSQL database
    # @param index_name [String] The name of the table to use for the index
    # @param llm [Object] The LLM client to use
    # @param namespace [String] The namespace to use for the index when inserting/querying
    def initialize(url:, index_name:, llm:, namespace: nil)
      depends_on "sequel"
      require "sequel"
      depends_on "pgvector"
      require "pgvector"

      @db = Sequel.connect(url)

      @table_name = index_name

      @namespace_column = "namespace"
      @namespace = namespace
      @operator = OPERATORS[DEFAULT_OPERATOR]

      super(llm: llm)
    end

    def documents_model
      Class.new(Sequel::Model(table_name.to_sym)) do
        plugin :pgvector, :vectors
      end
    end

    # Upsert a list of texts to the index
    # @param texts [Array<String>] The texts to add to the index
    # @param ids [Array<Integer>] The ids of the objects to add to the index, in the same order as the texts
    # @return [PG::Result] The response from the database including the ids of
    # the added or updated texts.
    def upsert_texts(texts:, ids:)
      data = texts.zip(ids).flat_map do |(text, id)|
        {id: id, content: text, vectors: llm.embed(text: text).to_s, namespace: namespace}
      end
      # @db[table_name.to_sym].multi_insert(data, return: :primary_key)
      @db[table_name.to_sym]
        .insert_conflict(
          target: :id,
          update: {content: Sequel[:excluded][:content], vectors: Sequel[:excluded][:vectors]}
        )
        .multi_insert(data, return: :primary_key)
    end

    # Add a list of texts to the index
    # @param texts [Array<String>] The texts to add to the index
    # @param ids [Array<String>] The ids to add to the index, in the same order as the texts
    # @return [Array<Integer>] The the ids of the added texts.
    def add_texts(texts:, ids: nil)
      if ids.nil? || ids.empty?
        data = texts.map do |text|
          {content: text, vectors: llm.embed(text: text).to_s, namespace: namespace}
        end

        @db[table_name.to_sym].multi_insert(data, return: :primary_key)
      else
        upsert_texts(texts: texts, ids: ids)
      end
    end

    # Update a list of ids and corresponding texts to the index
    # @param texts [Array<String>] The texts to add to the index
    # @param ids [Array<String>] The ids to add to the index, in the same order as the texts
    # @return [Array<Integer>] The ids of the updated texts.
    def update_texts(texts:, ids:)
      upsert_texts(texts: texts, ids: ids)
    end

    # Create default schema
    # @return [PG::Result] The response from the database
    def create_default_schema
      db.run "CREATE EXTENSION IF NOT EXISTS vector"
      namespace = namespace_column
      vector_dimension = default_dimension
      db.create_table? table_name.to_sym do
        primary_key :id
        text :content
        column :vectors, "vector(#{vector_dimension})"
        text namespace.to_sym, default: nil
      end
    end

    # TODO: Add destroy_default_schema method

    # Search for similar texts in the index
    # @param query [String] The text to search for
    # @param k [Integer] The number of top results to return
    # @return [Array<Hash>] The results of the search
    def similarity_search(query:, k: 4)
      embedding = llm.embed(text: query)

      similarity_search_by_vector(
        embedding: embedding,
        k: k
      )
    end

    # Search for similar texts in the index by the passed in vector.
    # You must generate your own vector using the same LLM that generated the embeddings stored in the Vectorsearch DB.
    # @param embedding [Array<Float>] The vector to search for
    # @param k [Integer] The number of top results to return
    # @return [Array<Hash>] The results of the search
    def similarity_search_by_vector(embedding:, k: 4)
      db.transaction do # BEGIN
        documents_model
          .nearest_neighbors(:vectors, embedding, distance: operator).limit(k)
          .where(namespace_column.to_sym => namespace)
      end
    end

    # Ask a question and return the answer
    # @param question [String] The question to ask
    # @yield [String] Stream responses back one String at a time
    # @return [String] The answer to the question
    def ask(question:, &block)
      search_results = similarity_search(query: question)

      context = search_results.map do |result|
        result.content.to_s
      end
      context = context.join("\n---\n")

      prompt = generate_prompt(question: question, context: context)

      llm.chat(prompt: prompt, &block)
    end
  end
end
