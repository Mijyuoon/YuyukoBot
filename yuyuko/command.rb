module Yuyuko
  class Command
    attr_reader :name

    attr_reader :aliases

    attr_accessor :group

    attr_accessor :arg_count

    attr_accessor :arg_mode

    attr_accessor :arg_types

    attr_accessor :hide_help

    attr_accessor :usage_info

    attr_accessor :description

    attr_reader :permissions

    attr_accessor :owner_only

    DEFAULT_GROUP = 'Generic'

    def initialize(name, aliases, attributes = {}, &block)
      @name, @aliases, @block = name, aliases, block

      @group = attributes[:group] || DEFAULT_GROUP

      @arg_count = attributes[:arg_count] || (0..-1)
      @arg_mode = attributes[:arg_mode] || :words
      @arg_types = attributes[:arg_types]

      @hide_help = attributes[:hide_help]
      @usage_info = attributes[:usage_info]
      @description = attributes[:description]

      @permissions = Set.new(attributes[:permissions])
      @owner_only = !!attributes[:owner_only]
    end

    def call(event, args)
      if args.length < @arg_count.first
        raise Yuyuko::Errors::ArgumentError, kind: :few
      elsif @arg_count.last > -1 && args.length > @arg_count.last
        raise Yuyuko::Errors::ArgumentError, kind: :many
      end

      owners = event.bot.get_config('owner_id')
      if owners && @owner_only && !owners.include?(event.user.id)
        raise Yuyuko::Errors::AccessError, kind: :owner
      end

      user_perms = event.bot.permissions(event.user)
      if user_perms && !user_perms.superset?(@permissions)
        raise Yuyuko::Errors::AccessError, kind: :permissions
      end

      event.user.roles.each do |role|
        role_perms = event.bot.permissions(role)
        if role_perms && !role_perms.superset?(@permissions)
          raise Yuyuko::Errors::AccessError, kind: :permissions
        end
      end

      @block.call(event, *args)
    end
  end

  class CommandEvent < MijDiscord::Events::Message
    attr_reader :command

    def initialize(bot, message, command)
      super(bot, message)

      @command = command
    end
  end

  class CommandGroup
    attr_reader :name

    attr_accessor :delay

    attr_reader :permissions

    attr_accessor :owner_only

    def initialize(name, attributes = {})
      @name = name

      @delay = attributes[:delay]

      @permissions = Set.new(attributes[:permissions])
      @owner_only = !!attributes[:owner_only]
    end
  end
end