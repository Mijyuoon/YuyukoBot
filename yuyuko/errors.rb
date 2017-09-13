module Yuyuko::Errors
  class Error < StandardError
    attr_reader :params

    def initialize(msg, **params)
      params, msg = msg, msg.delete(:msg) if msg.is_a?(Hash)

      super(msg)

      @params = params
    end

    def localized
      Yuyuko.tr(message, @params)
    end
  end

  class SyntaxError < Error; end

  class ArgumentError < Error; end

  class AccessError < Error; end
end