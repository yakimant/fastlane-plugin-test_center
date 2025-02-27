require 'trainer'
require 'shellwords'

module Fastlane
  module Actions
    class TestsFromXcresultAction < Action
      def self.run(params)
        unless FastlaneCore::Helper.xcode_at_least?('11.0.0')
          UI.error("Error: tests_from_xcresult requires at least Xcode 11.0")
          return {}
        end

        xcresult_path = File.absolute_path(params[:xcresult])

        # taken from the rubygem trainer, in the test_parser.rb module
        result_bundle_object_raw = sh("xcrun xcresulttool get --path #{xcresult_path.shellescape} --format json", print_command: false, print_command_output: false)
        result_bundle_object = JSON.parse(result_bundle_object_raw)

        # Parses JSON into ActionsInvocationRecord to find a list of all ids for ActionTestPlanRunSummaries
        actions_invocation_record = Trainer::XCResult::ActionsInvocationRecord.new(result_bundle_object)
        test_refs = actions_invocation_record.actions.map do |action|
          action.action_result.tests_ref
        end.compact

        ids = test_refs.map(&:id)
        summaries = ids.map do |id|
          raw = sh("xcrun xcresulttool get --format json --path #{xcresult_path.shellescape} --id #{id}", print_command: false, print_command_output: false)
          json = JSON.parse(raw)
          Trainer::XCResult::ActionTestPlanRunSummaries.new(json)
        end
        failures = actions_invocation_record.issues.test_failure_summaries || []
        all_summaries = summaries.map(&:summaries).flatten
        testable_summaries = all_summaries.map(&:testable_summaries).flatten
        failed = []
        passing = []
        failure_details = {}
        rows = testable_summaries.map do |testable_summary|
          all_tests = testable_summary.all_tests.flatten
          all_tests.each do |t|
            if t.test_status == 'Success'
              passing << "#{t.parent.name}/#{t.identifier}"
            else
              test_identifier = "#{t.parent.name}/#{t.identifier}"
              failed << test_identifier
              failure = t.find_failure(failures)
              if failure
                failure_details[test_identifier] = {
                  message: failure.failure_message
                }
              end
            end
          end
        end
        {
          failed: failed.uniq,
          passing: passing.uniq,
          failure_details: failure_details
        }
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "☑️ Retrieves the failing and passing tests as reportedn an xcresult bundle"
      end


      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :xcresult,
            env_name: "FL_TESTS_FROM_XCRESULT_XCRESULT_PATH",
            description: "The path to the xcresult bundle to retrieve the tests from",
            verify_block: proc do |path|
              UI.user_error!("Error: cannot find the xcresult bundle at '#{path}'") unless Dir.exist?(path)
              UI.user_error!("Error: cannot parse files that are not in the xcresult format") unless File.extname(path) == ".xcresult"
            end
          )
        ]
      end

      def self.return_value
        "A Hash with information about the test results:\r\n" \
        "failed: an Array of the failed test identifiers\r\n" \
        "passing: an Array of the passing test identifiers\r\n"
      end

      def self.authors
        ["lyndsey-ferguson/lyndseydf"]
      end

      def self.category
        :testing
      end

      def self.is_supported?(platform)
        %i[ios mac].include?(platform)
      end
    end
  end
end
