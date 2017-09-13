module MijDiscord::Data
  def self.yuyuko_embed(embed, params)
    case embed
      when Hash
        Yuyuko.localize!(embed, params)
      when String
        Yuyuko.localize!(Yuyuko.cfg(embed, true), params)
      when NilClass
        embed
      else raise ArgumentError, 'Argument is not an embed!'
    end
  end

  class Channel
    def send_embed(embed, text = '', **params)
      send_message(text: text, embed: MijDiscord::Data.yuyuko_embed(embed, params))
    end
  end

  class Message
    include Yuyuko::Interaction::MessageExtensions

    def reply_embed(embed, text = '', **params)
      @channel.send_embed(embed, text, **params)
    end

    def edit_embed(embed, text = '', **params)
      edit(text: text, embed: MijDiscord::Data.yuyuko_embed(embed, params))
    end
  end
end
