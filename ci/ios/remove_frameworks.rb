#!/usr/bin/env ruby
# Removes frameworks/xcframeworks from every build phase of an Xcode project (Link Binary,
# Embed Frameworks, ...). Meant for CI Simulator builds of apps that link device-only
# frameworks: run it on the CI checkout right before `xcodebuild`, never commit the result.
#
#   ruby remove_frameworks.rb <path/to/App.xcodeproj> <Framework.xcframework> [...]
#
# Needs the `xcodeproj` gem (installed with CocoaPods or fastlane).
require 'xcodeproj'

project_path, *names = ARGV
abort "usage: #{$PROGRAM_NAME} <App.xcodeproj> <Framework.xcframework> [...]" if project_path.nil? || names.empty?

project = Xcodeproj::Project.open(project_path)
removed = 0
project.targets.each do |target|
  target.build_phases.each do |phase|
    phase.files.select { |bf| names.include?(bf.display_name) }.each do |bf|
      puts "#{target.name}: removing #{bf.display_name} from #{phase.display_name}"
      phase.remove_build_file(bf)
      removed += 1
    end
  end
end
abort "None of #{names.join(', ')} found in #{project_path}" if removed.zero?
project.save
puts "Removed #{removed} build file reference(s)."
