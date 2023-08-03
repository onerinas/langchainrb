# frozen_string_literal: true

RSpec.describe Langchain::Utils::TokenLength::OpenAIValidator do
  describe "#validate_max_tokens!" do
    subject { described_class.validate_max_tokens!(content, model) }

    context "with text argument" do
      context "when the text is too long" do
        let(:content) { "lorem ipsum" * 9000 }
        let(:model) { "text-davinci-003" }

        it "raises an error" do
          expect {
            subject
          }.to raise_error(Langchain::Utils::TokenLength::TokenLimitExceeded, "This model's maximum context length is 4097 tokens, but the given text is 45000 tokens long.")
        end
      end

      context "when the text is not too long" do
        let(:content) { "lorem ipsum" * 100 }
        let(:model) { "gpt-4" }

        it "does not raise an error" do
          expect { subject }.not_to raise_error
        end

        it "returns the correct max_tokens" do
          expect(subject).to eq(7892)
        end
      end

      context "when the token is equal to the limit" do
        let(:content) { "lorem ipsum" * 9000 }
        let(:model) { "text-embedding-ada-002" }

        before do
          allow(described_class).to receive(:token_length).and_return(
            Langchain::Utils::TokenLength::OpenAIValidator::TOKEN_LIMITS[model]
          )
        end

        it "does not raise an error" do
          expect { subject }.not_to raise_error
        end

        it "returns the correct max_tokens" do
          expect(subject).to eq(0)
        end
      end
    end

    context "with array argument" do
      let(:content) { ["lorem ipsum" * 100, "lorem ipsum" * 100] }
      let(:model) { "gpt-4" }

      context "when the text is not too long" do
        it "returns the correct max_tokens" do
          expect(subject).to eq(7588)
        end
      end
    end
  end
end
