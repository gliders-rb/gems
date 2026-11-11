# frozen_string_literal: true

# Tiny harness shared by every <gem>/benchmarks/perf.rb.
#
#   PERF_GEM      label of the gem being measured (set by each script)
#   PERF_OUT      directory for result files (default benchmarks/perf/results)
#   PERF_ONLY     regexp; only workloads whose name matches run
#   PERF_PROFILE  "cpu", "wall" or "cpu,wall": run the matching workloads under StackProf instead of benchmark-ips
#   PERF_WARMUP / PERF_TIME   benchmark-ips seconds (defaults 2 / 5)
#   PERF_LIST=1   print workload names and exit
require 'benchmark/ips'
require 'json'
require 'fileutils'

module Perf
  RESULTS_DIR = ENV.fetch('PERF_OUT', File.expand_path('results', __dir__))
  Workload = Struct.new(:name, :items, :block, :setup)

  class << self
    def gem_label = @gem_label ||= ENV.fetch('PERF_GEM')
    def workloads = @workloads ||= []
    def yjit? = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?

    # Declare a workload. `items` = logical operations per block call (1000 for a batch of 1000), so per-op
    # numbers are comparable across workloads.
    def workload(name, items: 1, &block)
      workloads << Workload.new(name, items, block)
    end

    def run!
      selected = workloads.select { |w| !ENV['PERF_ONLY'] || w.name.match?(Regexp.new(ENV['PERF_ONLY'])) }
      if ENV['PERF_LIST']
        selected.each { |w| puts w.name }
        return
      end
      return profile!(selected) if ENV['PERF_PROFILE']

      ips!(selected)
    end

    def allocs_per_call(block, items)
      n = [200 / items, 3].max
      [n, 20].max.times { block.call } # settle caches, inline caches, YJIT
      GC.start
      GC.disable
      before = GC.stat(:total_allocated_objects)
      n.times { block.call }
      after = GC.stat(:total_allocated_objects)
      GC.enable
      (after - before).to_f / n
    end

    def ips!(selected)
      FileUtils.mkdir_p(RESULTS_DIR)
      rows = []
      selected.each do |w|
        warn "[#{gem_label} yjit=#{yjit?}] #{w.name}"
        w.block.call # fail fast on a broken workload
        report = Benchmark.ips do |x|
          x.config(time: Float(ENV.fetch('PERF_TIME', '5')), warmup: Float(ENV.fetch('PERF_WARMUP', '2')), quiet: true)
          x.report(w.name, &w.block)
        end
        entry = report.entries.first
        allocs = allocs_per_call(w.block, w.items)
        rows << { gem: gem_label, workload: w.name, items: w.items, yjit: yjit?, ips: entry.stats.central_tendency,
                  stddev_pct: entry.stats.error_percentage, allocs_per_call: allocs,
                  us_per_item: 1_000_000.0 / entry.stats.central_tendency / w.items,
                  allocs_per_item: allocs / w.items }
        puts format('%-44<n>s %12.1<i>f i/s (+-%4.1<e>f%%) %9.1<a>f allocs/call %10.2<u>f us/item',
                    n: w.name, i: rows.last[:ips], e: rows.last[:stddev_pct], a: allocs, u: rows.last[:us_per_item])
      end
      path = File.join(RESULTS_DIR, "#{gem_label}-yjit_#{yjit? ? 'on' : 'off'}.json")
      File.write(path, JSON.pretty_generate(rows.map { |r| r.merge(ruby: RUBY_DESCRIPTION) }))
    end

    # Run each selected workload for ~PERF_PROFILE_SECONDS under StackProf and write the raw dump plus a
    # top-10-by-self-time summary (file:line of the frame's definition, and its hottest line).
    def profile!(selected)
      require 'stackprof'
      dir = File.join(RESULTS_DIR, 'profiles')
      FileUtils.mkdir_p(dir)
      seconds = Float(ENV.fetch('PERF_PROFILE_SECONDS', '8'))
      ENV['PERF_PROFILE'].split(',').each do |mode|
        selected.each do |w|
          200.times { w.block.call }
          stem = "#{gem_label}-#{w.name.gsub(/[^\w]+/, '_')}-#{mode}"
          interval = mode == 'cpu' ? 200 : 200 # microseconds
          gc0 = GC.stat(:time)
          wall0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          data = StackProf.run(mode: mode.to_sym, interval: interval, raw: false, ignore_gc: true) do
            deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
            w.block.call while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
          end
          gc_pct = 100.0 * (GC.stat(:time) - gc0) / ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - wall0) * 1000)
          File.binwrite(File.join(dir, "#{stem}.dump"), Marshal.dump(data))
          File.write(File.join(dir, "#{stem}.json"), JSON.pretty_generate(summarize(data, w, mode, gc_pct)))
          warn "profiled #{stem}: #{data[:samples]} samples"
        end
      end
    end

    # Frame paths relative to the repo, or to the installed gem or Ruby, so results carry no machine paths.
    def portable_path(path)
      path.to_s
          .sub("#{File.expand_path('../..', __dir__)}/", '')
          .sub(%r{\A.*/lib/ruby/gems/[^/]+/gems/}, 'gems/')
          .sub(%r{\A.*/lib/ruby/(\d+\.\d+\.\d+)/}, 'ruby/\\1/')
    end

    def summarize(data, workload, mode, gc_pct)
      total = data[:samples].to_f
      frames = data[:frames].values.sort_by { |f| -f[:samples].to_i }.first(10).map do |f|
        hot = (f[:lines] || {}).max_by { |_, (_tot, self_s)| self_s.to_i }
        { name: f[:name], file: portable_path(f[:file]), line: f[:line], self_pct: (100.0 * f[:samples] / total).round(1),
          total_pct: (100.0 * f[:total_samples] / total).round(1), hot_line: hot && hot[0] }
      end
      { gem: gem_label, workload: workload.name, mode: mode, yjit: yjit?, samples: data[:samples],
        gc_wall_pct: gc_pct.round(1), top: frames }
    end
  end
end

at_exit { Perf.run! if Perf.workloads.any? && !$! }
