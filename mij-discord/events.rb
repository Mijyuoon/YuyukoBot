# frozen_string_literal: true

module MijDiscord::Events
  class EventBase
    def initialize(*args)
      # Nothing
    end

    def trigger?(filter)
      flist = self.class.event_filters

      result = flist.map do |fk, fds|
        next true unless filter.has_key?(fk)
        key = filter[fk]

        check = fds.map do |fd|
          on, field, cmp = fd[:on], fd[:field], fd[:cmp]

          match = case on
            when Array
              on.reduce(false) {|a,x| a || trigger_match?(x, key) }
            else
              trigger_match?(on, key)
          end

          next false unless match

          value = case field
            when Array
              field.reduce(self) {|a,x| a.respond_to?(x) ? a.send(x) : nil }
            else
              respond_to?(field) ? send(field) : nil
          end

          case cmp
            when :eql?
              value == key
            when :neq?
              value != key
            when :case
              key === value
            when Proc
              cmp.call(value, key)
            else
              false
          end
        end

        check.reduce(false, &:|)
      end

      result.reduce(true, &:&)
    end

    private

    def trigger_match?(match, key)
      case match
        when :any, :all
          true
        when :id_obj
          key.respond_to?(:to_id)
        when Class
          match === key
      end
    end

    class << self
      attr_reader :event_filters

      def filter_match(key, field: key, on: :any, cmp: nil, &block)
        raise ArgumentError, 'No comparison function provided' unless cmp || block

        # @event_filters ||= superclass&.event_filters&.dup || {}
        filter = (@event_filters[key] ||= [])
        filter << {field: field, on: on, cmp: block || cmp}
      end

      def delegate_method(*names, to:)
        names.each do |name|
          define_method(name) do |*arg|
            send(to).send(name, *arg)
          end
        end
      end

      def inherited(sc)
        filters = @event_filters&.dup || {}
        sc.instance_variable_set(:@event_filters, filters)
      end
    end
  end

  class DispatcherBase
    Callback = Struct.new(:block, :filter)

    def initialize(klass)
      raise ArgumentError, 'Class must inherit from EventBase' unless klass < EventBase

      @klass, @callbacks = klass, []
    end

    def add_callback(filter = {}, &block)
      raise ArgumentError, 'No callback block provided' if block.nil?
      raise ArgumentError, 'Filter must be a hash' unless filter.is_a?(Hash)

      @callbacks << Callback.new(block, filter)
      block.object_id
    end

    def remove_callback(id)
      @callbacks.reject! {|x| x.block.object_id == id }
      nil
    end

    def trigger(event_args, block_args = nil)
      event = @klass.new(*event_args)

      @callbacks.each do |cb|
        execute_callback(cb.block, event, block_args) if event.trigger?(cb.filter)
      end
    end

    alias_method :raise, :trigger

    # Must implement execute_callback
  end
end