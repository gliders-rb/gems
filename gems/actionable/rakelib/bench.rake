# frozen_string_literal: true

desc 'Indicative timings (not part of the default task)'
task :bench do
  ruby File.expand_path('../benchmarks/run.rb', __dir__)
end
