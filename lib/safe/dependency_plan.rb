# frozen_string_literal: true

module Safe
  # Keeps only formula upgrades whose runtime dependencies are satisfied by the
  # installed kegs or by the safe targets of other planned upgrades. A blocked
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
    def initialize(requirements_for:, next_target:, version_satisfies:)
      @requirements_for = requirements_for
      @next_target = next_target
      @version_satisfies = version_satisfies
      @requirements = {}
    end

    def apply(candidates)
      planned = candidates.select { |candidate| candidate.type == :formula && candidate.safe }
      # Candidates are mutable Structs whose hash changes on retarget, so key by identity.
      newest_targets = {}.compare_by_identity
      planned.each { |candidate| newest_targets[candidate] = target_fields(candidate) }
      by_name = candidates.select { |candidate| candidate.type == :formula }.to_h { |candidate| [candidate.item.full_name.to_s, candidate] }
      @blocked = blocked = []

      # Targets only move to older versions and the plan only shrinks, so this terminates.
      loop do
        plan = index(planned)
        unsatisfied = planned.reject { |candidate| unmet_requirements(candidate, plan, by_name).empty? }
        break if unsatisfied.empty?

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

      candidates
    end

    private

    def index(planned)
      planned.to_h { |candidate| [candidate.item.full_name.to_s, candidate] }
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
        state += ", upgrade #{dependency_status(dependency)}"
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
