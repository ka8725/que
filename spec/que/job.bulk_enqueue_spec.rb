# frozen_string_literal: true

require 'spec_helper'

describe Que::Job, '.bulk_enqueue' do
  def assert_enqueue(
    expected_queue: 'default',
    expected_priority: 100,
    expected_run_at: Time.now,
    expected_job_class: Que::Job,
    expected_result_class: nil,
    expected_args:,
    expected_kwargs:,
    expected_tags: nil,
    expected_count:,
    &enqueue_block
  )

    assert_equal 0, jobs_dataset.count

    results = enqueue_block.call

    assert_equal expected_count, jobs_dataset.count

    results.each_with_index do |result, i|
      assert_kind_of Que::Job, result
      assert_instance_of (expected_result_class || expected_job_class), result

      assert_equal expected_priority, result.que_attrs[:priority]
      assert_equal expected_args[i], result.que_attrs[:args]
      assert_equal expected_kwargs[i], result.que_attrs[:kwargs]

      if expected_tags.nil?
        assert_equal({}, result.que_attrs[:data])
      else
        assert_equal expected_tags, result.que_attrs[:data][:tags]
      end
    end

    jobs_dataset.each_with_index do |job, i|
      assert_equal expected_queue, job[:queue]
      assert_equal expected_priority, job[:priority]
      assert_in_delta job[:run_at], expected_run_at, QueSpec::TIME_SKEW
      assert_equal expected_job_class.to_s, job[:job_class]
      assert_equal expected_args[i], job[:args]
      assert_equal expected_kwargs[i], job[:kwargs]
    end

    jobs_dataset.delete
  end

  it "should be able to queue multiple jobs" do
    assert_enqueue(
      expected_count: 3,
      expected_args: Array.new(3) { [] },
      expected_kwargs: Array.new(3) { {} },
    ) do
      Que.bulk_enqueue(
        Array.new(3) { { args: [], kwargs: {} } }
      )
    end
  end

  it "should be able to queue multiple jobs with arguments" do
    assert_enqueue(
      expected_count: 2,
      expected_args: [[1], [4]],
      expected_kwargs: [{ two: '3' }, { five: '6' }],
    ) do
      Que.bulk_enqueue(
        [
          { args: [1], kwargs: { two: '3' } },
          { args: [4], kwargs: { five: '6' } },
        ]
      )
    end
  end

  it "should be able to queue jobs with complex arguments" do
    assert_enqueue(
      expected_count: 2,
      expected_args: [[1, 'two'], ['3', 4]],
      expected_kwargs: [
        { string: 'string', integer: 5, array: [1, 'two', { three: 3 }] },
        { hash: { one: 1, two: 'two', three: [3] } },
      ],
    ) do
      Que.bulk_enqueue(
        [
          { args: [1, 'two'], kwargs: { string: 'string', integer: 5, array: [1, 'two', { three: 3 }] } },
          { args: ['3', 4], kwargs: { hash: { one: 1, two: 'two', three: [3] } } },
        ],
      )
    end
  end

  describe "when bulk_enqueue args/kwargs are empty/omitted" do
    it "can enqueue jobs with empty args" do
      assert_enqueue(
        expected_count: 2,
        expected_args: [[], []],
        expected_kwargs: [{ one: '2' }, {three: '4' }],
      ) do
        Que.bulk_enqueue(
          [
            { args: [], kwargs: { one: '2' } },
            { args: [], kwargs: { three: '4' } },
          ],
        )
      end
    end

    it "can enqueue jobs where args is omitted" do
      assert_enqueue(
        expected_count: 2,
        expected_args: [[], []],
        expected_kwargs: [{ one: '2' }, { three: '4' }],
      ) do
        Que.bulk_enqueue(
          [
            { kwargs: { one: '2' } },
            { kwargs: { three: '4' } },
          ],
        )
      end
    end

    it "can enqueue jobs where kwargs is omitted" do
      assert_enqueue(
        expected_count: 2,
        expected_args: [[1], [2]],
        expected_kwargs: [{}, {}],
      ) do
        Que.bulk_enqueue(
          [
            { args: [1] },
            { args: [2] },
          ],
        )
      end
    end

    it "can enqueue jobs where args and kwargs is omitted" do
      assert_enqueue(
        expected_count: 2,
        expected_args: [[], []],
        expected_kwargs: [{}, {}],
      ) do
        Que.bulk_enqueue([{}, {}])
      end
    end

    it "can enqueue jobs with empty args" do
      assert_enqueue(
        expected_count: 2,
        expected_args: [[], []],
        expected_kwargs: [{ one: '2' }, { three: '4' }],
      ) do
        Que.bulk_enqueue(
          [
            { args: [], kwargs: { one: '2' } },
            { args: [], kwargs: { three: '4' } },
          ],
        )
      end
    end

    it "can enqueue jobs with empty kwargs" do
      assert_enqueue(
        expected_count: 2,
        expected_args: [[1], [2]],
        expected_kwargs: [{}, {}]
      ) do
        Que.bulk_enqueue(
          [
            { args: [1], kwargs: {} },
            { args: [2], kwargs: {} },
          ],
        )
      end
    end
  end

  it "should be able to handle a namespaced job class" do
    assert_enqueue(
      expected_count: 2,
      expected_args: [[1], [4]],
      expected_kwargs: [{ two: '3' }, { five: '6' }],
      expected_job_class: NamespacedJobNamespace::NamespacedJob,
    ) do
      NamespacedJobNamespace::NamespacedJob.bulk_enqueue(
        [
          { args: [1], kwargs: { two: '3' } },
          { args: [4], kwargs: { five: '6' } },
        ],
      )
    end
  end

  it "should error appropriately on an anonymous job subclass" do
    klass = Class.new(Que::Job)
    error = assert_raises(Que::Error) { klass.bulk_enqueue([{ args: [], kwargs: {} }, { args: [], kwargs: {} }]) }
    assert_equal \
      "Can't enqueue an anonymous subclass of Que::Job",
      error.message
  end

  it "should be able to queue jobs with specific queue names" do
    assert_enqueue(
      expected_count: 2,
      expected_args: [[1], [4]],
      expected_kwargs: [{ two: '3' }, { five: 'six' }],
      expected_queue: 'special_queue_name',
    ) do
      Que.bulk_enqueue(
        [
          { args: [1], kwargs: { two: '3' } },
          { args: [4], kwargs: { five: 'six' } }
        ],
        job_options: { queue: 'special_queue_name' },
      )
    end
  end


  it "should be able to queue jobs with a specific time to run" do
    assert_enqueue(
      expected_count: 2,
      expected_args: [[1], [2]],
      expected_kwargs: [{}, {}],
      expected_run_at: Time.now + 60
    ) do
      Que.bulk_enqueue(
        [{ args: [1], kwargs: {} }, { args: [2], kwargs: {} }],
        job_options: { run_at: Time.now + 60 },
      )
    end
  end

  it "should be able to enqueue jobs with a specific priority" do
    assert_enqueue(
      expected_count: 2,
      expected_args: [[1], [2]],
      expected_kwargs: [{}, {}],
      expected_priority: 4
    ) do
      Que.bulk_enqueue(
        [{ args: [1], kwargs: {} }, { args: [2], kwargs: {} }],
        job_options: { priority: 4 },
      )
    end
  end

  it "should be able to queue jobs with options in addition to args and kwargs" do
    assert_enqueue(
      expected_count: 2,
      expected_args: [[1], [4]],
      expected_kwargs: [{ two: "3" }, { five: "six" }],
      expected_run_at: Time.now + 60,
      expected_priority: 4,
    ) do
      Que.bulk_enqueue(
        [
          { args: [1], kwargs: { two: "3" } },
          { args: [4], kwargs: { five: "six" } },
        ],
        job_options: { run_at: Time.now + 60, priority: 4 },
      )
    end
  end

  it "should no longer fall back to using job options specified at the top level if not specified in job_options" do
    assert_enqueue(
      expected_count: 2,
      expected_args: [[1], [4]],
      expected_kwargs: [
        { two: "3", run_at: Time.utc(2050).to_s, priority: 10 },
        { five: "six" }
      ],
      expected_run_at: Time.now,
      expected_priority: 15,
    ) do
      Que.bulk_enqueue(
        [
          { args: [1], kwargs: { two: "3", run_at: Time.utc(2050), priority: 10 } },
          { args: [4], kwargs: { five: "six" } },
        ],
        job_options: { priority: 15 },
      )
    end
  end

  describe "when enqueuing jobs with tags" do
    it "should be able to specify tags on a case-by-case basis" do
      assert_enqueue(
        expected_count: 2,
        expected_args: [[1], [4]],
        expected_kwargs: [{ two: "3" }, { five: "six" }],
        expected_tags: ["tag_1", "tag_2"],
      ) do
        Que.bulk_enqueue(
          [
            { args: [1], kwargs: { two: "3" } },
            { args: [4], kwargs: { five: "six" } },
          ],
          job_options: { tags: ["tag_1", "tag_2"] },
        )
      end
    end

    it "should no longer fall back to using tags specified at the top level if not specified in job_options" do
      assert_enqueue(
        expected_count: 2,
        expected_args: [[1], [4]],
        expected_kwargs: [
          { two: "3", tags: ["tag_1", "tag_2"] },
          { five: "six" },
        ],
        expected_tags: nil,
      ) do
        Que.bulk_enqueue(
          [
            { args: [1], kwargs: { two: "3", tags: ["tag_1", "tag_2"] } },
            { args: [4], kwargs: { five: "six" } },
          ],
        )
      end
    end

    it "should raise an error if passing too many tags" do
      error =
        assert_raises(Que::Error) do
          Que::Job.bulk_enqueue(
            [
              { args: [1], kwargs: { two: "3" } },
              { args: [4], kwargs: { five: "six" } },
            ],
            job_options: { tags: %w[a b c d e f] },
          )
        end

      assert_equal \
        "Can't enqueue a job with more than 5 tags! (passed 6)",
        error.message
    end

    it "should raise an error if any of the tags are too long" do
      error =
        assert_raises(Que::Error) do
          Que::Job.bulk_enqueue(
            [
              { args: [1], kwargs: { two: "3" } },
              { args: [4], kwargs: { five: "six" } },
            ],
            job_options: { tags: ["a" * 101] },
          )
        end

      assert_equal \
        "Can't enqueue a job with a tag longer than 100 characters! (\"#{"a" * 101}\")",
        error.message
    end
  end

  it "should respect a job class defined as a string" do
    class MyJobClass < Que::Job; end

    assert_enqueue(
      expected_count: 2,
      expected_args: [[1], [4]],
      expected_kwargs: [{ two: "3" }, { five: "six" }],
      expected_job_class: MyJobClass,
      expected_result_class: Que::Job,
    ) do
      Que.bulk_enqueue(
        [
          { args: [1], kwargs: { two: "3" } },
          { args: [4], kwargs: { five: "six" } },
        ],
        job_options: { job_class: 'MyJobClass' },
      )
    end
  end

  describe "when there's a hierarchy of job classes" do
    class PriorityDefaultJob < Que::Job
      self.priority = 3
    end

    class PrioritySubclassJob < PriorityDefaultJob
    end

    class RunAtDefaultJob < Que::Job
      self.run_at = -> { Time.now + 30 }
    end

    class RunAtSubclassJob < RunAtDefaultJob
    end

    class QueueDefaultJob < Que::Job
      self.queue = :queue_1
    end

    class QueueSubclassJob < QueueDefaultJob
    end

    describe "priority" do
      it "should respect a default priority in a job class" do
        assert_enqueue(
          expected_count: 2,
          expected_args: [[1], [4]],
          expected_kwargs: [{ two: "3" }, { five: "six" }],
          expected_priority: 3,
          expected_job_class: PriorityDefaultJob,
        ) do
          PriorityDefaultJob.bulk_enqueue(
            [
              { args: [1], kwargs: { two: "3" } },
              { args: [4], kwargs: { five: "six" } },
            ],
          )
        end

        assert_enqueue(
          expected_count: 2,
          expected_args: [[1], [4]],
          expected_kwargs: [{ two: "3" }, { five: "six" }],
          expected_priority: 4,
          expected_job_class: PriorityDefaultJob,
        ) do
          PriorityDefaultJob.bulk_enqueue(
            [
              { args: [1], kwargs: { two: "3" } },
              { args: [4], kwargs: { five: "six" } },
            ],
            job_options: { priority: 4 },
          )
        end
      end

      it "should respect an inherited priority in a job class" do
        assert_enqueue(
          expected_count: 2,
          expected_args: [[1], [4]],
          expected_kwargs: [{ two: "3" }, { five: "six" }],
          expected_priority: 3,
          expected_job_class: PrioritySubclassJob
        ) do
          PrioritySubclassJob.bulk_enqueue(
            [
              { args: [1], kwargs: { two: "3" } },
              { args: [4], kwargs: { five: "six" } },
            ],
          )
        end

        assert_enqueue(
          expected_count: 2,
          expected_args: [[1], [4]],
          expected_kwargs: [{ two: "3" }, { five: "six" }],
          expected_priority: 4,
          expected_job_class: PrioritySubclassJob
        ) do
          PrioritySubclassJob.bulk_enqueue(
            [
              { args: [1], kwargs: { two: "3" } },
              { args: [4], kwargs: { five: "six" } },
            ],
            job_options: { priority: 4 },
          )
        end
      end

      it "should respect an overridden priority in a job class" do
        begin
          PrioritySubclassJob.priority = 60

          assert_enqueue(
            expected_count: 2,
            expected_args: [[1], [4]],
            expected_kwargs: [{ two: "3" }, { five: "six" }],
            expected_priority: 60,
            expected_job_class: PrioritySubclassJob
          ) do
            PrioritySubclassJob.bulk_enqueue(
              [
                { args: [1], kwargs: { two: "3" } },
                { args: [4], kwargs: { five: "six" } },
              ],
            )
          end

          assert_enqueue(
            expected_count: 2,
            expected_args: [[1], [4]],
            expected_kwargs: [{ two: "3" }, { five: "six" }],
            expected_priority: 4,
            expected_job_class: PrioritySubclassJob
          ) do
            PrioritySubclassJob.bulk_enqueue(
              [
                { args: [1], kwargs: { two: "3" } },
                { args: [4], kwargs: { five: "six" } },
              ],
              job_options: { priority: 4 },
            )
          end
        ensure
          PrioritySubclassJob.remove_instance_variable(:@priority)
        end
      end
    end

    describe "run_at" do
      it "should respect a default run_at in a job class" do
        assert_enqueue(
          expected_count: 2,
          expected_args: [[1], [4]],
          expected_kwargs: [{ two: "3" }, { five: "six" }],
          expected_run_at: Time.now + 30,
          expected_job_class: RunAtDefaultJob
        ) do
          RunAtDefaultJob.bulk_enqueue(
            [
              { args: [1], kwargs: { two: "3" } },
              { args: [4], kwargs: { five: "six" } },
            ],
          )
        end

        assert_enqueue(
          expected_count: 2,
          expected_args: [[1], [4]],
          expected_kwargs: [{ two: "3" }, { five: "six" }],
          expected_run_at: Time.now + 60,
          expected_job_class: RunAtDefaultJob
        ) do
          RunAtDefaultJob.bulk_enqueue(
            [
              { args: [1], kwargs: { two: "3" } },
              { args: [4], kwargs: { five: "six" } },
            ],
            job_options: { run_at: Time.now + 60 },
          )
        end
      end

      it "should respect an inherited run_at in a job class" do
        assert_enqueue(
          expected_count: 2,
          expected_args: [[1], [4]],
          expected_kwargs: [{ two: "3" }, { five: "six" }],
          expected_run_at: Time.now + 30,
          expected_job_class: RunAtDefaultJob
        ) do
          RunAtDefaultJob.bulk_enqueue(
            [
              { args: [1], kwargs: { two: "3" } },
              { args: [4], kwargs: { five: "six" } },
            ],
          )
        end

        assert_enqueue(
          expected_count: 2,
          expected_args: [[1], [4]],
          expected_kwargs: [{ two: "3" }, { five: "six" }],
          expected_run_at: Time.now + 60,
          expected_job_class: RunAtDefaultJob
        ) do
          RunAtDefaultJob.bulk_enqueue(
            [
              { args: [1], kwargs: { two: "3" } },
              { args: [4], kwargs: { five: "six" } },
            ],
            job_options: { run_at: Time.now + 60 },
          )
        end
      end

      it "should respect an overridden run_at in a job class" do
        begin
          RunAtSubclassJob.run_at = -> {Time.now + 90}

          assert_enqueue(
            expected_count: 2,
            expected_args: [[1], [4]],
            expected_kwargs: [{ two: "3" }, { five: "six" }],
            expected_run_at: Time.now + 90,
            expected_job_class: RunAtSubclassJob
          ) do
            RunAtSubclassJob.bulk_enqueue(
              [
                { args: [1], kwargs: { two: "3" } },
                { args: [4], kwargs: { five: "six" } },
              ],
            )
          end

          assert_enqueue(
            expected_count: 2,
            expected_args: [[1], [4]],
            expected_kwargs: [{ two: "3" }, { five: "six" }],
            expected_run_at: Time.now + 60,
            expected_job_class: RunAtSubclassJob
          ) do
            RunAtSubclassJob.bulk_enqueue(
              [
                { args: [1], kwargs: { two: "3" } },
                { args: [4], kwargs: { five: "six" } },
              ],
              job_options: { run_at: Time.now + 60 },
            )
          end
        ensure
          RunAtSubclassJob.remove_instance_variable(:@run_at)
        end
      end
    end

    describe "queue" do
      it "should respect a default queue in a job class" do
        assert_enqueue(
          expected_count: 2,
          expected_args: [[1], [4]],
          expected_kwargs: [{ two: "3" }, { five: "six" }],
          expected_queue: 'queue_1',
          expected_job_class: QueueDefaultJob
        ) do
          QueueDefaultJob.bulk_enqueue(
            [
              { args: [1], kwargs: { two: "3" } },
              { args: [4], kwargs: { five: "six" } },
            ],
          )
        end

        assert_enqueue(
          expected_count: 2,
          expected_args: [[1], [4]],
          expected_kwargs: [{ two: "3" }, { five: "six" }],
          expected_queue: 'queue_3',
          expected_job_class: QueueDefaultJob
        ) do
          QueueDefaultJob.bulk_enqueue(
            [
              { args: [1], kwargs: { two: "3" } },
              { args: [4], kwargs: { five: "six" } },
            ],
            job_options: { queue: 'queue_3' },
          )
        end
      end

      it "should respect an inherited queue in a job class" do
        assert_enqueue(
          expected_count: 2,
          expected_args: [[1], [4]],
          expected_kwargs: [{ two: "3" }, { five: "six" }],
          expected_queue: 'queue_1',
          expected_job_class: QueueSubclassJob
        ) do
          QueueSubclassJob.bulk_enqueue(
            [
              { args: [1], kwargs: { two: "3" } },
              { args: [4], kwargs: { five: "six" } },
            ],
          )
        end

        assert_enqueue(
          expected_count: 2,
          expected_args: [[1], [4]],
          expected_kwargs: [{ two: "3" }, { five: "six" }],
          expected_queue: 'queue_3',
          expected_job_class: QueueSubclassJob
        ) do
          QueueSubclassJob.bulk_enqueue(
            [
              { args: [1], kwargs: { two: "3" } },
              { args: [4], kwargs: { five: "six" } },
            ],
            job_options: { queue: 'queue_3' },
          )
        end
      end

      it "should respect an overridden queue in a job class" do
        begin
          QueueSubclassJob.queue = :queue_2

          assert_enqueue(
            expected_count: 2,
            expected_args: [[1], [4]],
            expected_kwargs: [{ two: "3" }, { five: "six" }],
            expected_queue: 'queue_2',
            expected_job_class: QueueSubclassJob
          ) do
            QueueSubclassJob.bulk_enqueue(
              [
                { args: [1], kwargs: { two: "3" } },
                { args: [4], kwargs: { five: "six" } },
              ],
            )
          end

          assert_enqueue(
            expected_count: 2,
            expected_args: [[1], [4]],
            expected_kwargs: [{ two: "3" }, { five: "six" }],
            expected_queue: 'queue_3',
            expected_job_class: QueueSubclassJob
          ) do
            QueueSubclassJob.bulk_enqueue(
              [
                { args: [1], kwargs: { two: "3" } },
                { args: [4], kwargs: { five: "six" } },
              ],
              job_options: { queue: 'queue_3' },
            )
          end
        ensure
          QueueSubclassJob.remove_instance_variable(:@queue)
        end
      end
    end
  end
end
