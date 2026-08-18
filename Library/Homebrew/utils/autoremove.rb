# typed: strict
# frozen_string_literal: true

module Utils
  # Helper function for finding autoremovable formulae.
  #
  # @private
  module Autoremove
    class << self
      # An array of {Formula} without {Formula} or {Cask} dependents that
      # weren't installed on request, and without {Formula} installed from
      # source or their build dependencies, unless `include_built: true`.
      # @private
      sig { params(formulae: T::Array[Formula], casks: T::Array[Cask::Cask], include_built: T::Boolean).returns(T::Array[Formula]) }
      def removable_formulae(formulae, casks, include_built: false)
        unused_formulae = unused_formulae_with_no_formula_dependents(formulae, include_built: include_built)
        cask_dep_names = cask_dependent_formula_names(casks, formulae)
        unused_formulae.reject { |f| cask_dep_names.intersect?(f.possible_names) }
      end

      # A set of names for all installed {Formula} objects that are {Cask} formula
      # dependencies (direct or transitive).
      # @private
      sig { params(casks: T::Array[Cask::Cask], formulae: T::Array[Formula]).returns(T::Set[String]) }
      def cask_dependent_formula_names(casks, formulae)
        formulae_by_name = formulae.to_h { |f| [f.name, f] }
        names = casks.flat_map { |cask| cask.depends_on.formula }.flat_map do |name|
          base = Utils.name_from_full_name(name)
          f = formulae_by_name[base]
          next [] unless f

          tab = f.any_installed_keg&.tab
          dep_names = if (tab_deps = T.cast(tab&.runtime_dependencies,
                                            T.nilable(T::Array[T::Hash[String, T.untyped]])))
            # Use tab data to avoid Formulary.resolve for each dependency.
            tab_deps.filter_map do |dep|
              full_name = dep["full_name"]
              next unless full_name

              Utils.name_from_full_name(full_name)
            end
          else
            # Fallback for pre-1.1.6 installations without tab runtime_dependencies.
            f.installed_runtime_formula_dependencies.map(&:name)
          end
          [base, *dep_names]
        end
        names.to_set
      end

      # An array of all installed {Formula} without runtime {Formula} dependents
      # and without build {Formula} dependents that were built from source.
      # Only bottled {Formula}, unless `include_built: true`.
      # @private
      sig { params(formulae: T::Array[Formula], include_built: T::Boolean).returns(T::Array[Formula]) }
      def formulae_with_no_formula_dependents(formulae, include_built: false)
        names_to_keep = T.let(Set.new, T::Set[String])
        formulae.each do |formula|
          tab = formula.any_installed_keg&.tab
          # Keep this formula's runtime dependencies
          if (tab_deps = T.cast(tab&.runtime_dependencies, T.nilable(T::Array[T::Hash[String, T.untyped]])))
            # Use tab data to avoid Formulary.resolve for each dependency.
            tab_deps.each do |dep|
              full_name = dep["full_name"]
              next unless full_name

              names_to_keep.add(Utils.name_from_full_name(full_name))
            end
          else
            # Fallback for pre-1.1.6 installations without tab runtime_dependencies.
            formula.installed_runtime_formula_dependencies.each { |f| names_to_keep.add(f.name) }
          end

          next if tab&.poured_from_bottle || include_built

          # This formula is built from source and we're not given --include-built

          # Keep this formula (which was built from source)
          names_to_keep.add(formula.name)

          # Keep build dependencies of this (built) formula
          formula.deps.select(&:build?).each do |dep|
            names_to_keep.add(dep.to_formula.name)
          rescue FormulaUnavailableError
            # do nothing
          end
        end
        formulae.reject { |f| names_to_keep.intersect?(f.possible_names) }
      end

      # Recursive function that returns an array of {Formula} without
      # {Formula} dependents that weren't installed on request.
      # Only bottled {Formula}, unless `include_built: true`.
      # @private
      sig { params(formulae: T::Array[Formula], include_built: T::Boolean).returns(T::Array[Formula]) }
      def unused_formulae_with_no_formula_dependents(formulae, include_built: false)
        unused_formulae = formulae_with_no_formula_dependents(formulae, include_built: include_built).select do |f|
          tab = f.any_installed_keg&.tab
          next unless tab
          next unless tab.installed_on_request_present?

          tab.installed_on_request == false
        end

        unless unused_formulae.empty?
          unused_formulae += unused_formulae_with_no_formula_dependents(formulae - unused_formulae,
                                                                        include_built: include_built)
        end

        unused_formulae
      end
    end
  end
end
