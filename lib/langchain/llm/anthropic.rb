# frozen_string_literal: true

module Langchain::LLM
  #
  # Wrapper around Anthropic APIs.
  #
  # Gem requirements:
  #   gem "anthropic", "~> 0.1.0"
  #
  # Usage:
  #     anthorpic = Langchain::LLM::Anthropic.new(api_key:)
  #
  class Anthropic < Base
    DEFAULTS = {
      temperature: 0.0,
      completion_model_name: "claude-2"
    }.freeze

    # TODO: Implement token length validator for Anthropic
    # LENGTH_VALIDATOR = Langchain::Utils::TokenLength::AnthropicValidator

    def initialize(api_key:, llm_options: {}, default_options: {})
      depends_on "anthropic"
      require "anthropic"

      @client = ::Anthropic::Client.new(access_token: api_key, **llm_options)
      @defaults = DEFAULTS.merge(default_options)
    end

    #
    # Generate a completion for a given prompt
    #
    # @param prompt [String] The prompt to generate a completion for
    # @param params [Hash] extra parameters passed to Anthropic::Client#complete
    # @return [String] The completion
    #
    def complete(prompt:, **params)
      parameters = compose_parameters @defaults[:completion_model_name], params

      parameters[:prompt] = prompt

      # TODO: Implement token length validator for Anthropic
      # parameters[:max_tokens_to_sample] = validate_max_tokens(prompt, parameters[:completion_model_name])

      response = client.complete(parameters: parameters)
      response.dig("completion")
    end

    private

    def compose_parameters(model, params)
      default_params = {model: model, temperature: @defaults[:temperature]}

      default_params.merge(params)
    end

    # TODO: Implement token length validator for Anthropic
    # def validate_max_tokens(messages, model)
    #   LENGTH_VALIDATOR.validate_max_tokens!(messages, model)
    # end
  end
end
