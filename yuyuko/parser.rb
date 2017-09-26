module Yuyuko::Parser
  module ArgumentConcat
    MATCHER = /\A(```|`(?!`))(.*?)\1\z/m

    def call(input)
      [ input.gsub(MATCHER, '\2') ]
    end

    module_function :call
  end

  module ArgumentWords
    MATCHER = /\G\s*(?>```(.*?)```|([^\s\"`]+)|`([^`]*)`|(\"\")|"((?:[^\"]|\"\")*)"|(\S))(\s|\z)?/m

    def call(input)
      words, accum = [], ''

      input.scan(MATCHER) do |blk, rw, bw, esc, qw, crap, sep|
        raise Yuyuko::Errors::SyntaxError, 'errors.bad_quotes' if crap

        if blk
          unless accum.empty?
            words << accum
            accum = ''
          end

          words << blk
        else
          accum << (rw || bw || (esc || qw)&.gsub('""', '"'))

          if sep
            words << accum
            accum = ''
          end
        end
      end

      words
    end

    module_function :call
  end

  module TypedArguments
    DISCORD_TYPES = {
      user: MijDiscord::Data::User,
      role: MijDiscord::Data::Role,
      emoji: MijDiscord::Data::Emoji,
      member: MijDiscord::Data::Member,
    }.freeze

    def call(items, types, server = nil)
      return items unless types

      items.each_with_index.map do |item, i|
        type = types[i] || types.last
        next item if type.nil?

        item = parse_item(item, type, server)
        raise Yuyuko::Errors::SyntaxError.new('errors.arg_parse', index: i+1) if item.nil?

        item == NilClass ? nil : item
      end
    end

    module_function :call

    private

    def self.parse_item(item, type, server)
      if type.is_a?(Array)
        return type.reduce(nil) do |a,x|
          a.nil? ? parse_item(item, x, server) : a
        end
      end

      case type
        when :string
          item
        when :symbol
          item.to_sym
        when :integer
          Integer(item)
        when :float
          Float(item)
        when :rational
          Rational(item)
        when :time
          Time.parse(item).utc
        when :bool
          case item.downcase
            when 'true', 'yes', 'on' then true
            when 'false', 'no', 'off' then false
            else raise ArgumentError
          end
        when :regexp
          Regexp.new(item)
        when :nil
          NilClass
        when :yaml
          YAML::load(item.gsub(/\A(?:ya?ml)\n/, ''))
        when :member, :role, :emoji
          result = server&.bot&.parse_mention(item, server)
          result.is_a?(DISCORD_TYPES[type]) ? result : nil
        when :user
          result = server&.bot&.parse_mention(item, nil)
          result.is_a?(DISCORD_TYPES[type]) ? result : nil
        when :invite
          server&.bot&.parse_invite_code(item)
        else
          type.respond_to?(:from_argument) && type.from_argument(item)
      end
    rescue ArgumentError, RegexpError, Psych::Exception
      nil
    end
  end
end