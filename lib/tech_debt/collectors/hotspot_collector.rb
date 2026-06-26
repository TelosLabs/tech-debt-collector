# frozen_string_literal: true

require "open3"
require_relative "base_collector"

module TechDebt
  module Collectors
    # Orientation pass. The AST/dead-code collectors only surface debt they are
    # built to detect, so files that are simply large and churning constantly
    # stay invisible. This collector flags maintenance hotspots: in-scope files
    # that are both frequently changed (git churn) and large. Their intersection
    # is where defect and review cost concentrate. Hotspots seed the LLM triage
    # with files it would otherwise never look at; the model then diagnoses the
    # concrete debt type from the snippet.
    class HotspotCollector < BaseCollector
      def call
        settings = config.hotspot
        return [] unless settings["enabled"]

        targets = target_files
        return [] if targets.empty?

        churn = churn_counts(settings["window_months"])
        return [] if churn.empty?

        hotspots(targets, churn, settings)
      end

      private

      def hotspots(targets, churn, settings)
        in_scope = index(targets)
        candidates = churn.filter_map do |file, commits|
          next unless in_scope[file]
          next if commits < settings["min_commits"]

          loc = line_count(file)
          next if loc < settings["min_loc"]

          build_candidate(file, commits, loc, settings["window_months"])
        end
        candidates.sort_by { |candidate| -candidate[:score] }.first(settings["max_files"])
      end

      def build_candidate(file, commits, loc, window_months)
        {
          file: file,
          identifier: file,
          type: "hotspot",
          detail: "Maintenance hotspot: #{commits} commits in the last #{window_months} months across #{loc} lines. " \
                  "High churn in a large file concentrates defect and review cost; inspect for responsibilities " \
                  "that should be extracted.",
          score: commits * loc
        }
      end

      # Counts commits touching each Ruby file in the window, repo-wide. Filtering
      # to in-scope files happens in #hotspots so we never shell out per file.
      def churn_counts(window_months)
        stdout, _stderr, status = Open3.capture3(
          "git", "log", "--since=#{window_months} months ago", "--name-only", "--format="
        )
        return {} unless status.success?

        counts = Hash.new(0)
        stdout.each_line do |line|
          path = line.strip
          counts[path] += 1 if path.end_with?(".rb")
        end
        counts
      end

      def line_count(file)
        File.readlines(file).size
      rescue StandardError
        0
      end

      def index(targets)
        targets.each_with_object({}) { |file, memo| memo[file] = true }
      end
    end
  end
end
