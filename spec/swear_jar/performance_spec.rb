# frozen_string_literal: true

require 'spec_helper'

# A coarse guard that only catches gross regressions, so it stays stable on slow CI machines.
# The real target (< 50 µs for a clean message) is measured by `rake bench`.
RSpec.describe SwearJar::Detector, '#matches performance' do
  subject(:detector) { described_class.new }

  messages = {
    'a clean' => 'Wczoraj wieczorem w tawernie pod Złotym Smokiem kusznik opowiadał, jak jego drużyna ' \
                 'przeprawiła się przez bagna, zgubiła mapę i dopiero o świcie trafiła na trakt do Werdelionu.',
    'a dirty' => 'Wczoraj wieczorem w tawernie ten kurwa kusznik znowu wszystko spierdolił, zgubił mapę ' \
                 'i dopiero o świcie trafił na trakt, a cała drużyna miała go po prostu w d u p i e, serio.'
  }.freeze

  def average_seconds(runs)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    runs.times { yield }
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) / runs
  end

  messages.each do |name, text|
    it "averages under 1 ms on #{name} ~200-character Polish message" do
      100.times { detector.matches(text) }
      expect(average_seconds(1_000) { detector.matches(text) }).to be < 0.001
    end
  end
end
