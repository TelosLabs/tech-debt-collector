# frozen_string_literal: true

require "octokit"

module TechDebt
  module Github
    # Builds Octokit clients and resolves the target repo from config/env.
    # Centralizes token handling shared by issue creation, verification, and
    # PR delta reporting.
    module Client
      module_function

      # Builds an Octokit client. When +token_env+ is given and set, that token
      # is used; otherwise it falls back to GITHUB_TOKEN (raising if absent).
      # auto_paginate is enabled so comment/file/commit listings are complete
      # (the default 30-per-page cap would silently truncate large PRs and break
      # comment upsert dedup).
      def build(token_env: nil)
        client = Octokit::Client.new(access_token: resolve_token(token_env))
        client.auto_paginate = true
        client
      end

      def repo(config)
        value = config.github["repo"] || ENV["GITHUB_REPOSITORY"]
        raise ArgumentError, "github.repo or GITHUB_REPOSITORY is required" if value.nil? || value.to_s.empty?

        value
      end

      def resolve_token(token_env)
        explicit = token_env && ENV[token_env]
        return explicit unless explicit.to_s.strip.empty?

        ENV.fetch("GITHUB_TOKEN")
      end
    end
  end
end
