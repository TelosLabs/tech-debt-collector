# frozen_string_literal: true

module TechDebt
  module Github
    # Read-only view over a pull request's changed Ruby files and diffs.
    class PullRequest
      HUNK_HEADER = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/

      def initialize(client, repo, number)
        @client = client
        @repo = repo
        @number = number
      end

      # Returns [changed_rb_files, patches_by_file].
      def ruby_file_index
        files = []
        patches = {}
        @client.pull_request_files(@repo, @number).each do |file|
          next unless file.filename.end_with?(".rb")

          files << file.filename
          patches[file.filename] = file.patch.to_s
        end
        [files.uniq, patches]
      end

      # Issue references (Fixes/Closes/Resolves #N) from the PR body and commits.
      def linked_issue_numbers(pattern)
        nums = []
        @client.pull_request(@repo, @number).body.to_s.scan(pattern) { nums << Regexp.last_match(1).to_i }
        @client.pull_request_commits(@repo, @number).each do |commit|
          commit.commit&.message.to_s.scan(pattern) { nums << Regexp.last_match(1).to_i }
        end
        nums.uniq.sort
      end

      # Set of new-file line numbers added by the diff in +patch+.
      def self.added_lines(patch)
        added = Set.new
        new_line = nil
        patch.to_s.each_line do |line|
          if (match = line.match(HUNK_HEADER))
            new_line = match[1].to_i
          elsif new_line
            new_line = advance(added, line, new_line)
          end
        end
        added
      end

      def self.advance(added, line, new_line)
        if line.start_with?("+") && !line.start_with?("+++")
          added << new_line
          new_line + 1
        elsif line.start_with?("-") && !line.start_with?("---")
          new_line
        else
          new_line + 1
        end
      end
    end
  end
end
