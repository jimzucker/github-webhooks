# frozen_string_literal: true

module GithubWebhooks
  # Deliberately minimal. The "[INFO] ..." / "[ERROR] ..." shapes are what
  # operators grep for in `docker logs`, and script/smoke_test.sh asserts on
  # them, so they are kept exactly as they were. $stdout.sync is set by the
  # entry point -- without it these never reach docker logs (issue #6).
  module Log
    class << self
      # Redirectable so specs can capture output instead of spraying it through
      # the test run.
      attr_writer :out

      def out
        @out ||= $stdout
      end

      def info(message)
        write('INFO', message)
      end

      def warn(message)
        write('WARN', message)
      end

      def error(message)
        write('ERROR', message)
      end

      private

      def write(level, message)
        out.puts("[#{level}] #{message}")
      end
    end
  end
end
