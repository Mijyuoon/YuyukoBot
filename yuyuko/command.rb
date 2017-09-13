module Yuyuko
  class CommandAttributes
    attr_reader :group

    attr_reader :arg_count
    attr_reader :arg_mode
    attr_reader :arg_types

    attr_reader :usage_info
    attr_reader :description

    attr_reader :owner_only

    def initialize(hash)
      @group = hash[:group] || :Generic

      @arg_count = hash[:arg_count] || (0..-1)
      @arg_mode = hash[:arg_mode] || :words
      @arg_types = hash[:arg_types]

      @usage_info = hash[:usage_info]
      @description = hash[:description]

      @owner_only = !!hash[:owner_only]
    end
  end

  class Command
    attr_reader :attributes

    def initialize(name, aliases, attributes = {}, &block)
      @name, @aliases, @block = name, aliases, block
      @attributes = CommandAttributes.new(attributes)
    end

    def name(str = false)
      str ? @name.to_s.gsub('_', '-') : @name
    end

    def aliases(str = false)
      str ? @aliases.map {|x| x.to_s.gsub('_', '-') } : @aliases
    end

    def call(event, args)
      arg_count = attributes.arg_count
      if args.length < arg_count.first
        raise Yuyuko::Errors::ArgumentError, kind: :few
      elsif arg_count.last > -1 && args.length > arg_count.last
        raise Yuyuko::Errors::ArgumentError, kind: :many
      end

      if attributes.owner_only && (owners = Yuyuko.cfg('core.bot.owner_id'))
        raise Yuyuko::Errors::AccessError, kind: :owner unless owners.include?(event.user.id)
      end

      @block.call(event, *args)
    rescue LocalJumpError
      nil
    end
  end

  class CommandEvent < MijDiscord::Events::Message
    attr_reader :command

    def initialize(bot, message, command)
      super(bot, message)

      @command = command
    end
  end
end