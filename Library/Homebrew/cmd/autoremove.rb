# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "cleanup"

module Homebrew
  module Cmd
    class Autoremove < AbstractCommand
      cmd_args do
        description <<~EOS
          Uninstall formulae that were only installed as a dependency of another formula and are now no longer needed.
        EOS
        switch "--include-built",
               description: "Include formulae that were built from source."
        switch "-n", "--dry-run",
               description: "List what would be uninstalled, but do not actually uninstall anything."

        named_args :none
      end

      sig { override.void }
      def run
        Cleanup.autoremove(include_built: args.include_built?, dry_run: args.dry_run?)
      end
    end
  end
end
