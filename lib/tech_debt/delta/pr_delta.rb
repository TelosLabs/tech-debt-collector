# frozen_string_literal: true

require_relative "../github/client"
require_relative "../github/pull_request"
require_relative "../github/comment_upserter"
require_relative "../collectors/debride_collector"
require_relative "../collectors/complexity_collector"
require_relative "../collectors/flay_collector"
require_relative "../collectors/layer_collector"

module TechDebt
  module Delta
    # Per-PR debt delta: runs the static collectors against only the Ruby files
    # a PR changes, keeps findings that land on lines the PR added, and posts a
    # single (upserted) summary comment. No issues are created.
    class PrDelta
      MARKER = "<!-- wall_e_pr_delta -->"
      SEVERITY_EMOJI = {"high" => "🔴", "medium" => "🟡", "low" => "🟢"}.freeze
      SEVERITY_RANK = {"high" => 2, "medium" => 1, "low" => 0}.freeze
      # A finding is "high" once its score reaches this multiple of the collector's threshold.
      HIGH_SEVERITY_MULTIPLIER = 2
      # Score at/above which a leaked-business-logic finding counts as high severity.
      LEAKED_HIGH_SCORE = 8

      def initialize(config, pr_number:, dry_run: false)
        @config = config
        @pr_number = pr_number.to_i
        @dry_run = dry_run
        @repo = Github::Client.repo(config)
        @client = Github::Client.build
        @pull_request = Github::PullRequest.new(@client, @repo, @pr_number)
      end

      def run
        changed_files, patches = @pull_request.ruby_file_index
        findings = changed_files.empty? ? [] : delta_findings(changed_files, patches)
        post_comment(findings)
        summary(changed_files, findings)
      end

      private

      def delta_findings(changed_files, patches)
        added_by_file = patches.transform_values { |patch| Github::PullRequest.added_lines(patch) }
        collect(changed_files)
          .select { |candidate| touches_changed_lines?(candidate, added_by_file) }
          .select { |candidate| allowed_debt_type?(candidate) }
          .map { |candidate| candidate.merge(severity: severity_for(candidate)) }
      end

      def collect(files)
        [
          Collectors::DebrideCollector,
          Collectors::ComplexityCollector,
          Collectors::FlayCollector,
          Collectors::LayerCollector
        ].flat_map { |collector| collector.new(@config, files: files).call }
      end

      def touches_changed_lines?(candidate, added_by_file)
        added = added_by_file[candidate[:file]]
        return false if added.nil? || added.empty?

        first = candidate.fetch(:line, 0)
        last = candidate.fetch(:end_line, first)
        added.any? { |line| line.between?(first, last) }
      end

      def allowed_debt_type?(candidate)
        allowed = Array(@config.pr_delta["debt_types"]).map(&:to_s)
        allowed.empty? || allowed.include?(candidate[:type].to_s)
      end

      def post_comment(findings)
        body = format_comment(findings)
        if @dry_run
          warn "[wall-e] Dry run — PR delta comment would be:\n#{body}"
          return
        end

        Github::CommentUpserter
          .new(client: @client, repo: @repo, pr_number: @pr_number)
          .upsert(body, marker: MARKER)
      end

      def format_comment(findings)
        return no_findings_comment if findings.empty?

        rows = findings.sort_by { |f| -severity_rank(f) }.map { |f| finding_row(f) }
        [
          "## 🤖 wall-e debt delta",
          "",
          "Found **#{findings.size}** debt signal(s) on the lines this PR changed.",
          "",
          "| Severity | Type | Location | Detail |",
          "| --- | --- | --- | --- |",
          *rows,
          "",
          "_Static analysis on changed lines only. Run a full wall-e scan to file tracked issues._",
          "",
          MARKER
        ].join("\n")
      end

      def no_findings_comment
        [
          "## 🤖 wall-e debt delta",
          "",
          "✅ No new debt signals on the lines this PR changed.",
          "",
          MARKER
        ].join("\n")
      end

      def finding_row(finding)
        severity = finding[:severity]
        file = finding[:file].to_s.tr("|`", "/")
        location = "`#{file}:#{finding[:line]}`"
        detail = finding[:detail].to_s.tr("|", "/").gsub(/\s+/, " ").strip
        "| #{SEVERITY_EMOJI.fetch(severity, "🟡")} #{severity} | #{finding[:type]} | #{location} | #{detail} |"
      end

      def severity_rank(finding)
        SEVERITY_RANK.fetch(finding[:severity], 1)
      end

      def severity_for(finding)
        case finding[:type].to_s
        when "high_complexity"
          (finding[:score].to_f >= (@config.flog_threshold * HIGH_SEVERITY_MULTIPLIER)) ? "high" : "medium"
        when "structural_duplication"
          (finding[:score].to_f >= (@config.flay_threshold * HIGH_SEVERITY_MULTIPLIER)) ? "high" : "medium"
        when "dead_code"
          "low"
        else
          (finding[:score].to_i >= LEAKED_HIGH_SCORE) ? "high" : "medium"
        end
      end

      def summary(changed_files, findings)
        gated = findings.select { |f| gates?(f[:severity]) }
        {
          "mode" => @dry_run ? "dry_run" : "live",
          "pull_request" => @pr_number,
          "changed_ruby_files" => changed_files.size,
          "finding_count" => findings.size,
          "gating_count" => gated.size,
          "status" => gated.empty? ? "pass" : "fail",
          "findings" => findings
        }
      end

      def gates?(severity)
        case @config.pr_delta.fetch("fail_on", "none").to_s
        when "any" then true
        when "high" then severity == "high"
        else false
        end
      end
    end
  end
end
