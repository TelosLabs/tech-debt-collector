# frozen_string_literal: true

require "spec_helper"
require "tech_debt/config"
require "tech_debt/github/client"

RSpec.describe TechDebt::Github::Client do
  describe ".repo" do
    it "returns the configured repo" do
      config = instance_double(TechDebt::Config, github: {"repo" => "acme/app"})
      expect(described_class.repo(config)).to eq("acme/app")
    end

    it "falls back to GITHUB_REPOSITORY when config repo is absent" do
      config = instance_double(TechDebt::Config, github: {})
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("GITHUB_REPOSITORY").and_return("acme/env")
      expect(described_class.repo(config)).to eq("acme/env")
    end

    it "raises when neither config repo nor GITHUB_REPOSITORY is set" do
      config = instance_double(TechDebt::Config, github: {})
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("GITHUB_REPOSITORY").and_return(nil)
      expect { described_class.repo(config) }.to raise_error(ArgumentError, /GITHUB_REPOSITORY/)
    end
  end

  describe ".resolve_token" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:fetch).and_call_original
    end

    it "prefers an explicit token_env when set" do
      allow(ENV).to receive(:[]).with("AGENT_TOKEN").and_return("explicit")
      expect(described_class.resolve_token("AGENT_TOKEN")).to eq("explicit")
    end

    it "falls back to GITHUB_TOKEN when token_env is blank" do
      allow(ENV).to receive(:[]).with("AGENT_TOKEN").and_return("  ")
      allow(ENV).to receive(:fetch).with("GITHUB_TOKEN").and_return("ghtoken")
      expect(described_class.resolve_token("AGENT_TOKEN")).to eq("ghtoken")
    end

    it "falls back to GITHUB_TOKEN when token_env is nil" do
      allow(ENV).to receive(:fetch).with("GITHUB_TOKEN").and_return("ghtoken")
      expect(described_class.resolve_token(nil)).to eq("ghtoken")
    end

    it "raises KeyError when GITHUB_TOKEN is absent" do
      allow(ENV).to receive(:fetch).with("GITHUB_TOKEN").and_raise(KeyError)
      expect { described_class.resolve_token(nil) }.to raise_error(KeyError)
    end
  end

  describe ".build" do
    it "enables auto_paginate so listings are not truncated at 30 per page" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("GITHUB_TOKEN").and_return("ghtoken")
      expect(described_class.build.auto_paginate).to be(true)
    end
  end
end
