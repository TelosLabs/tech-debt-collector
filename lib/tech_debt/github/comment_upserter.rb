# frozen_string_literal: true

require "octokit"

module TechDebt
  module Github
    # Posts or updates a single PR comment identified by a hidden marker, so
    # repeated runs (e.g. on every `synchronize`) edit one comment instead of
    # stacking duplicates.
    class CommentUpserter
      def initialize(client:, repo:, pr_number:)
        @client = client
        @repo = repo
        @pr_number = pr_number
      end

      def upsert(body, marker:)
        existing = find_existing(marker)
        if existing
          @client.update_comment(@repo, existing.id, body)
        else
          @client.add_comment(@repo, @pr_number, body)
        end
      end

      private

      def find_existing(marker)
        @client.issue_comments(@repo, @pr_number).find { |comment| comment.body.to_s.include?(marker) }
      end
    end
  end
end
