# frozen_string_literal: true

require "set"

module Safe
  # Keeps only formula upgrades whose runtime dependencies are satisfied by the
  # installed kegs or by the safe targets of other planned upgrades. A missing
  # dependency, or an installed one that is not part of the plan, is added as its
  # own install or upgrade candidate when it has a safe target. A blocked
  # candidate falls back to older safe targets; when none fits, it is marked
  # blocked with the dependencies its newest safe target needs.
  class DependencyPlan
    # A runtime dependency that the installed kegs do not satisfy.
    # A nil minimum_version means Homebrew requires the dependency's latest version.
    Requirement = Struct.new(:name, :minimum_version, :installed_version, keyword_init: true)

    TARGET_FIELDS = %i[target_version target_publication_date upgrade_commit_sha upgrade_source_path].freeze

    # requirements_for: ->(candidate) { [Requirement] } for the candidate's current target.
    # next_target: ->(candidate) { older safe version ref or nil }.
    # version_satisfies: ->(target_version, minimum_version) { Boolean }.
    # dependency_candidate: ->(requirement) { install or upgrade candidate for the dependency, or nil }.
    def initialize(requirements_for:, next_target:, version_satisfies:, dependency_candidate:)
      @requirements_for = requirements_for
      @next_target = next_target
      @version_satisfies = version_satisfies
      @dependency_candidate = dependency_candidate
      @requirements = {}
    end

    # Returns the added dependency candidates that the plan installs or that explain
    # a blocked candidate, followed by the given candidates. Each added candidate's
    # required_by lists the formulae that need it.
    def apply(candidates)
      planned = candidates.select { |candidate| candidate.type == :formula && candidate.safe }
      # Candidates are mutable Structs whose hash changes on retarget, so key by identity.
      newest_targets = {}.compare_by_identity
      by_name = candidates.select { |candidate| candidate.type == :formula }.to_h { |candidate| [candidate.item.full_name.to_s, candidate] }
      added = []
      looked_up = Set.new
      @blocked = blocked = []

      # Each dependency is looked up once, targets only move to older versions,
      # and the plan only shrinks otherwise, so this terminates.
      loop do
        planned.each { |candidate| newest_targets[candidate] ||= target_fields(candidate) }
        plan = index(planned)
        unsatisfied = planned.reject { |candidate| unmet_requirements(candidate, plan, by_name).empty? }
        break if unsatisfied.empty?

        new_dependencies = add_dependencies(unsatisfied, by_name, looked_up)
        if new_dependencies.any?
          added.concat(new_dependencies)
          planned.concat(new_dependencies.select(&:safe))
          next
        end

        unsatisfied.each do |candidate|
          target = @next_target.call(candidate)
          if target
            retarget(candidate, target)
          else
            planned.delete_if { |planned_candidate| planned_candidate.equal?(candidate) }
            candidate.safe = false
            blocked << candidate
          end
        end
      end

      plan = index(planned)
      blocked.each do |candidate|
        restore(candidate, newest_targets.fetch(candidate))
        candidate.blocked_dependencies = unmet_requirements(candidate, plan, by_name)
      end

      kept = needed_dependencies(candidates, added, by_name)
      kept.each { |dependency| dependency.required_by = required_by(dependency, candidates + kept) }
      kept + candidates
    end

    private

    def index(planned)
      planned.to_h { |candidate| [candidate.item.full_name.to_s, candidate] }
    end

    # Looks up each unmet dependency that no candidate covers yet.
    def add_dependencies(unsatisfied, by_name, looked_up)
      unsatisfied.each_with_object([]) do |candidate, new_dependencies|
        requirements = requirements(candidate)
        next if requirements.is_a?(StandardError)

        requirements.each do |requirement|
          name = requirement.name.to_s
          next if name == candidate.item.full_name.to_s || by_name.key?(name) || looked_up.include?(name)

          looked_up << name
          dependency = @dependency_candidate.call(requirement)
          next unless dependency

          by_name[name] = dependency
          new_dependencies << dependency
        end
      end
    end

    # Added dependencies reachable from the planned given candidates while planned
    # themselves, or from the blocked given candidates while blocked themselves.
    def needed_dependencies(candidates, added, by_name)
      reachable = lambda do |roots, state|
        found = []
        queue = roots.dup
        until queue.empty?
          requirements = requirements(queue.shift)
          next if requirements.is_a?(StandardError)

          requirements.each do |requirement|
            dependency = by_name[requirement.name.to_s]
            next unless added.any? { |candidate| candidate.equal?(dependency) }
            next if found.any? { |candidate| candidate.equal?(dependency) } || !state.call(dependency)

            found << dependency
            queue << dependency
          end
        end
        found
      end

      formulae = candidates.select { |candidate| candidate.type == :formula }
      planned = reachable.call(formulae.select(&:safe), :safe.to_proc)
      blocked = reachable.call(formulae.select(&:blocked_dependencies), :blocked_dependencies.to_proc)
      added.select { |candidate| (planned + blocked).any? { |dependency| dependency.equal?(candidate) } }
    end

    def required_by(dependency, candidates)
      name = dependency.item.full_name.to_s
      candidates.filter_map do |candidate|
        next if candidate.equal?(dependency) || candidate.type != :formula
        next unless candidate.safe || candidate.blocked_dependencies

        requirements = requirements(candidate)
        next if requirements.is_a?(StandardError)

        candidate.item.full_name.to_s if requirements.any? { |requirement| requirement.name.to_s == name }
      end
    end

    def unmet_requirements(candidate, plan, by_name)
      requirements = requirements(candidate)
      return ["dependency check failed: #{requirements.message}"] if requirements.is_a?(StandardError)

      requirements.filter_map do |requirement|
        name = requirement.name.to_s
        next if name == candidate.item.full_name.to_s

        dependency = plan[name]
        next if dependency && satisfies?(dependency, requirement)

        describe(requirement, dependency || by_name[name])
      end
    end

    def requirements(candidate)
      key = [candidate.object_id, candidate.target_version]
      @requirements.fetch(key) do
        @requirements[key] = begin
          @requirements_for.call(candidate)
        rescue StandardError => e
          e
        end
      end
    end

    def satisfies?(dependency, requirement)
      return dependency.target_version == dependency.latest_version if requirement.minimum_version.nil?

      @version_satisfies.call(dependency.target_version, requirement.minimum_version)
    end

    def describe(requirement, dependency)
      needed = requirement.minimum_version ? " >= #{requirement.minimum_version}" : " (latest version)"
      state = if requirement.installed_version
        "installed #{requirement.installed_version}"
      else
        "not installed"
      end

      if dependency&.safe
        state += ", safe target #{dependency.target_version}"
      elsif dependency
        action = dependency.installed_version ? "upgrade" : "install"
        state += ", #{action} #{dependency_status(dependency)}"
      end

      "#{requirement.name}#{needed} (#{state})"
    end

    def dependency_status(dependency)
      return "blocked" if @blocked.any? { |candidate| candidate.equal?(dependency) }
      return "release date unknown" if dependency.date_unknown
      return "has no cutoff" if dependency.no_cutoff

      "too new"
    end

    def target_fields(candidate)
      TARGET_FIELDS.to_h { |field| [field, candidate.public_send(field)] }
    end

    def restore(candidate, fields)
      fields.each { |field, value| candidate.public_send(:"#{field}=", value) }
    end

    def retarget(candidate, target)
      candidate.target_version = target.version
      candidate.target_publication_date = target.publication_date
      candidate.upgrade_commit_sha = target.commit_sha
      candidate.upgrade_source_path = target.path
    end
  end
end
