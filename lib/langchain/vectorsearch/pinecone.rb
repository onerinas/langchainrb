# frozen_string_literal: true

module Langchain::Vectorsearch
  class Pinecone < Base
    #
    # Wrapper around Pinecone API.
    #
    # Gem requirements: gem "pinecone", "~> 0.1.6"
    #
    # Usage:
    # pinecone = Langchain::Vectorsearch::Pinecone.new(environment:, api_key:, index_name:, llm:, llm_api_key:)
    #

    # Initialize the Pinecone client
    # @param environment [String] The environment to use
    # @param api_key [String] The API key to use
    # @param index_name [String] The name of the index to use
    # @param llm [Object] The LLM client to use
    def initialize(environment:, api_key:, index_name:, llm:)
      depends_on "pinecone"
      require "pinecone"

      ::Pinecone.configure do |config|
        config.api_key = api_key
        config.environment = environment
      end

      @client = ::Pinecone::Client.new
      @index_name = index_name

      super(llm: llm)
    end

    # Add a list of texts to the index
    # @param texts [Array] The list of texts to add
    # @param ids [Array] The list of IDs to add
    # @param namespace [String] The namespace to add the texts to
    # @param metadata [Hash] The metadata to use for the texts
    # @return [Hash] The response from the server
    def add_texts(texts:, ids: [], namespace: "", metadata: nil)
      vectors = texts.map.with_index do |text, i|
        {
          id: ids[i] ? ids[i].to_s : SecureRandom.uuid,
          metadata: metadata || {content: text},
          values: llm.embed(text: text)
        }
      end

      index = client.index(index_name)

      index.upsert(vectors: vectors, namespace: namespace)
    end

    # Update a list of texts in the index
    # @param texts [Array] The list of texts to update
    # @param ids [Array] The list of IDs to update
    # @param namespace [String] The namespace to update the texts in
    # @param metadata [Hash] The metadata to use for the texts
    # @return [Array] The response from the server
    def update_texts(texts:, ids:, namespace: "", metadata: nil)
      texts.map.with_index do |text, i|
        # Pinecone::Vector#update ignore args when it is empty
        index.update(
          namespace: namespace,
          id: ids[i].to_s,
          values: llm.embed(text: text),
          set_metadata: metadata
        )
      end
    end

    # Create the index with the default schema
    # @return [Hash] The response from the server
    def create_default_schema
      client.create_index(
        metric: DEFAULT_METRIC,
        name: index_name,
        dimension: default_dimension
      )
    end

    # Delete the index
    # @return [Hash] The response from the server
    def destroy_default_schema
      client.delete_index(index_name)
    end

    # Get the default schema
    # @return [Pinecone::Vector] The default schema
    def get_default_schema
      index
    end

    # Search for similar texts
    # @param query [String] The text to search for
    # @param k [Integer] The number of results to return
    # @param namespace [String] The namespace to search in
    # @param filter [String] The filter to use
    # @return [Array] The list of results
    def similarity_search(
      query:,
      k: 4,
      namespace: "",
      filter: nil
    )
      embedding = llm.embed(text: query)

      similarity_search_by_vector(
        embedding: embedding,
        k: k,
        namespace: namespace,
        filter: filter
      )
    end

    # Search for similar texts by embedding
    # @param embedding [Array] The embedding to search for
    # @param k [Integer] The number of results to return
    # @param namespace [String] The namespace to search in
    # @param filter [String] The filter to use
    # @return [Array] The list of results
    def similarity_search_by_vector(embedding:, k: 4, namespace: "", filter: nil)
      index = client.index(index_name)

      query_params = {
        vector: embedding,
        namespace: namespace,
        filter: filter,
        top_k: k,
        include_values: true,
        include_metadata: true
      }.compact

      response = index.query(query_params)
      response.dig("matches")
    end

    # Ask a question and return the answer
    # @param question [String] The question to ask
    # @param namespace [String] The namespace to search in
    # @param filter [String] The filter to use
    # @return [String] The answer to the question
    def ask(question:, namespace: "", filter: nil)
      search_results = similarity_search(query: question, namespace: namespace, filter: filter)

      context = search_results.map do |result|
        result.dig("metadata").to_s
      end
      context = context.join("\n---\n")

      prompt = generate_prompt(question: question, context: context)

      llm.chat(prompt: prompt)
    end

    # Pinecone index
    # @return [Object] The Pinecone index
    private def index
      client.index(index_name)
    end
  end
end
