# frozen_string_literal: true

module Langchain::Vectorsearch
  class Milvus < Base
    #
    # Wrapper around Milvus REST APIs.
    #
    # Gem requirements: gem "milvus", "~> 0.9.0"
    #
    # Usage:
    # milvus = Langchain::Vectorsearch::Milvus.new(url:, index_name:, llm:, api_key:)
    #

    def initialize(url:, index_name:, llm:, api_key: nil)
      depends_on "milvus"
      require "milvus"

      @client = ::Milvus::Client.new(url: url)
      @index_name = index_name

      super(llm: llm)
    end

    def add_texts(texts:)
      client.entities.insert(
        collection_name: index_name,
        num_rows: Array(texts).size,
        fields_data: [
          {
            field_name: "content",
            type: ::Milvus::DATA_TYPES["varchar"],
            field: Array(texts)
          }, {
            field_name: "vectors",
            type: ::Milvus::DATA_TYPES["binary_vector"],
            field: Array(texts).map { |text| llm.embed(text: text) }
          }
        ]
      )
    end

    # TODO: Add update_texts method

    # Create default schema
    # @return [Hash] The response from the server
    def create_default_schema
      client.collections.create(
        auto_id: true,
        collection_name: index_name,
        description: "Default schema created by Vectorsearch",
        fields: [
          {
            name: "id",
            is_primary_key: true,
            autoID: true,
            data_type: ::Milvus::DATA_TYPES["int64"]
          }, {
            name: "content",
            is_primary_key: false,
            data_type: ::Milvus::DATA_TYPES["varchar"],
            type_params: [
              {
                key: "max_length",
                value: "32768" # Largest allowed value
              }
            ]
          }, {
            name: "vectors",
            data_type: ::Milvus::DATA_TYPES["binary_vector"],
            is_primary_key: false,
            type_params: [
              {
                key: "dim",
                value: default_dimension.to_s
              }
            ]
          }
        ]
      )
    end

    # Get the default schema
    # @return [Hash] The response from the server
    def get_default_schema
      client.collections.get(collection_name: index_name)
    end

    # Delete default schema
    # @return [Hash] The response from the server
    def destroy_default_schema
      client.collections.delete(collection_name: index_name)
    end

    def similarity_search(query:, k: 4)
      embedding = llm.embed(text: query)

      similarity_search_by_vector(
        embedding: embedding,
        k: k
      )
    end

    def similarity_search_by_vector(embedding:, k: 4)
      client.search(
        collection_name: index_name,
        top_k: k.to_s,
        vectors: [embedding],
        dsl_type: 1,
        params: "{\"nprobe\": 10}",
        anns_field: "content",
        metric_type: "L2"
      )
    end
  end
end
