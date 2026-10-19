# frozen_string_literal: true

# Run with `bundle exec rake bench`. Uses only Process.clock_gettime, so it needs no benchmark gem.
require_relative '../lib/swear_jar'

MESSAGES = {
  'clean pl' => 'Wczoraj wieczorem w tawernie pod Złotym Smokiem kusznik opowiadał, jak jego drużyna ' \
                'przeprawiła się przez bagna, zgubiła mapę i dopiero o świcie trafiła na trakt do Werdelionu.',
  'clean en' => 'Last night at the Golden Dragon tavern the crossbowman told us how his party crossed ' \
                'the marshes, lost the map, and only found the road to the capital at dawn. Great story.',
  'clean emoji' => 'Dzięki za pomoc 🙏🙏 świetna drużyna 💪🔥 do zobaczenia jutro o 20:00 😀👍 ' \
                   '👨‍👩‍👧 rodzina w komplecie, ✨🎉🎉 gratulacje dla zwycięzców turnieju 🏆🥇 ' \
                   'i dla wszystkich, którzy grali do końca 💯❤️',
  'dirty pl' => 'Wczoraj wieczorem w tawernie ten kurwa kusznik znowu wszystko spierdolił, zgubił mapę ' \
                'i dopiero o świcie trafił na trakt, a cała drużyna miała go po prostu w d u p i e, serio.'
}.freeze

ITERATIONS = 20_000
WARMUP = 1_000

def clock
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

# Average microseconds per call of the block.
def measure(iterations = ITERATIONS, warmup: WARMUP)
  warmup.times { yield }
  started = clock
  iterations.times { yield }
  (clock - started) * 1_000_000 / iterations
end

def row(label, micros)
  puts format('  %-38<label>s %9.2<micros>f µs', label: label, micros: micros)
end

puts "SwearJar #{SwearJar::VERSION}, Ruby #{RUBY_VERSION}, #{ITERATIONS} iterations per row"
puts

started = clock
SwearJar::Detector.new
puts format('Detector.new (all locales, :words): %.1f ms', (clock - started) * 1000)
puts format('Detector.new, average of 20: %.1f ms', measure(20, warmup: 1) { SwearJar::Detector.new } / 1000)
puts

%i[words embedded].each do |mode|
  detector = SwearJar::Detector.new(mode: mode)
  puts "mode: #{mode}"
  MESSAGES.each do |name, text|
    row("profane? #{name} (#{text.length} chars)", measure { detector.profane?(text) })
    row("matches  #{name} (#{text.length} chars)", measure { detector.matches(text) })
  end
  puts
end
